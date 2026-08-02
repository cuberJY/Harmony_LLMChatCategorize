/**
 * 历史对话列表项组件
 * 用于 SideBarPage 历史列表中展示单条对话
 * 显示：对话标题 + 最后更新时间
 */

import { Conversation } from "../model/Conversation";
import { COLORS, FONT_SIZES, SPACING } from "../common/AppConstants";
@Component
export struct ConversationItem {
  /** 对话数据（由父组件传入） */
  @ObjectLink conversation: Conversation;
  @Prop isEditMode: boolean = false; // 是否多选编辑模式
  @Prop isSelected: boolean = false; // 当前项是否被选中

  onClickItem?: (conv: Conversation) => void; // 点击进入（非编辑模式）
  onMenuDelete?: (conv: Conversation) => void; // 长按菜单-删除
  onMenuRename?: (conv: Conversation) => void; // 长按菜单-重命名
  onMenuSelect?: (conv: Conversation) => void; // 长按菜单-多选
  onSelectChange?: (conv: Conversation, checked: boolean) => void; // 勾选变化
  onMenuMove?: (conv: Conversation) => void; // 长按菜单-移动到文件夹

  build() {
    Row() {
      // 对话标题（无标题时显示"新对话"）
      Column() {
        Text(this.conversation.title.length > 0 ? this.conversation.title : "新对话")
          .fontSize(FONT_SIZES.NAME)
          .fontColor(COLORS.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width("100%")
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 编辑模式：右侧勾选圆圈
      if (this.isEditMode) {
        Stack() {
          if (this.isSelected) {
            SymbolGlyph($r("sys.symbol.checkmark")) // 对勾
            .fontSize(FONT_SIZES.ICON_LG)
            .fontColor([Color.White]);
          }
        }
        .width(24)
        .height(24)
        .borderRadius(12)
        .border({ width: 1.5, color: this.isSelected ? COLORS.PRIMARY : "#CCCCCC" })
        .backgroundColor(this.isSelected ? COLORS.PRIMARY : Color.Transparent)
      }
    }
    .width("100%")
    .padding({
      left: SPACING.XL,
      right: SPACING.XL,
      top: SPACING.MD,
      bottom: SPACING.MD,
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
            .fontSize(FONT_SIZES.BUTTON)
            .fontColor(COLORS.TEXT_PRIMARY)
        }
        .width("100%")
        .height(36)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.onMenuSelect) this.onMenuSelect(this.conversation);
        })
        Divider()
          .strokeWidth(0.5)
          .color(COLORS.DIVIDER)

        // 重命名
        Row() {
          Text("重命名")
            .fontSize(FONT_SIZES.BUTTON)
            .fontColor(COLORS.TEXT_PRIMARY)
        }
        .width("100%")
        .height(36)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.onMenuRename) this.onMenuRename(this.conversation);
        })
        Divider()
          .strokeWidth(0.5)
          .color(COLORS.DIVIDER)

        // 移动到文件夹
        Row() {
          Text("移动")
            .fontSize(FONT_SIZES.BUTTON)
            .fontColor(COLORS.TEXT_PRIMARY)
        }
        .width("100%")
        .height(36)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.onMenuMove) this.onMenuMove(this.conversation);
        })

        // 删除
        Row() {
          Text("删除")
            .fontSize(FONT_SIZES.BUTTON)
            .fontColor(COLORS.TEXT_DANGER)
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
      .backgroundColor(COLORS.MENU_BG);
    }
  }

  /**
   * 对话列表时间格式化（比消息时间更简洁）
   *   今天   → "14:30"
   *   昨天   → "昨天"
   *   7天内  → "星期三"
   *   30天内 → "7/9"
   *   更早   → "2026/6/9"
   */
  private formatConvTime(timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();

    // 今天 → HH:MM
    if (date.toDateString() === now.toDateString()) {
      return `${date.getHours().toString().padStart(2, "0")}:${date.getMinutes().toString().padStart(2, "0")}`;
    }
    // 昨天
    const yesterday = new Date(now);
    yesterday.setDate(now.getDate() - 1);
    if (date.toDateString() === yesterday.toDateString()) {
      return "昨天";
    }
    // 7天内 → 星期
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const msgDayStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
    const diffDays = Math.floor((todayStart - msgDayStart) / (1000 * 60 * 60 * 24));
    if (diffDays < 7) {
      const weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"];
      return weekdays[date.getDay()];
    }
    // 30天内 → M/D
    if (diffDays < 30) {
      return `${date.getMonth() + 1}/${date.getDate()}`;
    }
    // 更早 → YYYY/M/D
    return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`;
  }
}
