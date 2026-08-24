/**
 * Markdown 文件预览页（独立路由页）
 * 用途：对话气泡内点击 md 文件卡片 → 本页预览（Preview Kit 不支持 md 类型，自研实现）
 * 支持「源码 | 预览」双模式切换：
 *  - 预览模式：@luvi/lv-markdown-in 富文本渲染（与聊天气泡同一渲染器）
 *  - 源码模式：等宽字体原样展示 md 源码
 * 数据来源：file.textContent（阶段1 已解析落库，气泡内消息直接携带，无需重新读文件）
 */
import { Markdown, MarkdownController } from "@luvi/lv-markdown-in";
import { common, ConfigurationConstant, EnvironmentCallback } from '@kit.AbilityKit';
import { FileAttachment } from "../model/Message";
import { SafeAreaHelper } from "../common/Utils";
import { applyMarkdownTheme } from "../common/MarkdownTheme";

/* 路由参数（ChatPage pushPathByName 注入）：md 文件附件 */
export interface MarkdownPreviewParams {
  file: FileAttachment;
}

/* 预览模式：预览(渲染) / 源码(原文) */
type PreviewMode = "preview" | "source";

@ComponentV2
export struct MarkdownPreviewPage {
  /* 路由参数：md 文件附件（textContent 已由解析填充） */
  @Param file: FileAttachment = { id: "", name: "", ext: "", size: 0, localPath: "", textContent: "", pageImages: [] };
  /* 路由栈（NavDestination.onReady 获取）：返回 = pop 弹栈 */
  private pathStack: NavPathStack = new NavPathStack();
  /* Markdown 渲染控制器（主题配置与聊天气泡共用 applyMarkdownTheme） */
  private mdController: MarkdownController = new MarkdownController();
  /* 当前预览模式（切换驱动内容区刷新） */
  @Local mode: PreviewMode = "preview";
  /* 状态栏高度（vp）：标题栏顶部避让 */
  @Local statusBarHeightVp: number = 0;
  /* 是否深色模式（驱动代码块/思维导图主题切换，与气泡一致） */
  @Local isDarkMode: boolean = false;
  /* 系统环境监听回调 ID（aboutToDisappear 注销用） */
  private envCallbackId: number = -1;

  aboutToAppear(): void {
    this.statusBarHeightVp = SafeAreaHelper.getStatusBarHeight();
    /* 依据当前系统颜色模式配置 Markdown 主题（与聊天气泡同一套样式） */
    this.applyTheme();
    this.registerEnvironmentListener();
  }

  aboutToDisappear(): void {
    this.unregisterEnvironmentListener();
  }

  /* 读取系统深浅色并应用 Markdown 主题 */
  private applyTheme(): void {
    const host = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    let isDark = this.isDarkMode;
    if (host !== undefined && host.config !== undefined) {
      isDark = host.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    this.isDarkMode = isDark;
    applyMarkdownTheme(this.mdController, isDark);
  }

  /* 监听系统配置变化（深色/浅色切换），动态更新代码块/思维导图主题（与气泡一致） */
  private registerEnvironmentListener(): void {
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      return;
    }
    const appCtx = host.getApplicationContext();
    const callback: EnvironmentCallback = {
      onConfigurationUpdated: (config): void => {
        const isDark = config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
        if (isDark !== this.isDarkMode) {
          this.isDarkMode = isDark;
          applyMarkdownTheme(this.mdController, isDark);
        }
      },
      onMemoryLevel: (level): void => {
        /* 内存紧张回调，本页无需处理 */
      },
    };
    this.envCallbackId = appCtx.on('environment', callback);
  }

