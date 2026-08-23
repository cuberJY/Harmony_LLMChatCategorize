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
      Text("源码")
        .fontSize($r('app.float.font_icon_sm'))
        .fontColor(this.mode === "source" ? $r('app.color.font_primary') : $r('app.color.font_secondary'))
        .fontWeight(this.mode === "source" ? 700 : 400)
        .padding({
          left: $r('app.float.space_sm'),
          right: $r('app.float.space_sm'),
          top: $r('app.float.space_xxs'),
          bottom: $r('app.float.space_xxs'),
        })
        .onClick(() => {
          this.mode = "source";
        })
      Text("预览")
        .fontSize($r('app.float.font_icon_sm'))
        .fontColor(this.mode === "preview" ? $r('app.color.font_primary') : $r('app.color.font_secondary'))
        .fontWeight(this.mode === "preview" ? 700 : 400)
        .padding({
          left: $r('app.float.space_sm'),
          right: $r('app.float.space_sm'),
          top: $r('app.float.space_xxs'),
          bottom: $r('app.float.space_xxs'),
        })
        .onClick(() => {
          this.mode = "preview";
        })
    }
    .backgroundColor($r('app.color.chat_input_bg'))
    .borderRadius($r('app.float.space_sm'))
    .padding(2)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  build() {
    NavDestination() {
      Column() {
        /* 标题栏：返回键 + 文件名 + 右上角源码/预览切换 */
        Row() {
          Button() {
            SymbolGlyph($r("sys.symbol.chevron_left"))
              .fontSize(32)
              .fontColor([$r('app.color.font_on_primary')])
          }
          .width(40)
          .height(40)
          .type(ButtonType.Circle)
          .backgroundColor('#FF212121')
          .padding({
            left: $r('app.float.space_xs'),
            right: 6,
            top: $r('app.float.space_xs'),
            bottom: $r('app.float.space_xs'),
          })
          .margin({
            top: $r('app.float.space_md')
          })
          .onClick(() => {
            this.pathStack.pop();
          })

          Text(this.file.name)
            .fontSize($r('app.float.font_title'))
            .fontWeight(700)
            .fontColor($r('app.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          /* 右上角切换按钮（源码 ⇄ 预览） */
          this.modeSwitch()
        }
        .width("100%")
        .height(40)
        .padding({
          left: $r('app.float.space_md'),
          right: $r('app.float.space_md')
        })
        .justifyContent(FlexAlign.End)
        .margin({ top: this.statusBarHeightVp })

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
          .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md'), top: $r('app.float.space_md'), bottom: $r('app.float.space_md') })
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
