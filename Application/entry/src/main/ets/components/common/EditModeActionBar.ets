/**
 * 多选编辑底部操作栏（通用组件）
 * 用于 SideBarPage / FolderPage 的多选编辑模式底部栏：
 *   删除 + 取消收藏 + 移动（收藏页特有操作可配置显隐）。
 * 内置沉浸式系统栏适配（高度 = 标题栏 + 导航条，内容显式避让导航条）。
 */

import { SafeAreaHelper } from "../../common/Utils";

@ComponentV2
export struct EditModeActionBar {
  /* 已选择数量（0 时操作按钮置灰且不可点） */
  @Param selectedCount: number = 0;
  /* 是否显示"取消收藏/移动"（收藏 Tab / 文件夹页显示；历史 Tab 关闭） */
  @Param showFavoriteActions: boolean = true;

  /* 删除回调 */
  @Event onDelete: () => void = () => {};
  /* 取消收藏回调 */
  @Event onUnfavorite: () => void = () => {};
  /* 移动回调 */
  @Event onMove: () => void = () => {};

  build() {
    Row() {
      Row() {
        Text("删除")
          .fontSize($r('app.float.font_button'))
          .fontWeight(500)
          .fontColor(this.selectedCount > 0 ? $r('app.color.text_danger') : $r('app.color.font_secondary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            if (this.selectedCount > 0) this.onDelete();
          })
        if (this.showFavoriteActions) {
          Text("取消收藏")
            .fontSize($r('app.float.font_button'))
            .fontWeight(500)
            .fontColor(this.selectedCount > 0 ? $r('app.color.text_danger') : $r('app.color.font_secondary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              if (this.selectedCount > 0) this.onUnfavorite();
            })
          Text("移动")
            .fontSize($r('app.float.font_button'))
            .fontWeight(500)
            .fontColor(this.selectedCount > 0 ? $r('app.color.toggle_text_active') : $r('app.color.font_secondary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              if (this.selectedCount > 0) this.onMove();
            })
        }
      }
      .margin({ bottom: $r('app.float.space_lg') })
    }
    .width("100%")
    /* 沉浸式：操作栏高度 = 标题栏 + 导航条，背景延伸 + 显式 padding 内容避让 */
    .height(SafeAreaHelper.getTitleBarHeight(this.getUIContext()) + SafeAreaHelper.getNavBarHeight())
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ bottom: SafeAreaHelper.getNavBarHeight() })
    .backgroundColor($r('app.color.title_bar_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .border({
      width: { top: 2 },
      color: { top: $r('app.color.divider') },
    })
  }
}
