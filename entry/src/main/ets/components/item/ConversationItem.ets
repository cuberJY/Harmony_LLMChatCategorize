/**
 * 历史对话列表项组件
 * 用于 SideBarPage 历史列表中展示单条对话
 * 显示：对话标题
 */

import { Conversation } from "../../model/Conversation";
import { SymbolGlyphModifier } from '@kit.ArkUI';
@ComponentV2
export struct ConversationItem {
  /* 对话数据（由父组件传入的 @ObservedV2 对象，@Trace 属性变化驱动列表项刷新） */
  @Param conversation: Conversation = new Conversation();
  @Param isEditMode: boolean = false; // 是否多选编辑模式
  @Param isSelected: boolean = false; // 当前项是否被选中
  @Param isCurrent: boolean = false; // 是否为当前打开的对话
  @Param showFavoriteIcon: boolean = true; // 是否显示收藏星标（历史页显示，收藏页关闭）
  @Param showPinMenu: boolean = false; // 是否显示置顶菜单与图标（收藏页/文件夹页开启，历史页关闭）
  @Param showMoveMenu: boolean = true; // 是否显示"移动"菜单项（收藏页显示，历史页关闭）

  /* 回调（@Event：V2 允许父组件初始化的普通事件） */
  @Event onClickItem: (conv: Conversation) => void = (conv: Conversation) => {}; // 点击进入（非编辑模式）
  @Event onMenuDelete: (conv: Conversation) => void = (conv: Conversation) => {}; // 长按菜单-删除
  @Event onMenuRename: (conv: Conversation) => void = (conv: Conversation) => {}; // 长按菜单-重命名
  @Event onMenuSelect: (conv: Conversation) => void = (conv: Conversation) => {}; // 长按菜单-多选
  @Event onSelectChange: (conv: Conversation, checked: boolean) => void = (conv: Conversation, checked: boolean) => {}; // 勾选变化
  @Event onMenuMove: (conv: Conversation) => void = (conv: Conversation) => {}; // 长按菜单-移动到文件夹
  @Event onMenuFavorite: (conv: Conversation) => void = (conv: Conversation) => {}; // 长按菜单-收藏/取消收藏
  @Event onMenuPin: (conv: Conversation) => void = (conv: Conversation) => {}; // 长按菜单-置顶/取消置顶
  
  build() {
    Row() {
      /* 对话标题（无标题时显示"新对话"） */
      Column() {
        Text(this.conversation.title.length > 0 ? this.conversation.title : "新对话")
          .fontSize($r('app.float.font_name'))
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width("100%")
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      /* 已收藏对话：行尾显示金色星标（历史页展示；收藏页 showFavoriteIcon=false 关闭） */
      if (this.showFavoriteIcon && this.conversation.isFavorite) {
        SymbolGlyph($r("sys.symbol.star_fill"))
          .fontSize($r('app.float.font_icon_lg'))
          .fontColor([$r('app.color.star_gold')]) // 金色星标
          .margin({
            left: $r('app.float.space_sm'),
          })
      }

      /* 编辑模式：右侧勾选圆圈 */
      if (this.isEditMode) {
        Stack() {
          if (this.isSelected) {
            SymbolGlyph($r("sys.symbol.checkmark")) // 对勾
            .fontSize($r('app.float.font_icon_lg'))
            .fontWeight(900)
            .fontColor([Color.White])
          }
        }
        .width(20)
        .height(20)
        .borderRadius(10)
        .border({ width: 1.5, color: this.isSelected ? $r('app.color.primary') : $r('app.color.send_btn_disabled') })
        .backgroundColor(this.isSelected ? $r('app.color.primary') : Color.Transparent)
        .margin({
            left: $r('app.float.space_sm'),
        })
      }
    }
    .width("100%")
    .padding({
      left: $r('app.float.space_xl'),
      right: $r('app.float.space_xl'),
      top: $r('app.float.space_md'),
      bottom: $r('app.float.space_md'),
    })
    .backgroundColor(
      this.isCurrent ? $r('app.color.item_current_bg')
        : (this.conversation.isPinned ? $r('app.color.item_pin_bg') : Color.Transparent),
    )
    .onClick(() => {
      /* 点击 → 回调父组件，由父组件决定跳转逻辑 */
      if (this.isEditMode) {
        if (this.onSelectChange) this.onSelectChange(this.conversation, !this.isSelected);
      } else {
        if (this.onClickItem) this.onClickItem(this.conversation);
      }
    })
    /* 长按弹上下文菜单（编辑模式下 builder 为空 → 不弹） */
    .bindContextMenu(this.itemMenu(), ResponseType.LongPress);
  }

  @Builder
  private itemMenu() {
    if (!this.isEditMode) {
      /* 长按菜单统一为系统 Menu/MenuItem（与 MessageBubble 的「更多」菜单视觉一致） */
      Menu() {
        /* 多选 */
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle'))
            .fontSize($r('app.float.font_icon_lg'))
            .fontWeight(500)
            .fontColor([$r('app.color.operation_icon')]),
          content: "多选",
        })
          .onChange(() => {
            this.onMenuSelect(this.conversation);
          })
        /* 重命名 */
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil'))
            .fontSize($r('app.float.font_icon_lg'))
            .fontWeight(500)
            .fontColor([$r('app.color.operation_icon')]),
          content: "重命名",
        })
          .onChange(() => {
            this.onMenuRename(this.conversation);
          })
        /* 移动到文件夹（历史页 showMoveMenu=false 隐藏：未收藏对话不参与文件夹分类） */
        if (this.showMoveMenu) {
          MenuItem({
            symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.folder'))
              .fontSize($r('app.float.font_icon_lg'))
              .fontWeight(500)
              .fontColor([$r('app.color.operation_icon')]),
            content: "移动",
          })
            .onChange(() => {
              this.onMenuMove(this.conversation);
            })
        }
        /* 置顶 / 取消置顶（动态切换：未置顶→蓝色"置顶"，已置顶→红色"取消置顶"） */
        if (this.showPinMenu) {
          MenuItem({
            symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.pin'))
              .fontSize($r('app.float.font_icon_lg'))
              .fontWeight(500)
              .fontColor([$r('app.color.operation_icon')]),
            content: this.conversation.isPinned ? "取消置顶" : "置顶",
          })
            .contentFontColor(
              this.conversation.isPinned ? $r('app.color.text_danger') : $r('app.color.primary'),
            )
            .onChange(() => {
              this.onMenuPin(this.conversation);
            })
        }
        /* 收藏 / 取消收藏（动态切换：未收藏→蓝色"收藏"，已收藏→红色"取消收藏"） */
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier(this.conversation.isFavorite ? $r('sys.symbol.star_slash') : $r('sys.symbol.star'))
            .fontSize($r('app.float.font_icon_lg'))
            .fontWeight(500)
            .fontColor([$r('app.color.operation_icon')]),
          content: this.conversation.isFavorite ? "取消收藏" : "收藏",
        })
          .contentFontColor(
            this.conversation.isFavorite ? $r('app.color.text_danger') : $r('app.color.primary'),
          )
          .onChange(() => {
            this.onMenuFavorite(this.conversation);
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
            this.onMenuDelete(this.conversation);
          })
      }
    }
  }
}
