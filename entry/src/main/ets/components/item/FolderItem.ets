/**
 * 文件夹列表项组件
 * 用于 SideBarPage 收藏 Tab 和 FolderPage 中展示单个文件夹
 * 显示：文件夹图标 + 名称
 * 交互：点击进入 / 长按弹菜单（重命名、删除）
 */

import { Category } from "../../model/Category";
@ComponentV2
export struct FolderItem {
  // 文件夹数据（父组件传入的 @ObservedV2 对象，@Trace 属性变化驱动本项刷新）
  @Param category: Category = new Category();

  // 回调：点击进入 / 长按菜单操作（@Event：V2 允许父组件初始化的普通事件）
  @Event onClickItem: (cat: Category) => void = (cat: Category) => {}; // 点击文件夹
  @Event onMenuRename: (cat: Category) => void = (cat: Category) => {}; // 长按-编辑（重命名+改色）
  @Event onMenuMove: (cat: Category) => void = (cat: Category) => {}; // 长按-移动
  @Event onMenuDelete: (cat: Category) => void = (cat: Category) => {}; // 长按-删除

  build() {
    Row() {
      // 文件夹图标（按 color 着色，彩色图标）
      SymbolGlyph($r("sys.symbol.folder"))
        .fontSize($r('app.float.font_icon_lg'))
        .fontColor([this.category.color])
        .margin({ right: $r('app.float.space_md') })

      // 名称
      Text(this.category.name)
        .fontSize($r('app.float.font_name'))
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.Start)

      // 进入箭头
      SymbolGlyph($r("sys.symbol.chevron_right"))
        .fontSize($r('app.float.font_icon_md'))
        .fontColor([$r('app.color.text_secondary')])
    }
    .width("100%")
    .padding({
      left: $r('app.float.space_xl'),
      right: $r('app.float.space_xl'),
      top: $r('app.float.space_md'),
      bottom: $r('app.float.space_md')
    })
    .onClick(() => {
      if (this.onClickItem) this.onClickItem(this.category);
    })
    // 长按弹菜单：编辑 / 移动 / 删除
    .bindContextMenu(this.folderMenu(), ResponseType.LongPress);
  }

  @Builder
  private folderMenu() {
    Column() {
      Row() {
        Text("编辑")
          .fontSize($r('app.float.font_button'))
          .fontColor($r('app.color.text_primary'))
      }
      .width("100%")
      .height(36)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.onMenuRename) this.onMenuRename(this.category);
      })
      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.divider'))
      Row() {
        Text("移动")
          .fontSize($r('app.float.font_button'))
          .fontColor($r('app.color.text_primary'))
      }
      .width("100%")
      .height(36)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.onMenuMove) this.onMenuMove(this.category);
      })
      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.divider'))
      Row() {
        Text("删除")
          .fontSize($r('app.float.font_button'))
          .fontColor($r('app.color.text_danger'))
      }
      .width("100%")
      .height(36)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.onMenuDelete) this.onMenuDelete(this.category);
      })
    }
    .width(160)
    .borderRadius(10)
    .backgroundColor($r('app.color.menu_bg'));
  }
}