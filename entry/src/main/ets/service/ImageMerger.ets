/**
 * 图片拼接工具
 * 将 ExportCardLayer 分段截取的多张 PixelMap 纵向拼接为一张长图。
 * 背景：单组件截图高度受渲染缓冲上限约束（约 16000px），长对话卡片需分段截图；
 * 图片分享要求单张图片文件，故用 drawing.Canvas 把各段按统一宽度等比对齐后拼接。
 *
 * 拼接规则：
 *  - 各段统一对齐到 targetWidth（窄段等比放大，不变形）；
 *  - 拼接总高超 maxTotalH 时整体等比缩小（避免长图过大导致内存溢出）；
 *  - 背景填充卡片浅灰，避免拼接边缘露出透明像素。
 */

import { image } from '@kit.ImageKit';
import { drawing, common2D } from '@kit.ArkGraphics2D';
import { SHARE_CARD_BG } from '../common/ShareStyle';

/* 拼接段信息：缩放后目标尺寸 + 原图尺寸（drawImageRectWithSrc 的源区域） */
class SegSize {
  w: number = 0; // 缩放后宽（统一 targetWidth，超限缩小后也统一）
  h: number = 0; // 缩放后高（等比）
  srcW: number = 0; // 原图宽
  srcH: number = 0; // 原图高
}

/** 图片拼接总高上限（px）：超限整体等比缩小，避免长图缓冲过大导致内存溢出 */
export const IMAGE_MERGE_MAX_HEIGHT: number = 20000;

export class ImageMerger {
  /**
   * 纵向拼接多段 PixelMap 为一张长图
   * @param segments 各段截图（ExportCardLayer 逐段 componentSnapshot 得到；拼接后内部 release）
   * @param targetWidth 拼接目标宽度（px；各段等比对齐，窄段放大不变形）
   * @param maxTotalH 拼接总高上限（px，防内存溢出），超限整体等比缩小
   * @returns 拼接后的长图 PixelMap（调用方负责 release）
   */
  static async mergeVertical(segments: image.PixelMap[], targetWidth: number, maxTotalH: number): Promise<image.PixelMap> {
    /* 第一步：读取各段尺寸，等比换算到统一宽度，累加总高 */
    const sizes: SegSize[] = [];
    let totalH: number = 0;
    for (const seg of segments) {
      const info: image.ImageInfo = await seg.getImageInfo();
      const s: SegSize = new SegSize();
      s.srcW = info.size.width;
      s.srcH = info.size.height;
      s.w = targetWidth;
      s.h = Math.max(1, Math.round(s.srcH * targetWidth / s.srcW));
      sizes.push(s);
      totalH += s.h;
    }

    /* 第二步：总高超限时整体等比缩小（保持统一宽度不变形） */
    if (totalH > maxTotalH) {
      const ratio: number = maxTotalH / totalH;
      let newTotal: number = 0;
      for (const s of sizes) {
        s.w = Math.max(1, Math.round(s.w * ratio));
        s.h = Math.max(1, Math.round(s.h * ratio));
        newTotal += s.h;
      }
      totalH = newTotal;
    }

    /* 第三步：创建目标长图缓冲（RGBA 8888），Canvas 填充背景并逐段绘制 */
    const targetW: number = sizes.length > 0 ? sizes[0].w : targetWidth;
    const buffer: ArrayBuffer = new ArrayBuffer(targetW * totalH * 4);
    const opts: image.InitializationOptions = {
      size: { width: targetW, height: totalH },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
    };
    const target: image.PixelMap = await image.createPixelMap(buffer, opts);
    const canvas = new drawing.Canvas(target);
    /* 卡片浅灰背景：拼接边缘无缝连续，避免露出透明黑 */
    canvas.clear(parseInt(SHARE_CARD_BG.replace('#', 'FF'), 16));

    let y: number = 0;
    for (let i = 0; i < segments.length; i++) {
      /* common2D.Rect 为接口类型，用带类型标注的对象字面量构造（ArkTS 不允许 new 接口） */
      const srcRect: common2D.Rect = {
        left: 0,
        top: 0,
        right: sizes[i].srcW,
        bottom: sizes[i].srcH,
      };
      const dstRect: common2D.Rect = {
        left: 0,
        top: y,
        right: sizes[i].w,
        bottom: y + sizes[i].h,
      };
      canvas.drawImageRectWithSrc(segments[i], srcRect, dstRect, new drawing.SamplingOptions());
      y += sizes[i].h;
      segments[i].release(); // 每段用完即释放，控制峰值内存
    }
    return target;
  }
}
