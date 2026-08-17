/**
 * 悬浮"新建文件夹"按钮（通用组件）
 * 用于 SideBarPage 收藏 Tab / FolderPage 右下角（两处原本重复的 FAB 本体）。
 * 定位由父容器负责（父 Stack align BottomEnd），本组件仅封装圆形加号按钮样式；
 * 多选编辑模式可传入 visible=false 隐藏，避免遮挡底部操作栏。
 */

@ComponentV2
export struct NewFolderFab {
  /* 是否可见（多选编辑模式传 false 隐藏） */
  @Param visible: boolean = true;
  /* 点击回调（父级执行新建文件夹逻辑） */
  @Event onAddClick: () => void = () => {};

  build() {
    Button() {
      SymbolGlyph($r("sys.symbol.plus"))
        .fontSize($r('app.float.font_icon_xxl'))
        .fontColor([Color.White])
        .fontWeight(800)
    }
    .width(48)
    .height(48)
    .type(ButtonType.Circle)
    .backgroundColor($r('app.color.primary'))
    .shadow({ radius: 8, color: $r('app.color.fab_shadow'), offsetY: 2 })
    .margin({ right: $r('app.float.space_xl'), bottom: $r('app.float.middle_button_height') })
    .visibility(this.visible ? Visibility.Visible : Visibility.None)
    .onClick(() => {
      this.onAddClick();
    })
  }
}
