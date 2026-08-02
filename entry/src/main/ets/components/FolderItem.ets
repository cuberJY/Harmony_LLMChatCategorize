/**
 * 文件夹列表项组件
 * 用于 SideBarPage 收藏 Tab 和 FolderPage 中展示单个文件夹
 * 显示：文件夹图标 + 名称
 * 交互：点击进入 / 长按弹菜单（重命名、删除）
 */

import { Category } from "../model/Category";
import { COLORS, FONT_SIZES, SPACING } from "../common/AppConstants";
@Component
export struct FolderItem {
  @ObjectLink category: Category; // 文件夹数据（父组件传入）

  // 回调：点击进入 / 长按菜单操作
  onClickItem?: (cat: Category) => void; // 点击文件夹
  onMenuRename?: (cat: Category) => void; // 长按-编辑（重命名+改色）
  onMenuMove?: (cat: Category) => void; // 长按-移动
  onMenuDelete?: (cat: Category) => void; // 长按-删除

  build() {
    Row() {
      // 文件夹图标（按 color 着色，彩色图标）
      SymbolGlyph($r("sys.symbol.folder"))
        .fontSize(FONT_SIZES.ICON_LG)
        .fontColor([this.category.color])
        .margin({ right: SPACING.MD })

      // 名称
      Text(this.category.name)
        .fontSize(FONT_SIZES.NAME)
        .fontColor(COLORS.TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.Start)

      // 进入箭头
      SymbolGlyph($r("sys.symbol.chevron_right"))
        .fontSize(FONT_SIZES.ICON_MD)
        .fontColor([COLORS.TEXT_SECONDARY])
    }
    .width("100%")
    .padding({
      left: SPACING.XL,
      right: SPACING.XL,
      top: SPACING.MD,
      bottom: SPACING.MD
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
          .fontSize(FONT_SIZES.BUTTON)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width("100%")
      .height(36)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.onMenuRename) this.onMenuRename(this.category);
      })
      Divider()
        .strokeWidth(0.5)
        .color(COLORS.DIVIDER)
      Row() {
        Text("移动")
          .fontSize(FONT_SIZES.BUTTON)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width("100%")
      .height(36)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.onMenuMove) this.onMenuMove(this.category);
      })
      Divider()
        .strokeWidth(0.5)
        .color(COLORS.DIVIDER)
      Row() {
        Text("删除")
          .fontSize(FONT_SIZES.BUTTON)
          .fontColor(COLORS.TEXT_DANGER)
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
    .backgroundColor(COLORS.MENU_BG);
  }
}