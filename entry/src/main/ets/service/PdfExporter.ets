/**
 * PDF 导出服务
 * 将「分享卡片」的长图（ComponentSnapshot 组件截图）按 A4 页面尺寸切分为多页，
 * 用 PDF Kit（@kit.PDFKit / pdfService）逐页嵌入图片，生成多页 A4 PDF 文件。
 *
 * 为什么放弃 ArkWeb createPdf：
 *   createPdf 按 Web 组件当前渲染宽度导出到 A4，窄屏布局导出后内容偏左、
 *   各页宽度不一致、末尾出现空白页；@media print 与专用 A4 宽 Web 多次修复仍不可靠。
 *   图片方案用 ArkUI 原生排版 + 组件截图，PDF 页面即图片，各页宽度一致、无空白，
 *   分页规则简单（页宽固定，按 A4 页高等比切分长图）。
 *
 * 关键 API：
 *   - @kit.PDFKit（pdfService.PdfDocument）：createDocument 建页 / insertBlankPage
 *     补页 / PdfPage.addImageObject 铺图（按文件路径读取）/ saveDocument 落盘
 *   - @kit.ImageKit：image.createImageSource + createPixelMap({desiredRegion})
 *     按原图坐标切段，每段按页宽等比放大后写临时 PNG 供 addImageObject 读取
 */

import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { pdfService } from '@kit.PDFKit';
import { fileIo as fs } from '@kit.CoreFileKit';

/* A4 页面像素尺寸（150dpi：8.27in × 150 ≈ 1240px，11.69in × 150 ≈ 1754px）。
   页面即图片，宽度固定保证各页一致 */
const PDF_PAGE_WIDTH: number = 1240;
const PDF_PAGE_HEIGHT: number = 1754;

export class PdfExporter {
  /**
   * 将长图导出为多页 A4 PDF 文件
   * @param context UIAbilityContext（cacheDir 用于临时切分图片与最终 PDF）
   * @param pixelMap 分享卡片长图（ComponentSnapshot 截图）
   * @param title 分享标题（用于 PDF 文件名）
   * @returns 生成的 PDF 文件路径
   */
  static async export(context: common.UIAbilityContext, pixelMap: image.PixelMap, title: string): Promise<string> {
    /* 文件名：去除标题中的非法文件名字符，过长则截断；标题为空时用时间戳兜底 */
    const safeName = title.replace(/[\\/:*?"<>|]/g, '_').slice(0, 30) || `chat_${Date.now()}`;
    const pdfPath = `${context.cacheDir}/${safeName}.pdf`;

    /* 原图尺寸（截图宽度取决于屏幕密度，高度由卡片内容决定，可能远高于 A4） */
    const info = await pixelMap.getImageInfo();
    const imgW: number = info.size.width;
    const imgH: number = info.size.height;

    /* 图片等比缩放到页宽，计算总高度与所需页数 */
    const scale: number = PDF_PAGE_WIDTH / imgW;
    const scaledH: number = imgH * scale;
    const pageCount: number = Math.max(1, Math.ceil(scaledH / PDF_PAGE_HEIGHT));

    /* 长图打包为 PNG buffer，用 ImageSource 按 A4 页高在原图坐标上切段 */
    const packer = image.createImagePacker();
    const srcData: ArrayBuffer = await packer.packing(pixelMap, { format: 'image/png', quality: 100 });
    const src = image.createImageSource(srcData);

    const doc = new pdfService.PdfDocument();
    try {
      /* 创建 A4 文档（第一个页面由 createDocument 创建） */
      doc.createDocument(PDF_PAGE_WIDTH, PDF_PAGE_HEIGHT);

      for (let i = 0; i < pageCount; i++) {
        /* 原图坐标中的段落边界（等分页数，最后一段收尾） */
        const y0: number = Math.round(i * imgH / pageCount);
        const y1: number = Math.round((i + 1) * imgH / pageCount);
        const segH: number = y1 - y0;

        /* 段落等比放大到页宽：中间页高度≈页高，最后一段可能略矮（底部留白，不拉伸变形） */
        const segW: number = PDF_PAGE_WIDTH;
        const segDispH: number = Math.round(segH * scale);

        /* 按原图坐标裁剪段落并放大 */
        const seg = await src.createPixelMap({
          desiredRegion: { x: 0, y: y0, size: { width: imgW, height: segH } },
          desiredSize: { width: segW, height: segDispH },
        });

        /* 段落写临时 PNG（PDF Kit 的 addImageObject 按文件路径读取图片） */
        const segPath = `${context.cacheDir}/pdf_seg_${i}.png`;
        const segData: ArrayBuffer = await packer.packing(seg, { format: 'image/png', quality: 100 });
        const segFile = await fs.open(segPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        try {
          await fs.write(segFile.fd, segData);
        } finally {
          await fs.close(segFile.fd);
        }
        seg.release();

        /* 图片铺入页面：顶部对齐（y 为图片底边到页面底边的距离） */
        const page = i === 0 ? doc.getPage(0) : doc.insertBlankPage(i, PDF_PAGE_WIDTH, PDF_PAGE_HEIGHT);
        page.addImageObject(segPath, 0, PDF_PAGE_HEIGHT - segDispH, segW, segDispH);
      }

      /* 落盘 PDF 文件 */
      if (!doc.saveDocument(pdfPath)) {
        throw new Error(`PdfExporter saveDocument failed: ${pdfPath}`);
      }
      return pdfPath;
    } finally {
      packer.release();
      src.release();
      doc.releaseDocument();
    }
  }
}
