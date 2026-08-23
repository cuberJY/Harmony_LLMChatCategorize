/**
 * 文件附件服务（txt / md / pdf 文件输入能力）—— 阶段1 延迟解析
 *
 * 职责（延迟解析模式：选中文件仅持久化源文件，发送时才解析内容）：
 *  - 选文件：DocumentViewPicker（无需存储权限，返回带临时读权限的 URI）
 *  - pickAndSave(context)：弹系统文档选择器选单个文件 → 拷贝源文件到沙箱持久目录
 *    {@link #attachmentsDir}（filesDir/attachments/）→ 返回 FileAttachment（含 localPath + 元数据，
 *    textContent / pageImages 留空）。此阶段不解析，仅保存源文件。
 *  - parseForSend(file)：发送时把选中的文件解析结果填回附件：
 *      - txt / md：读 UTF-8 文本 → textContent（走 input_text 文本通道，所有模型可用）
 *      - pdf：PDF Kit 逐页渲染 → JPEG Base64 → pageImages（走 input_image 视觉通道，仅视觉模型）
 *
 * 沙箱持久目录而非 cacheDir 的原因：源文件需保留供【阶段5 历史重解析】与【Preview Kit 预览】使用。
 *
 * 限制（用户决策）：
 *  - 单文件（DocumentViewPicker maxSelectNumber=1，重复选择替换）
 *  - 单文件 ≤ 20MB
 *  - PDF 最多渲染 100 页；全部页面 Base64 总量 ≤ MAX_TOTAL_BASE64（请求体保护，达到即停止后续页）
 *  - txt/md 提取文本 ≤ MAX_TEXT_LENGTH（截断）
 *
 * 失败语义：pickAndSave 返回 null = 用户取消；抛异常 = 解析失败（超限/损坏），由调用方 Toast 提示
 */

import { common } from "@kit.AbilityKit";
import { picker, fileIo as fs } from "@kit.CoreFileKit";
import { image } from "@kit.ImageKit";
import { pdfService } from "@kit.PDFKit";
import buffer from "@ohos.buffer";
import { util } from "@kit.ArkTS";
import { FileAttachment } from "../model/Message";
import { generateId } from "../common/Utils";
import { Logger } from "../common/Logger";

/* 支持的文件后缀（DocumentViewPicker fileSuffixFilters 过滤） */
const SUPPORTED_EXTS: string[] = [".txt", ".md", ".pdf"];
/* 单文件大小上限（字节，20MB） */
const MAX_FILE_SIZE: number = 20 * 1024 * 1024;
/* PDF 最大渲染页数 */
const MAX_PDF_PAGES: number = 100;
/* txt/md 提取文本长度上限（字符，超长截断避免请求体过大） */
const MAX_TEXT_LENGTH: number = 30000;
/* PDF 全部页面 Base64 总量上限（请求体保护，累计达到即停止后续页面渲染） */
const MAX_TOTAL_BASE64: number = 12 * 1024 * 1024;
/* PDF 页渲染图 JPEG 压缩质量 */
const JPEG_QUALITY: number = 80;
/* 附件持久化子目录名（位于应用 filesDir 下；源文件保留供历史重解析/预览） */
const ATTACHMENTS_DIR: string = "attachments";

export class FileParser {
  private static instance: FileParser;

  private constructor() {}

  static getInstance(): FileParser {
    if (!FileParser.instance) {
      FileParser.instance = new FileParser();
    }
    return FileParser.instance;
  }

  /** 附件持久化目录（filesDir/attachments），不存在则创建 */
  private ensureAttachmentsDir(context: common.UIAbilityContext): string {
    const dir: string = `${context.filesDir}/${ATTACHMENTS_DIR}`;
    try {
      fs.mkdirSync(dir);
    } catch (e) {
      /* 目录已存在时 mkdirSync 抛异常，这里忽略即可 */
    }
    return dir;
  }

