/**
 * OfficeHtmlParser —— ArkWeb 文档排版渲染服务（阶段4 落地）
 *
 * 作用：对 docx / pptx 做"排版还原"（仅视觉模型使用）。流程：
 *  1. ChatPage 常驻一个不可见的 Web 组件（zIndex 0，被聊天内容覆盖）加载
 *     rawfile 的 office-parser/index.html（内含 deck-ir / docx-preview 浏览器版）。
 *  2. 页面 onPageEnd 时调用 markReady()，标记 JS Bridge 就绪。
 *  3. renderToImages(kind, base64)：把文件 Base64 注入 JS Bridge 渲染成逐页 HTML，
 *     每页通过 componentSnapshot 截图 → JPEG Base64（与 PDF 页面图同通道 input_image）。
 *
 * 关键依赖注入（由 ChatPage 完成）：
 *  - 截图执行器 setScreenshotExecutor：componentSnapshot.get 需要 UIContext，
 *    service 层拿不到，由页面注入"id → Promise<PixelMap>"函数。
 *  - Web 组件通过 getWebviewController() 绑定本服务的 controller。
 */
import { webview } from "@kit.ArkWeb";
import { image } from "@kit.ImageKit";
import buffer from "@ohos.buffer";
import { Logger } from "../common/Logger";

/* 全部页面图 Base64 总量上限（与 FileParser.MAX_TOTAL_BASE64 一致，请求体保护） */
const MAX_TOTAL_BASE64: number = 12 * 1024 * 1024;
/* 截图 JPEG 压缩质量 */
const JPEG_QUALITY: number = 80;
/* 页切换后等待渲染帧的间隔（ms）：JS 同步 showPage 后留出布局/绘制时间再截图 */
const PAGE_FRAME_DELAY_MS: number = 180;
/* Base64 分段注入的单段长度：过大单次 runJavaScript 在部分 WebView 上注入失败/返回 null */
const INJECT_CHUNK_SIZE: number = 512 * 1024;
/* 渲染结果轮询间隔与总超时（JS 侧渲染大文件可能耗时较长） */
const POLL_INTERVAL_MS: number = 300;
const RENDER_TIMEOUT_MS: number = 120 * 1000;

export class OfficeHtmlParser {
  private static instance: OfficeHtmlParser;

  /* 隐藏 WebView 控制器；Web 组件在 ChatPage 侧渲染（getWebviewController 绑定） */
  private controller: webview.WebviewController;
  /* JS Bridge 就绪标记（index.html onPageEnd 后置 true） */
  private ready: boolean = false;
  /* 截图执行器（ChatPage 注入）：id → Promise<PixelMap>，内部使用 UIContext */
  private executor?: (id: string) => Promise<image.PixelMap>;
  /* 渲染互斥：同一时刻只允许一个渲染任务 */
  private rendering: boolean = false;

  private constructor() {
    this.controller = new webview.WebviewController();
  }

  static getInstance(): OfficeHtmlParser {
    if (!OfficeHtmlParser.instance) {
      OfficeHtmlParser.instance = new OfficeHtmlParser();
    }
    return OfficeHtmlParser.instance;
  }

  getWebviewController(): webview.WebviewController {
    return this.controller;
  }

  /** 标记 JS Bridge 就绪（由页面 Web 组件 onPageEnd 触发） */
  markReady(): void {
    this.ready = true;
  }

  /** 注入截图执行器（ChatPage aboutToAppear 调用；UIContext 属于页面） */
  setScreenshotExecutor(fn: (id: string) => Promise<image.PixelMap>): void {
    this.executor = fn;
  }

