import { WebPage } from "../../model/Message";
import { common } from '@kit.AbilityKit';
import { showToast } from "../../common/Utils";

/**
 * 「xx个网页」半模态面板：展示某条消息思考过程中浏览过的网页列表
 * - 结构与「选择文本」面板一致：上方居中标题 + 右上角叉号，顶部与页面标题栏下缘对齐
 * - 列表每项：域名 + 完整 URL，点击调用系统浏览器打开
 * 注：bindSheet 仍由父组件 MessageBubble 绑定，本组件仅作为 sheetContent 的 web 分支内容渲染
 */
@ComponentV2
export struct WebSheetPanel {
  /* 浏览过的网页列表（由 MessageBubble 传入 message.searchedWebs） */
  @Param webs: WebPage[] = [];
  /* 关闭面板回调（点击右上角叉号时触发，由父组件置 isSheetShow=false） */
  @Event onClose: () => void = () => {};

  build() {
    Column() {
      /* 标题行：左右等宽占位保证标题居中 */
      Row() {
        Row().width($r('app.float.space_xxl')) // 左侧占位（与右侧关闭按钮等宽，保证标题视觉居中）
        Text(`${this.webs.length} 个网页`)
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.font_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        /* 右上角关闭按钮（叉） */
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize($r('app.float.font_icon_lg'))
            .fontWeight(700)
            .fontColor([$r('app.color.font_primary')])
        }
        .width($r('app.float.space_xxl'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.onClose();
        })
      }
      .width("100%")
      .height($r('app.float.title_bar_height'))
      .padding({
        left: $r('app.float.space_xl'),
        right: $r('app.float.space_xl'),
      })
      /* 标题行底部分割线 */
      .border({
        width: { bottom: 2 },
        color: { bottom: $r('app.color.divider') },
      })

      /* 网页列表：每项 = 图标 + 域名 + 完整 URL，点击打开 */
      List() {
        ForEach(this.webs, (web: WebPage) => {
          ListItem() {
            this.webRow(web);
          }
        }, (web: WebPage) => web.url)
      }
      .width("100%")
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .divider({
        strokeWidth: 1,
        color: $r('app.color.divider'),
        startMargin: $r('app.float.space_xl'),
        endMargin: $r('app.float.space_xl'),
      })
    }
    .width("100%")
    .height("100%")
    .backgroundColor($r('app.color.dialog_bg'))
  }

  /* 网页列表单行：图标 + 域名（主行）+ 完整 URL（次行），点击打开 */
  @Builder
  webRow(web: WebPage) {
    Row() {
      SymbolGlyph($r("sys.symbol.link"))
        .fontSize($r('app.float.font_icon_lg'))
        .fontWeight(600)
        .fontColor([$r('app.color.search_icon')])
        .margin({ right: $r('app.float.space_md') })
      Column() {
        Text(web.domain)
          .fontSize($r('app.float.font_body'))
          .fontWeight(400)
          .fontColor($r('app.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(web.url)
          .fontSize($r('app.float.font_thinking'))
          .fontColor($r('app.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: $r('app.float.space_xxs') })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      /* 打开指示箭头 */
      SymbolGlyph($r("sys.symbol.arrow_up_right"))
        .fontSize($r('app.float.font_icon_md'))
        .fontWeight(600)
        .fontColor([$r('app.color.operation_icon')])
    }
    .width("100%")
    .padding({
      left: $r('app.float.space_xl'),
      right: $r('app.float.space_xl'),
      top: $r('app.float.space_md'),
      bottom: $r('app.float.space_md'),
    })
    .onClick(() => {
      this.openWebUrl(web.url);
    })
  }

  /* 调用系统浏览器打开网页（openLink API 12+） */
  private openWebUrl(url: string): void {
    try {
      const host = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (host !== undefined) {
        host.openLink(url);
      }
    } catch (e) {
      showToast($r('app.string.web_open_failed'));
    }
  }
}
