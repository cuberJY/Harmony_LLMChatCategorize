/**
 * 多选编辑标题栏（通用组件）
 * 用于 SideBarPage / FolderPage 的多选编辑模式顶部栏：
 *   左侧 xmark 退出编辑、中间"已选择 X 项"、右侧全选按钮。
 * 内置沉浸式系统栏适配（高度 = 标题栏 + 状态栏，内容显式避让状态栏），
 * 页面无需再重复 SafeAreaHelper 调用。
 */

import { SafeAreaHelper } from "../../common/Utils";

@ComponentV2
export struct EditModeTitleBar {
  /* 已选择数量（驱动"已选择 X 项"文案，0 时亦可展示） */
  @Param selectedCount: number = 0;
  /* 是否全选（驱动全选图标高亮态） */
  @Param isAllSelected: boolean = false;

  /* 退出编辑回调（xmark 点击） */
  @Event onExit: () => void = () => {};
  /* 全选/取消全选回调（右侧图标点击） */
  @Event onToggleSelectAll: () => void = () => {};

  build() {
    Row() {
      Row() {
        Button() {
          SymbolGlyph($r("sys.symbol.xmark"))
            .fontSize($r('app.float.font_icon_xl'))
            .fontWeight(900)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(32)
        .height(32)
        .type(ButtonType.Circle)
        .backgroundColor($r('app.color.page_bg'))
        .onClick(() => {
          this.onExit();
        })
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)

      Row() {
        Text("已选择 ")
          .fontSize($r('app.float.font_title'))
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
        Text(this.selectedCount.toString())
          .fontSize($r('app.float.font_title'))
          .fontWeight(600)
          .fontColor($r('app.color.text_important'))
          .textAlign(TextAlign.Center)
        Text(" 项")
          .fontSize($r('app.float.font_title'))
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
      }
      .justifyContent(FlexAlign.Center)

      Row() {
        SymbolGlyph(
          this.isAllSelected
            ? $r("sys.symbol.checkmark_square_on_square_fill")
            : $r("sys.symbol.checkmark_square_on_square"),
        )
        .fontSize($r('app.float.font_icon_xxl'))
        .fontWeight(700)
        .fontColor([$r('app.color.text_primary')])
      }
      .width(40)
      .layoutWeight(1)
      .justifyContent(FlexAlign.End)
      .onClick(() => {
        this.onToggleSelectAll();
      })
    }
    .width("100%")
    /* 沉浸式：标题栏高度 = 标题栏 + 状态栏，背景延伸 + 显式 padding 内容避让 */
    .height(SafeAreaHelper.getTitleBarHeight(this.getUIContext()) + SafeAreaHelper.getStatusBarHeight())
    .padding({
      top: SafeAreaHelper.getStatusBarHeight(),
      left: $r('app.float.space_lg'),
      right: $r('app.float.space_xl')
    })
    .backgroundColor($r('app.color.title_bar_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .border({ width: { bottom: 2 }, color: { bottom: $r('app.color.divider') } });
  }
}