  /** 把源文件拷贝到沙箱持久目录，返回持久化后的 FileAttachment（未解析，内容留空） */
  private persistSource(context: common.UIAbilityContext, uri: string, name: string, ext: string, size: number): FileAttachment {
    const dir: string = this.ensureAttachmentsDir(context);
    const id: string = generateId();
    const destPath: string = `${dir}/${id}.${ext}`;
    const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const destFile = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      if (srcFile !== undefined && destFile !== undefined) {
        fs.copyFileSync(srcFile.fd, destFile.fd);
      }
    } finally {
      try {
        fs.closeSync(srcFile);
      } catch (e) {
        Logger.warn(`FileParser persist close src fail: ${JSON.stringify(e)}`);
      }
      try {
        fs.closeSync(destFile);
      } catch (e) {
        Logger.warn(`FileParser persist close dest fail: ${JSON.stringify(e)}`);
      }
    }
    return {
      id: id,
      name: name,
      ext: ext,
      size: size,
      localPath: destPath,
      textContent: "",
      pageImages: [],
    };
  }

  /**
   * 弹出系统文档选择器选择单个文件，持久化并返回未解析的 FileAttachment
   * @param context UIAbilityContext（系统弹窗宿主）
   * @returns 未解析的附件（含 localPath）；用户取消返回 null；超限/损坏抛异常由调用方提示
   */
  async pickAndSave(context: common.UIAbilityContext): Promise<FileAttachment | null> {
    const dp = new picker.DocumentViewPicker(context);
    const uris: string[] = await dp.select({
      maxSelectNumber: 1, // 单文件：再次选择即替换
      fileSuffixFilters: SUPPORTED_EXTS,
    });
    if (uris.length === 0) {
      return null; // 用户取消
    }
    const uri = uris[0];
    const name: string = this.extractFileName(uri);
    const ext: string = this.extractExt(name);
    /* 文件大小校验（picker 已按后缀过滤，此处防御未知来源） */
    const sizeFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    let size: number;
    try {
      size = fs.statSync(sizeFile.fd).size;
    } finally {
      fs.closeSync(sizeFile);
    }
    if (size > MAX_FILE_SIZE) {
      throw new Error(`文件过大（超过 20MB）：${name}`);
    }
    if (ext === "txt" || ext === "md" || ext === "pdf") {
      return this.persistSource(context, uri, name, ext, size);
    }
    throw new Error(`不支持的文件类型：${name}`);
  }

  /**
   * 发送时解析附件内容，填回 textContent / pageImages
   * @param file 已持久化（localPath 非空）或未解析的附件；解析结果直接写回该对象字段
   * txt/md → textContent；pdf → pageImages。已解析过（有内容）则直接返回。
   */
  parseForSend(file: FileAttachment): Promise<void> {
    /* 幂等：已解析过（文本或页面图已填充）则跳过 */
    if (file.textContent.length > 0 || file.pageImages.length > 0) {
      return Promise.resolve();
    }
    const ext: string = file.ext;
    const localPath: string = file.localPath;
    if (ext === "txt" || ext === "md") {
      const text: string = this.readText(localPath);
      file.textContent = text;
      return Promise.resolve();
    }
    if (ext === "xlsx" || ext === "xls") {
      /* xlsx 解析暂缓（@archermind/exceljs 存在 data1904 已知 bug，后续方案再定） */
      throw new Error(`暂不支持解析 ${ext.toUpperCase()} 文件`);
    }
    if (ext === "pdf") {
      return this.parsePdf(localPath, file, file.size);
    }
    /* 未知扩展名：抛异常提示（正常情况下 pickAndSave 已过滤） */
    throw new Error(`不支持的文件类型：${file.name}`);
  }

  /** 读取 UTF-8 文件文本，超长截断 */
  private readText(path: string): string {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const st = fs.statSync(file.fd);
      const raw = new ArrayBuffer(st.size);
      if (st.size > 0) {
        fs.readSync(file.fd, raw);
      }
      const decoder = util.TextDecoder.create("utf-8");
      let text: string = decoder.decodeToString(new Uint8Array(raw));
      if (text.length > MAX_TEXT_LENGTH) {
        text = text.substring(0, MAX_TEXT_LENGTH);
      }
      return text;
    } finally {
      fs.closeSync(file);
    }
  }

  /**
   * pdf：从沙箱 localPath 加载 → PDF Kit 逐页渲染 → JPEG Base64 → pageImages
   * 逐页累计体积，达到总量上限即停止后续页面（保护请求体不过大）
   */
  private async parsePdf(path: string, file: FileAttachment, size: number): Promise<void> {
    const pageImages: string[] = [];
    const doc = new pdfService.PdfDocument();
    try {
      await doc.loadDocument(path);
      const pageCount: number = doc.getPageCount();
      const pagesToRender: number = Math.min(pageCount, MAX_PDF_PAGES);
      let totalBytes: number = 0;
      for (let i = 0; i < pagesToRender; i++) {
        if (totalBytes >= MAX_TOTAL_BASE64) {
          break; // 已到请求体总量上限，停止渲染剩余页
        }
        const page: pdfService.PdfPage = doc.getPage(i);
        const pixelMap: image.PixelMap = await page.getPagePixelMap();
        try {
          const packer = image.createImagePacker();
          try {
            const jpegData: ArrayBuffer = await packer.packing(pixelMap, {
              format: "image/jpeg",
              quality: JPEG_QUALITY,
            });
            const b64: string = buffer.from(jpegData).toString("base64");
            totalBytes += b64.length;
            pageImages.push(b64);
          } finally {
            packer.release();
          }
        } finally {
          pixelMap.release();
        }
      }
      if (pageImages.length === 0) {
        throw new Error("PDF 解析失败：未渲染出有效页面");
      }
      file.pageImages = pageImages;
    } finally {
      /* 释放文档资源（API 20 方法名 releaseDocument；释放失败可忽略） */
      try {
        doc.releaseDocument();
      } catch (e) {
        /* 忽略释放异常 */
      }
    }
  }

  /* 从 URI 提取文件名（最后一段）；解析失败回退时间戳名 */
  private extractFileName(uri: string): string {
    const idx = uri.lastIndexOf('/');
    const name = idx >= 0 ? uri.substring(idx + 1) : uri;
    return name.length > 0 ? name : `file_${Date.now()}`;
  }

  /* 提取小写扩展名（含点转纯后缀：xxx.txt → txt）；无后缀返回空串 */
  private extractExt(name: string): string {
    const idx = name.lastIndexOf('.');
    if (idx < 0 || idx === name.length - 1) {
      return "";
    }
    return name.substring(idx + 1).toLowerCase();
  }
}