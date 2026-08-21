/**
 * 图片附件工具（视觉模型发图能力）
 *
 * 职责：
 *  - 相册选图：PhotoViewPicker（系统相册选择，无需申请读图权限）
 *  - 系统相机拍照：CameraPicker（拉起系统相机，无需 CAMERA 权限）
 *  - 图片压缩与编码：PNG/WebP/JPEG 统一缩放（长边 ≤ 1024px）+ JPEG 质量 80 压缩，
 *    GIF 保持原格式不压缩（保留动画）；结果以 Base64 存入 ImageAttachment
 *
 * 格式支持（与 DeepSeek 视觉模型文档一致）：JPEG / PNG / GIF / WebP
 * MIME 类型按文件内容魔数判断（而非文件名扩展名），与模型侧判断口径一致
 */

import { common } from "@kit.AbilityKit";
import { photoAccessHelper } from "@kit.MediaLibraryKit";
import { camera, cameraPicker } from "@kit.CameraKit";
import { fileIo as fs, fileUri } from "@kit.CoreFileKit";
import { image } from "@kit.ImageKit";
import buffer from "@ohos.buffer";
import { ImageAttachment } from "../model/Message";
import { generateId } from "../common/Utils";
import { Logger } from "../common/Logger";

/* 压缩参数 */
const MAX_DIMENSION: number = 1024; // 长边上限（px）：超过则等比缩放
const JPEG_QUALITY: number = 80; // JPEG 压缩质量（1-100）

/* MIME 类型常量 */
const MIME_JPEG: string = "image/jpeg";
const MIME_PNG: string = "image/png";
const MIME_WEBP: string = "image/webp";
const MIME_GIF: string = "image/gif";

export class ImageUtil {
  private static instance: ImageUtil;

  private constructor() {}

  static getInstance(): ImageUtil {
    if (!ImageUtil.instance) {
      ImageUtil.instance = new ImageUtil();
    }
    return ImageUtil.instance;
  }

  /**
   * 从系统相册多选图片并压缩编码为 ImageAttachment 列表
   * @param context UIAbilityContext（系统弹窗宿主）
   * @param maxCount 本次最多可选数量（含已选数量，调用方按剩余额度传入）
   * @returns 压缩后的图片附件列表（单张失败跳过，不中断整批）
   */
  async pickFromGallery(context: common.UIAbilityContext, maxCount: number): Promise<ImageAttachment[]> {
    if (maxCount <= 0) {
      return [];
    }
    const picker = new photoAccessHelper.PhotoViewPicker();
    const result = await picker.select({
      MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, // 仅图片
      maxSelectNumber: maxCount,
    });
    const attachments: ImageAttachment[] = [];
    for (const uri of result.photoUris) {
      try {
        const mime: string = this.detectMimeType(uri);
        const att = await this.compressAndEncode(uri, mime, this.extractFileName(uri));
        attachments.push(att);
      } catch (e) {
        /* 单张失败（损坏/格式异常）跳过，不阻塞其余图片 */
        Logger.error(`ImageUtil.pickFromGallery compress failed: ${JSON.stringify(e)}`);
      }
    }
    return attachments;
  }

