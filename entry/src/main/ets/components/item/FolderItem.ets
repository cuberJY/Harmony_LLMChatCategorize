/**
 * 文件夹列表项组件
 * 用于 SideBarPage 收藏 Tab 和 FolderPage 中展示单个文件夹
 * 显示：文件夹图标 + 名称
 * 交互：点击进入 / 长按弹菜单（重命名、删除）
 */

import { Category } from "../../model/Category";
import { SymbolGlyphModifier } from '@kit.ArkUI';
@ComponentV2
export struct FolderItem {
  /* 文件夹数据（父组件传入的 @ObservedV2 对象，@Trace 属性变化驱动本项刷新） */
  @Param category: Category = new Category();

  /* 回调：点击进入 / 长按菜单操作（@Event：V2 允许父组件初始化的普通事件） */
  @Event onClickItem: (cat: Category) => void = (cat: Category) => {}; // 点击文件夹
  @Event onMenuRename: (cat: Category) => void = (cat: Category) => {}; // 长按-编辑（重命名+改色）
  @Event onMenuPin: (cat: Category) => void = (cat: Category) => {}; // 长按-置顶/取消置顶
  @Event onMenuMove: (cat: Category) => void = (cat: Category) => {}; // 长按-移动
  @Event onMenuDelete: (cat: Category) => void = (cat: Category) => {}; // 长按-删除

  build() {
    Row() {
      /* 文件夹图标（按 color 着色） */
      SymbolGlyph($r("sys.symbol.folder"))
        .fontSize($r('app.float.font_icon_lg'))
        .fontColor([this.category.color])
        .margin({ right: $r('app.float.space_md') })

      /* 名称 */
      Text(this.category.name)
        .fontSize($r('app.float.font_name'))
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.Start)

      /* 进入箭头 */
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
    .backgroundColor(this.category.isPinned ? $r('app.color.item_pin_bg') : Color.Transparent)
    .onClick(() => {
      if (this.onClickItem) this.onClickItem(this.category);
    })
    /* 长按弹上下文菜单 */
    .bindContextMenu(this.folderMenu(), ResponseType.LongPress);
  }

  @Builder
  private folderMenu() {
    /* 长按菜单统一为系统 Menu/MenuItem（与 MessageBubble 的「更多」菜单视觉一致） */
    Menu() {
      /* 编辑（重命名 + 切换图标颜色） */
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.operation_icon')]),
        content: "编辑",
      })
        .onChange(() => {
          this.onMenuRename(this.category);
        })
      /* 移动 */
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_right_folder_circle'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.operation_icon')]),
        content: "移动",
      })
        .onChange(() => {
          this.onMenuMove(this.category);
        })
      /* 置顶 / 取消置顶（动态切换：未置顶→蓝色"置顶"，已置顶→红色"取消置顶"） */
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.pin'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.operation_icon')]),
        content: this.category.isPinned ? "取消置顶" : "置顶",
      })
        .onChange(() => {
          this.onMenuPin(this.category);
        })
      /* 删除 */
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash'))
          .fontSize($r('app.float.font_icon_lg'))
          .fontWeight(500)
          .fontColor([$r('app.color.text_danger')]),
        content: "删除",
      })
        .contentFontColor($r('app.color.text_danger'))
        .onChange(() => {
          this.onMenuDelete(this.category);
        })
    }
  }
}