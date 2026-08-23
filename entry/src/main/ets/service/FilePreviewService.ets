/**
 * FilePreviewService —— 文件预览服务（Preview Kit 系统预览）
 *
 * 作用：对沙箱内已持久化的文件附件（txt / pdf / docx / pptx / xlsx）调起系统预览。
 * 流程：
 *  1. 沙箱 localPath（filesDir/attachments/ 下）→ 构造带包名的 URI（file://{bundleName}{path}），
 *     系统预览需以此格式访问沙箱文件（Preview Kit 不支持直接传裸路径）。
 *  2. mimeType 映射表：各格式对应的标准 MIME（写错会导致预览无法打开）。
 *  3. canPreview 预检（URI 可预览才 openPreview），失败抛异常由调用方 toast。
 *
 * 限制（用户决策）：
 *  - 入口仅对话气泡内已发送的文件卡片（预览条不预览）
 *  - md 不预览（Preview Kit 文本类型列表未声明 md，点击无动作，由 FileCard 层拦截）
 *  - Preview Kit 仅中国境内可用；模拟器不支持 pdf/office 预览（需真机验证）
 *  - Office 预览借系统 WPS 能力（模态窗展示，含"WPS 提供技术支持"字样）
 */

import { common } from "@kit.AbilityKit";
import { filePreview } from "@kit.PreviewKit";
import { FileAttachment } from "../model/Message";

export class FilePreviewService {
  private static instance: FilePreviewService;

  private constructor() {}

  static getInstance(): FilePreviewService {
    if (!FilePreviewService.instance) {
      FilePreviewService.instance = new FilePreviewService();
    }
    return FilePreviewService.instance;
  }

  /** 各格式标准 MIME（Preview Kit 要求与文件一致，否则无法打开）；md 不在映射内（不预览） */
  private mimeOf(ext: string): string {
    if (ext === "pdf") {
      return "application/pdf";
    }
    if (ext === "txt") {
      return "text/plain";
    }
    if (ext === "docx") {
      return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    }
    if (ext === "pptx") {
      return "application/vnd.openxmlformats-officedocument.presentationml.presentation";
    }
    if (ext === "xlsx") {
      return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    }
    return "";
  }

  /** 该扩展名是否支持预览（md 除外） */
  canPreviewExt(ext: string): boolean {
    return this.mimeOf(ext).length > 0;
  }

  /**
   * 调起系统预览
   * @param context UIAbilityContext（提供 bundleName 构造沙箱 URI）
   * @param file 已持久化的文件附件（localPath 非空）
   * @throws 不支持格式 / canPreview 为 false / openPreview 失败时抛异常，调用方 toast
   */
  async preview(context: common.UIAbilityContext, file: FileAttachment): Promise<void> {
    const mime: string = this.mimeOf(file.ext);
    if (mime.length === 0 || file.localPath.length === 0) {
      throw new Error(`不支持预览的文件类型：${file.name}`);
    }
    /* 带包名 URI：Preview Kit 仅识别 file://{bundleName}{沙箱路径} */
    const bundleName: string = context.abilityInfo.bundleName;
    const uri: string = `file://${bundleName}${file.localPath}`;
    const ok: boolean = await filePreview.canPreview(context, uri);
    if (!ok) {
      throw new Error(`系统不支持预览该文件：${file.name}`);
    }
    const info: filePreview.PreviewInfo = {
      title: file.name,
      uri: uri,
      mimeType: mime,
    };
    await filePreview.openPreview(context, info);
  }
}