  /**
   * 拉起系统相机拍照并压缩编码为 ImageAttachment
   * 照片写入应用缓存目录临时文件，压缩完成后删除临时文件
   * @param context UIAbilityContext
   * @returns 压缩后的图片附件；用户取消返回 null
   */
  async capturePhoto(context: common.UIAbilityContext): Promise<ImageAttachment | null> {
    const tmpPath = `${context.cacheDir}/camera_${Date.now()}.jpg`;
    /* 预创建临时文件（CameraPicker 的 saveUri 需要文件已存在或可创建） */
    const tmpFile = fs.openSync(tmpPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    fs.closeSync(tmpFile);
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK, // 默认后置（用户可在相机内切换）
        saveUri: fileUri.getUriFromPath(tmpPath),
      };
      const result = await cameraPicker.pick(
        context,
        [cameraPicker.PickerMediaType.PHOTO],
        profile,
      );
      if (result.resultCode !== 0) {
        return null; // 用户取消
      }
      /* 拍照结果可能写回 saveUri 或另存 resultUri，统一以 resultUri 为准 */
      const uri: string = result.resultUri.length > 0 ? result.resultUri : fileUri.getUriFromPath(tmpPath);
      return await this.compressAndEncode(uri, MIME_JPEG, `IMG_${Date.now()}.jpg`);
    } catch (e) {
      Logger.error(`ImageUtil.capturePhoto failed: ${JSON.stringify(e)}`);
      return null;
    } finally {
      /* 清理临时文件（成功压缩后原始文件已不再需要） */
      try {
        fs.unlinkSync(tmpPath);
      } catch (e) {
        /* 删除失败可忽略 */
      }
    }
  }

  /**
   * 读取图片文件 → 按类型处理 → Base64 编码
   * PNG/WebP/JPEG：缩放（长边 ≤1024）后压缩为 JPEG；GIF：原样保留（不压缩，保留动画）
   * @param uri 图片文件 URI（相册 URI 或应用沙箱路径）
   * @param mimeType 检测到的 MIME 类型（image/jpeg | png | webp | gif）
   * @param name 文件名（展示用）
   * @returns ImageAttachment（data 为不含 data: 前缀的纯 Base64）
   */
  private async compressAndEncode(uri: string, mimeType: string, name: string): Promise<ImageAttachment> {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const raw = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, raw);
      /* GIF 原样编码（压缩会丢动画），其余统一压缩为 JPEG */
      const isGif: boolean = mimeType === MIME_GIF;
      let data: string;
      if (isGif) {
        data = buffer.from(raw).toString("base64");
      } else {
        data = await this.compressToJpegBase64(raw);
      }
      return {
        id: generateId(),
        mimeType: isGif ? MIME_GIF : MIME_JPEG,
        data: data,
        name: name,
      };
    } finally {
      fs.closeSync(file);
    }
  }

  /**
   * 图片字节 → 等比缩放（长边 ≤ MAX_DIMENSION）→ JPEG 压缩 → Base64
   * @param srcData 原始图片字节
   * @returns JPEG Base64 字符串
   */
  private async compressToJpegBase64(srcData: ArrayBuffer): Promise<string> {
    const src = image.createImageSource(srcData);
    try {
      const info = await src.getImageInfo();
      const w: number = info.size.width;
      const h: number = info.size.height;
      let pixelMap: image.PixelMap;
      if (w > MAX_DIMENSION || h > MAX_DIMENSION) {
        /* 长边超限：等比缩放到 MAX_DIMENSION（短边跟随，保持宽高比） */
        const scale: number = MAX_DIMENSION / Math.max(w, h);
        pixelMap = await src.createPixelMap({
          desiredSize: { width: Math.max(1, Math.round(w * scale)), height: Math.max(1, Math.round(h * scale)) },
        });
      } else {
        pixelMap = await src.createPixelMap();
      }
      try {
        const packer = image.createImagePacker();
        try {
          const jpegData: ArrayBuffer = await packer.packing(pixelMap, {
            format: "image/jpeg",
            quality: JPEG_QUALITY,
          });
          return buffer.from(jpegData).toString("base64");
        } finally {
          packer.release();
        }
      } finally {
        pixelMap.release();
      }
    } finally {
      src.release();
    }
  }

  /**
   * 按文件内容魔数检测 MIME 类型（而非文件名扩展名）
   * JPEG: FF D8 FF | PNG: 89 50 4E 47 | GIF: GIF8 | WebP: RIFF....WEBP
   * 未识别时回退 image/jpeg（压缩流程对格式不敏感，统一转 JPEG）
   */
  private detectMimeType(uri: string): string {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const head = new ArrayBuffer(12);
      const readLen: number = fs.readSync(file.fd, head);
      const u8 = new Uint8Array(head);
      if (readLen >= 3 && u8[0] === 0xff && u8[1] === 0xd8 && u8[2] === 0xff) {
        return MIME_JPEG;
      }
      if (readLen >= 4 && u8[0] === 0x89 && u8[1] === 0x50 && u8[2] === 0x4e && u8[3] === 0x47) {
        return MIME_PNG;
      }
      if (readLen >= 6 && u8[0] === 0x47 && u8[1] === 0x49 && u8[2] === 0x46 && u8[3] === 0x38) {
        return MIME_GIF;
      }
      if (readLen >= 12 && u8[0] === 0x52 && u8[1] === 0x49 && u8[2] === 0x46 && u8[3] === 0x46
        && u8[8] === 0x57 && u8[9] === 0x45 && u8[10] === 0x42 && u8[11] === 0x50) {
        return MIME_WEBP;
      }
      return MIME_JPEG;
    } finally {
      fs.closeSync(file);
    }
  }

  /* 从 URI 提取文件名（最后一段）；解析失败回退时间戳名 */
  private extractFileName(uri: string): string {
    const idx = uri.lastIndexOf('/');
    const name = idx >= 0 ? uri.substring(idx + 1) : uri;
    return name.length > 0 ? name : `IMG_${Date.now()}.jpg`;
  }
}
