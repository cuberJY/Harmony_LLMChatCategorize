/**
 * OfficeHtmlParser —— ArkWeb 文档排版渲染服务（阶段0 骨架）
 *
 * 作用：对 docx / pptx 做"排版还原"：在隐藏 WebView 中加载 rawfile 的
 *       office-parser/index.html（内含 deck-ir / docx-preview 浏览器版），
 *       把文件 Base64 注入 JS Bridge 解析/渲染成 HTML，ArkTS 侧再截图为图片。
 *
 * 说明：本文件为阶段0 技术验证骨架，验证 ArkWeb 加载 rawfile + JS Bridge 通信
 *       链路是否可行。完整的分页/截图/编码在阶段4 落地。
 */
import { webview } from "@kit.ArkWeb";
import { common } from "@kit.AbilityKit";
import { Logger } from "../common/Logger";

export class OfficeHtmlParser {
  private static instance: OfficeHtmlParser;

  /* 隐藏 WebView 控制器；真正的 Web 组件在页面侧渲染（createWebviewController） */
  private controller: webview.WebviewController;
  private ready: boolean = false;

  private constructor() {
    this.controller = new webview.WebviewController();
  }

  static getInstance(): OfficeHtmlParser {
    if (!OfficeHtmlParser.instance) {
      OfficeHtmlParser.instance = new OfficeHtmlParser();
    }
    return OfficeHtmlParser.instance;
  }

  isReady(): boolean {
    return this.ready;
  }

  getWebviewController(): webview.WebviewController {
    return this.controller;
  }

  /**
   * 标记 JS Bridge 就绪（由页面 Web 组件的 onPageEnd 回调触发）
   */
  markReady(): void {
    this.ready = true;
  }

  /**
   * 初始化：校验 UIAbilityContext 可用（仅作骨架，真正的 rawfile 加载与截图在阶段4）
   */
  init(context: common.UIAbilityContext): void {
    if (!context) {
      Logger.error('OfficeHtmlParser.init: invalid context');
      return;
    }
    Logger.info('OfficeHtmlParser.init: context ok');
  }
}