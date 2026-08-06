/**
 * 历史对话列表项组件
 * 用于 SideBarPage 历史列表中展示单条对话
 * 显示：对话标题 + 最后更新时间
 */

import { Conversation } from "../model/Conversation";
@ComponentV2
export struct ConversationItem {
  // 对话数据（由父组件传入的 @ObservedV2 对象，@Trace 属性变化驱动列表项刷新）
  @Param conversation: Conversation = new Conversation();
  @Param isEditMode: boolean = false; // 是否多选编辑模式
  @Param isSelected: boolean = false; // 当前项是否被选中
  @Param showFavoriteIcon: boolean = true; // 是否显示收藏星标（历史页显示，收藏页关闭）
  @Param showMoveMenu: boolean = true; // 是否显示"移动"菜单项（收藏页显示，历史页关闭）

  // 回调（@Event：V2 允许父组件初始化的普通事件）
  @Event onClickItem: (conv: Conversation) => void = (conv: Conversation) => {}; // 点击进入（非编辑模式）
  @Event onMenuDelete: (conv: Conversation) => void = (conv: Conversation) => {}; // 长按菜单-删除
  @Event onMenuRename: (conv: Conversation) => void = (conv: Conversation) => {}; // 长按菜单-重命名
  @Event onMenuSelect: (conv: Conversation) => void = (conv: Conversation) => {}; // 长按菜单-多选
  @Event onSelectChange: (conv: Conversation, checked: boolean) => void = (conv: Conversation, checked: boolean) => {}; // 勾选变化
  @Event onMenuMove: (conv: Conversation) => void = (conv: Conversation) => {}; // 长按菜单-移动到文件夹
  @Event onMenuFavorite: (conv: Conversation) => void = (conv: Conversation) => {}; // 长按菜单-收藏/取消收藏

  build() {
    Row() {
      // 对话标题（无标题时显示"新对话"）
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

      // 已收藏对话：行尾显示金色星标（历史页展示；收藏页 showFavoriteIcon=false 关闭）
      if (this.showFavoriteIcon && this.conversation.isFavorite) {
        SymbolGlyph($r("sys.symbol.star_fill"))
          .fontSize($r('app.float.font_icon_lg'))
          .fontColor([$r('app.color.star_gold')]) // 金色星标
          .margin({ left: $r('app.float.space_sm') })
      }

      // 编辑模式：右侧勾选圆圈
      if (this.isEditMode) {
        Stack() {
          if (this.isSelected) {
            SymbolGlyph($r("sys.symbol.checkmark")) // 对勾
            .fontSize($r('app.float.font_icon_lg'))
            .fontColor([Color.White]);
          }
        }
        .width(24)
        .height(24)
        .borderRadius(12)
        .border({ width: 1.5, color: this.isSelected ? $r('app.color.primary') : $r('app.color.send_btn_disabled') })
        .backgroundColor(this.isSelected ? $r('app.color.primary') : Color.Transparent)
      }
    }
    .width("100%")
    .padding({
      left: $r('app.float.space_xl'),
      right: $r('app.float.space_xl'),
      top: $r('app.float.space_md'),
      bottom: $r('app.float.space_md'),
    })
    .onClick(() => {
      // 点击 → 回调父组件，由父组件决定跳转逻辑
      if (this.isEditMode) {
        if (this.onSelectChange) this.onSelectChange(this.conversation, !this.isSelected);
      } else {
        if (this.onClickItem) this.onClickItem(this.conversation);
      }
    })
    // 长按弹上下文菜单（编辑模式下 builder 为空 → 不弹）
    .bindContextMenu(this.itemMenu(), ResponseType.LongPress);
  }

  @Builder
  private itemMenu() {
    if (!this.isEditMode) {
      Column() {
        // 多选
        Row() {
          Text("多选")
            .fontSize($r('app.float.font_button'))
            .fontColor($r('app.color.text_primary'))
        }
        .width("100%")
        .height(36)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.onMenuSelect) this.onMenuSelect(this.conversation);
        })
        Divider()
          .strokeWidth(0.5)
          .color($r('app.color.divider'))

        // 收藏 / 取消收藏（动态切换：未收藏→蓝色"收藏"，已收藏→红色"取消收藏"）
        Row() {
          Text(this.conversation.isFavorite ? "取消收藏" : "收藏")
            .fontSize($r('app.float.font_button'))
            .fontColor(this.conversation.isFavorite ? $r('app.color.text_danger') : $r('app.color.primary'))
        }
        .width("100%")
        .height(36)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.onMenuFavorite) this.onMenuFavorite(this.conversation);
        })
        Divider()
          .strokeWidth(0.5)
          .color($r('app.color.divider'))

        // 重命名
        Row() {
          Text("重命名")
            .fontSize($r('app.float.font_button'))
            .fontColor($r('app.color.text_primary'))
        }
        .width("100%")
        .height(36)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.onMenuRename) this.onMenuRename(this.conversation);
        })

        // 移动到文件夹（历史页 showMoveMenu=false 隐藏：未收藏对话不参与文件夹分类）
        if (this.showMoveMenu) {
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
            if (this.onMenuMove) this.onMenuMove(this.conversation);
          })
        }

        // 删除
        Row() {
          Text("删除")
            .fontSize($r('app.float.font_button'))
            .fontColor($r('app.color.text_danger'))
        }
        .width("100%")
        .height(36)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.onMenuDelete) this.onMenuDelete(this.conversation);
        })
      }
      .width(160)
      .borderRadius(10)
      .backgroundColor($r('app.color.menu_bg'));
    }
  }
}