  private unregisterEnvironmentListener(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined && this.envCallbackId !== -1) {
      host.getApplicationContext().off('environment', this.envCallbackId);
      this.envCallbackId = -1;
    }
  }

  /* 右上角切换按钮：预览 ⇄ 源码 */
  @Builder
  modeSwitch() {
    Row() {
      Text("源\n码")
        .fontSize($r('app.float.font_icon_sm'))
        .fontColor(this.mode === "source" ? $r('app.color.toggle_text_active') : $r('app.color.font_secondary'))
        .backgroundColor(this.mode === "source" ? $r('app.color.toggle_bg_active') : Color.Transparent)
        .fontWeight(this.mode === "source" ? 700 : 400)
        .padding({
          left: $r('app.float.space_xs'),
          right: $r('app.float.space_xs'),
          top: $r('app.float.space_xs'),
          bottom: $r('app.float.space_xs'),
        })
        .onClick(() => {
          this.mode = "source";
        })
        .border({ width:{ right:1 }, color:{ right:$r('app.color.divider') } })
      // 预览
      Text("预\n览")
        .fontSize($r('app.float.font_icon_sm'))
        .fontColor(this.mode === "preview" ? $r('app.color.toggle_text_active') : $r('app.color.font_secondary'))
        .backgroundColor(this.mode === "preview" ? $r('app.color.toggle_bg_active') : Color.Transparent)
        .fontWeight(this.mode === "preview" ? 700 : 400)
        .padding({
          left: $r('app.float.space_xs'),
          right: $r('app.float.space_xs'),
          top: $r('app.float.space_xs'),
          bottom: $r('app.float.space_xs'),
        })
        .onClick(() => {
          this.mode = "preview";
        })
    }
    .backgroundColor($r('app.color.title_bar_bg'))
    .borderRadius(4)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  build() {
    NavDestination() {
      Column() {
        /* 标题栏：返回键 + 文件名 + 右上角源码/预览切换 */
        Row() {
          Button() {
            SymbolGlyph($r("sys.symbol.chevron_left"))
              .fontSize($r('app.float.font_icon_xxl'))
              .fontColor([$r('app.color.font_primary')])
          }
          .width(32)
          .height(32)
          .type(ButtonType.Circle)
          .backgroundColor('#20212121')
          .padding({
            left: $r('app.float.space_xs'),
            right: 5,
            top: $r('app.float.space_xs'),
            bottom: $r('app.float.space_xs'),
          })
          .onClick(() => {
            this.pathStack.pop();
          })

          Text(this.file.name)
            .fontSize($r('app.float.font_title'))
            .fontWeight(700)
            .fontColor($r('app.color.font_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({
              left: $r('app.float.space_xs'),
              right: $r('app.float.space_xs'),
            })
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          /* 右上角切换按钮（源码 ⇄ 预览） */
          this.modeSwitch()
        }
        .width("100%")
        .height(SafeAreaHelper.getTitleBarHeight(this.getUIContext()) + this.statusBarHeightVp)
        .padding({
          top: this.statusBarHeightVp,
          left: $r('app.float.space_md'),
          right: $r('app.float.space_md')
        })
        .backgroundColor($r('app.color.title_bar_bg'))
        /**
         * 沉浸式：expandSafeArea 让标题栏背景向上延伸到状态栏背后（与系统栏同色融为一体）；
         * 内容改用显式 padding（真实状态栏高度）避让——safeAreaPadding 在固定高度组件上会失效导致重叠
         */
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
        .border({
          width: { bottom: 2 },
          color: { bottom: $r('app.color.divider') },
        })

        /* 内容区：预览 / 源码 双模式 */
        if (this.file.textContent.length === 0) {
          /* 空态：md 内容为空（解析失败/极端场景） */
          Column() {
            Text("暂无内容")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.font_secondary'))
          }
          .width("100%")
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.mode === "preview") {
          /* 预览模式：lv-markdown-in 富文本渲染（滚动容器承载，长文档可滚动） */
          Scroll() {
            Markdown({
              text: this.file.textContent,
              mode: "text",
              controller: this.mdController,
            })
          }
          .width("100%")
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .align(Alignment.TopStart)
          .padding({
            left: $r('app.float.space_md'),
            right: $r('app.float.space_md'),
            top: $r('app.float.space_md'),
            bottom: $r('app.float.space_lg'),
          })
        } else {
          /* 源码模式：等宽字体原样展示 md 源码 */
          Scroll() {
            Text(this.file.textContent)
              .fontSize($r('app.float.font_remind'))
              .fontColor($r('app.color.font_primary'))
              .lineHeight(20)
              .copyOption(CopyOptions.LocalDevice)
          }
          .width("100%")
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .align(Alignment.TopStart)
          .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md'), top: $r('app.float.space_md'), bottom: $r('app.float.space_md') })
        }
      }
      .width("100%")
      .height("100%")
      .backgroundColor($r('app.color.page_bg'))
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}
