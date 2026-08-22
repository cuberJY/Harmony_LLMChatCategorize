/**
 * 文件附件解析服务（txt / md / pdf 文件输入能力）
 *
 * 职责：
 *  - 系统文档选择器选文件：DocumentViewPicker（无需存储权限，返回带临时读权限的 URI）
 *  - txt / md：直接读取 UTF-8 文本存入 textContent（超长截断）→ 发送时走 input_text 文本通道
 *  - pdf：复制到应用沙箱 → PDF Kit 逐页渲染为 PixelMap → JPEG 压缩编码 Base64 存入 pageImages
 *    → 发送时逐页走 input_image 视觉通道（项目 API 20 无 getTextContent 文本提取，故渲染成图）
 *
 * 限制（用户决策）：
 *  - 单文件（DocumentViewPicker maxSelectNumber=1，重复选择替换）
 *  - 单文件 ≤ 20MB
 *  - PDF 最多渲染 100 页；全部页面 Base64 总量 ≤ MAX_TOTAL_BASE64（请求体保护，达到即停止后续页）
 *  - txt/md 提取文本 ≤ MAX_TEXT_LENGTH（截断）
 *
 * 失败语义：pickAndParse 返回 null = 用户取消；抛异常 = 解析失败（超限/损坏），由调用方 Toast 提示
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

export class FileParser {
  private static instance: FileParser;

  private constructor() {}

  static getInstance(): FileParser {
    if (!FileParser.instance) {
      FileParser.instance = new FileParser();
    }
    return FileParser.instance;
  }

  /**
   * 弹出系统文档选择器选择单个文件并解析为 FileAttachment
   * @param context UIAbilityContext（系统弹窗宿主）
   * @returns 解析成功的附件；用户取消返回 null；解析失败（超限/损坏）抛异常由调用方提示
   */
  async pickAndParse(context: common.UIAbilityContext): Promise<FileAttachment | null> {
    const dp = new picker.DocumentViewPicker(context);
    const uris: string[] = await dp.select({
      maxSelectNumber: 1, // 单文件：再次选择即替换
      fileSuffixFilters: SUPPORTED_EXTS,
    });
    if (uris.length === 0) {
      return null; // 用户取消
    }
    return await this.parse(context, uris[0]);
  }

  /**
   * 解析单个文件 URI → FileAttachment
   * txt/md 读文本；pdf 渲染页面为 Base64 图片列表
   */
  private async parse(context: common.UIAbilityContext, uri: string): Promise<FileAttachment> {
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
    if (ext === "txt" || ext === "md") {
      return this.parseText(uri, name, ext, size);
    }
    if (ext === "pdf") {
      return await this.parsePdf(context, uri, name, size);
    }
    throw new Error(`不支持的文件类型：${name}`);
  }

  /** txt / md：读取 UTF-8 文本，超长截断 */
  private parseText(uri: string, name: string, ext: string, size: number): FileAttachment {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      /* readSync 需要 ArrayBuffer 缓冲区（与 ImageUtil 一致）；decodeToString 需要 Uint8Array，故解码前转换 */
      const raw = new ArrayBuffer(size);
      if (size > 0) {
        fs.readSync(file.fd, raw);
      }
      const decoder = util.TextDecoder.create("utf-8");
      let text: string = decoder.decodeToString(new Uint8Array(raw));
      if (text.length > MAX_TEXT_LENGTH) {
        text = text.substring(0, MAX_TEXT_LENGTH);
      }
      return {
        id: generateId(),
        name: name,
        ext: ext,
        size: size,
        textContent: text,
        pageImages: [], // 文本文件无页面图
      };
    } finally {
      fs.closeSync(file);
    }
  }

  /**
   * pdf：复制到沙箱（PDF Kit 仅支持沙箱路径）→ 逐页渲染为 PixelMap → JPEG Base64
   * 逐页累计体积，达到总量上限即停止后续页面（保护请求体不过大）
   */
  private async parsePdf(
    context: common.UIAbilityContext,
    uri: string,
    name: string,
    size: number,
  ): Promise<FileAttachment> {
    const destPath: string = `${context.cacheDir}/file_${Date.now()}.pdf`;
    /* picker 返回的 document URI 无法直接 copyFileSync，先 openSync 取 fd 再按 fd 拷贝到沙箱，
       之后由 PDF Kit（仅支持沙箱路径）加载 */
    const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const destFile = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.copyFileSync(srcFile.fd, destFile.fd);
    } finally {
      fs.closeSync(srcFile);
      fs.closeSync(destFile);
    }
    try {
      const doc = new pdfService.PdfDocument();
      await doc.loadDocument(destPath);
      try {
        const pageCount: number = doc.getPageCount();
        const pagesToRender: number = Math.min(pageCount, MAX_PDF_PAGES);
        const pageImages: string[] = [];
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
        return {
          id: generateId(),
          name: name,
          ext: "pdf",
          size: size,
          textContent: "", // API 20 无 PDF 文本提取，页面图走视觉通道
          pageImages: pageImages,
        };
      } finally {
        /* 释放文档资源（API 20 方法名 releaseDocument；释放失败可忽略） */
        try {
          doc.releaseDocument();
        } catch (e) {
          /* 忽略释放异常 */
        }
      }
    } finally {
      /* 删除沙箱临时 PDF */
      try {
        fs.unlinkSync(destPath);
      } catch (e) {
        Logger.warn(`FileParser unlink temp pdf failed: ${JSON.stringify(e)}`);
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
