/**
 * 搜索结果分组列表项组件
 * 用于搜索结果列表展示「一个对话为组的全部命中」：
 *   - 组头：对话标题（标题命中时带标记）+ 命中条数 + 更新时间，点击打开对话（不定位）
 *   - 组内：每条内容命中消息一行（片段 5 行省略 + 消息发送时间），点击精确定位到该消息
 */

import { Conversation } from "../../model/Conversation";
import { SearchHit } from "../../viewmodel/SearchViewModel";
import { formatSmartTime } from "../../common/TimeUtil";

@ComponentV2
export struct SearchResultItem {
  /* 搜索命中的对话（由父组件传入的 @ObservedV2 对象） */
  @Param conversation: Conversation = new Conversation();
  /* 是否标题命中（组头显示命中标记；仅标题命中时 hits 为空） */
  @Param titleHit: boolean = false;
  /* 内容命中的所有消息（按发送时间升序，可能为空） */
  @Param hits: SearchHit[] = [];

  /* 回调（@Event：V2 允许父组件初始化的普通事件） */
  /* 组头点击 → 打开对话（无定位目标） */
  @Event onClickOpen: (conv: Conversation) => void = (conv: Conversation) => {};
  /* 命中消息行点击 → 打开对话并定位到该条消息 */
  @Event onClickHit: (conv: Conversation, messageId: string) => void = (conv: Conversation, messageId: string) => {};

  build() {
    Column() {
      /* 组头：标题 + 命中条数 + 更新时间 */
      Row() {
        Column() {
          Row() {
            Text(this.conversation.title.length > 0 ? this.conversation.title : "新对话")
              .fontSize($r('app.float.font_name'))
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width("100%")
          }
          /* 命中信息行：标题命中标记 + 内容命中条数（均为空时整行不显示） */
          if (this.titleHit || this.hits.length > 0) {
            Row() {
              if (this.titleHit) {
                Text("标题")
                  .fontSize($r('app.float.font_time'))
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ right: $r('app.float.space_xs') })
              }
              if (this.hits.length > 0) {
                Text(`${this.hits.length} 条搜索结果`)
                  .fontSize($r('app.float.font_time'))
                  .fontColor($r('app.color.text_secondary'))
              }
            }
            .width("100%")
            .margin({ top: $r('app.float.space_xxs') })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        /* 组头右侧：对话最后更新时间 */
        Text(formatSmartTime(this.conversation.updatedAt))
          .fontSize($r('app.float.font_time'))
          .fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
          .margin({
            left: $r('app.float.space_md'),
            top: $r('app.float.space_xxs')
        })
      }
      .width("100%")
      .padding({
        left: $r('app.float.space_lg'),
        right: $r('app.float.space_lg'),
        top: $r('app.float.space_md'),
        bottom: $r('app.float.space_md'),
      })
      .onClick(() => {
        if (this.onClickOpen) this.onClickOpen(this.conversation);
      })

      /* 组内：每条内容命中消息一行（片段 + 消息时间），点击精确定位 */
      ForEach(this.hits, (hit: SearchHit) => {
        Row() {
          /* 命中片段摘要（5行省略） */
          Text(hit.snippet)
            .fontSize($r('app.float.font_thinking'))
            .fontColor($r('app.color.text_secondary'))
            .maxLines(5)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          /* 命中消息发送时间 */
          Text(formatSmartTime(hit.createdAt))
            .fontSize($r('app.float.font_time'))
            .fontColor($r('app.color.text_secondary'))
            .alignSelf(ItemAlign.Start)
            .margin({
              left: $r('app.float.space_md'),
              top: $r('app.float.space_xxs')
            })
        }

        .width("100%")
        .padding({
          left: $r('app.float.space_xxl'),
          right: $r('app.float.space_lg'),
          top: $r('app.float.space_sm'),
          bottom: $r('app.float.space_sm'),
        })
        .backgroundColor($r('app.color.bubble_bg_thinking'))
        .onClick(() => {
          if (this.onClickHit) this.onClickHit(this.conversation, hit.messageId);
        })
      }, (hit: SearchHit) => hit.messageId)
    }
    .width("100%")
  }
}