  /**
   * 渲染 docx/pptx 并逐页截图，返回 JPEG Base64 列表（走视觉通道 input_image）
   * @param kind "docx" | "pptx"（决定调用的 Bridge 方法）
   * @param base64 文件字节的 Base64（大文件注入；上限由调用方/请求体保护控制）
   * @returns 页面图 Base64 数组；受 MAX_TOTAL_BASE64 总量限制（达到即停止后续页）
   */
  async renderToImages(kind: string, base64: string): Promise<string[]> {
    if (!this.ready) {
      throw new Error("OfficeWebView 尚未就绪");
    }
    if (this.rendering) {
      throw new Error("OfficeWebView 已有渲染任务进行中");
    }
    if (this.executor === undefined) {
      throw new Error("OfficeWebView 截图执行器未注入");
    }
    this.rendering = true;
    try {
      const fn: string = kind === "pptx" ? "renderPptx" : "renderDocx";

      /* 1. 分段注入 base64 到 window._officeData（单次 script 长度受控，避免大字符串注入失败） */
      await this.controller.runJavaScript(`window._officeChunks = []; true;`);
      let offset: number = 0;
      while (offset < base64.length) {
        const end: number = Math.min(offset + INJECT_CHUNK_SIZE, base64.length);
        await this.controller.runJavaScript(`window._officeChunks.push('${base64.substring(offset, end)}'); true;`);
        offset = end;
      }
      await this.controller.runJavaScript(`window._officeData = window._officeChunks.join(''); true;`);

      /* 2. 发起渲染（JS 侧完成后写 window._officeResult，runJavaScript 只拿返回值 true，不等长时异步） */
      await this.controller.runJavaScript(`window._officeResult = null; true;`);
      await this.controller.runJavaScript(`OfficeParserBridge.${fn}({base64: window._officeData}); true;`);

      /* 3. 轮询渲染结果（PENDING 标记未完成；超时抛错）
         ArkWeb runJavaScript 对字符串返回值做 JSON 序列化（外层带引号，如 "OK:1"），
         读回后用 JSON.parse 解一层得到真实内容 */
      let result: string = "PENDING";
      let waited: number = 0;
      while (waited < RENDER_TIMEOUT_MS && result === "PENDING") {
        await this.sleep(POLL_INTERVAL_MS);
        waited += POLL_INTERVAL_MS;
        const quoted: string = await this.controller.runJavaScript(
          `window._officeResult === null ? 'PENDING' : window._officeResult`);
        try {
          result = JSON.parse(quoted) as string;
        } catch (e) {
          result = quoted; // 兜底：非 JSON 序列化格式时按原文处理
        }
      }
      if (result === "PENDING") {
        throw new Error(`OfficeWebView 渲染超时（超过 ${RENDER_TIMEOUT_MS / 1000}s）`);
      }
      /* 4. 解析渲染结果（文本协议：OK:<页数> / ERR:<原因>，避免 JSON.parse 类型转换问题） */
      let pageCount: number = 0;
      if (result.startsWith("OK:")) {
        pageCount = parseInt(result.substring(3));
        if (pageCount <= 0) {
          throw new Error("OfficeWebView 渲染结果无页面");
        }
      } else if (result.startsWith("ERR:")) {
        throw new Error(`OfficeWebView 渲染失败: ${result.substring(4)}`);
      } else {
        throw new Error(`OfficeWebView 渲染结果异常: ${result.substring(0, 200)}`);
      }
      /* 5. 逐页：显示第 i 页 → 等渲染帧 → componentSnapshot 截图 → JPEG Base64 */
      const images: string[] = [];
      let total: number = 0;
      for (let i = 0; i < pageCount; i++) {
        await this.controller.runJavaScript(`OfficeParserBridge.showPage(${i})`);
        await this.sleep(PAGE_FRAME_DELAY_MS);
        const pm: image.PixelMap = await this.executor("office-web");
        const b64: string = await this.pixelMapToBase64(pm);
        images.push(b64);
        total += b64.length;
        if (total >= MAX_TOTAL_BASE64) {
          Logger.info(`OfficeHtmlParser: stop at page ${i + 1}, total b64 ${total}`);
          break;
        }
      }
      return images;
    } finally {
      this.rendering = false;
    }
  }

  /** PixelMap → JPEG Base64（与 FileParser.parsePdf 页面图编码一致） */
  private async pixelMapToBase64(pm: image.PixelMap): Promise<string> {
    const packer: image.ImagePacker = image.createImagePacker();
    try {
      const packed: ArrayBuffer = await packer.packToData(pm, {
        format: "image/jpeg",
        quality: JPEG_QUALITY,
      });
      return buffer.from(packed).toString("base64");
    } finally {
      packer.release();
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => setTimeout(resolve, ms));
  }
}
