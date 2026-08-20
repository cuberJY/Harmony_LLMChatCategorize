/**
 * 搜索面板（SearchSheetPanel）
 * 从下方弹出的半模态搜索面板（由 SideBarPage 的搜索框 bindSheet 弹出，形式同 ChatPage 的网页/文本面板）
 *   - 无标题栏：顶部搜索框（自动聚焦）+ 内容范围复选框 + 结果列表
 *   - 交互：标题命中实时显示，内容命中防抖补全（带命中片段）；选中结果通过 onSelectConversation 回调通知父组件
 * 注：SearchViewModel 由父组件（SideBarPage）持有并传入，sheet 关闭再打开时状态保留、数据源由父组件刷新
 */

import { SearchViewModel, SearchResultGroup } from "../../viewmodel/SearchViewModel";
import { SearchResultItem } from "../item/SearchResultItem";
import { Conversation } from "../../model/Conversation";

@ComponentV2
export struct SearchSheetPanel {
  /* 搜索数据与业务逻辑（@ObservedV2，父组件 SideBarPage 持有并传入；@Trace 变化自动驱动本组件刷新） */
  @Param vm: SearchViewModel = new SearchViewModel();
  /* 选中搜索结果回调（父组件负责关闭面板并回传对话给 ChatPage；messageId 用于定位命中消息，标题命中为空串） */
  @Event onSelectConversation: (conv: Conversation, messageId: string) => void = (conv: Conversation, messageId: string) => {};

  build() {
    Column() {
      /* 搜索框 + 内容范围切换 */
      Column() {
        TextInput({ placeholder: "搜索对话...", text: this.vm.searchText })
          .height(40)
          .width("92.5%")
          .borderRadius(20)
          .borderWidth(1)
          .fontSize($r('app.float.font_input'))
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary')) // 占位符颜色
          .borderColor($r('app.color.input_border'))
          .backgroundColor($r('app.color.input_bg'))
          .padding({
            left: $r('app.float.space_md'),
            right: $r('app.float.space_md')
          })
          .margin({
            top: $r('app.float.space_md'),
            bottom: $r('app.float.space_sm'),
          })
          .defaultFocus(true) // 面板弹出后自动聚焦，可直接输入
          .onChange((value: string) => {
            /* 实时搜索：标题 + 消息内容（防抖与竞态守卫在 VM 内处理） */
            this.vm.onSearchChanged(value);
          })
          /* 输入法右下角按键显示为「搜索」，按下时立即搜索（跳过防抖） */
          .enterKeyType(EnterKeyType.Search)
          .onSubmit(() => {
            this.vm.submitSearch();
          });

        /* 内容搜索范围开关：关闭=仅激活分支消息，打开=全部消息（含被覆盖的变体） */
        Row() {
          Text("包含所有历史分支")
            .fontSize($r('app.float.font_body'))
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1);
          Toggle({ type: ToggleType.Switch, isOn: this.vm.searchScope !== "active" })
            .selectedColor($r('app.color.primary'))
            .onChange((isOn: boolean) => {
              /* 仅当状态真正变化时才切换（isOn 由 searchScope 推导，避免冗余触发） */
              if (isOn !== (this.vm.searchScope !== "active")) {
                this.vm.toggleSearchScope();
              }
            });
        }
        .width("100%")
        .padding({
          left: $r('app.float.space_lg'),
          right: $r('app.float.space_lg')
        })
      }
      .width("100%")

      /* 内容区：未输入提示 / 无结果提示 / 结果列表 */
      if (this.vm.searchText.trim().length === 0) {
      } else if (this.vm.results.length === 0) {
        Column() {
          Text("无搜索结果")
            .fontSize($r('app.float.font_remind'))
            .fontColor($r('app.color.text_secondary'))
            .offset({ y: -60 }) // 居中偏移，与结果列表垂直居中
        }
        .width("100%")
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center);
      } else {
        List() {
          ForEach(
            this.vm.results,
            (group: SearchResultGroup) => {
              ListItem() {
                SearchResultItem({
                  conversation: group.conversation,
                  titleHit: group.titleHit,
                  hits: group.hits,
                  onClickOpen: (selected: Conversation) => {
                    /* 组头点击：打开对话（不定位） */
                    this.onSelectConversation(selected, "");
                  },
                  onClickHit: (selected: Conversation, messageId: string) => {
                    /* 命中消息行点击：打开对话并定位到该条消息 */
                    this.onSelectConversation(selected, messageId);
                  },
                })
              }.width("100%");
            },
            (group: SearchResultGroup) => group.conversation.id,
          )
        }
        .width("100%")
        .layoutWeight(1)
        .backgroundColor($r('app.color.page_bg'))
        .divider({
          strokeWidth: 0.5,
          color: $r('app.color.divider'),
        });
      }
    }
    .width("100%")
    .height("100%")
    .backgroundColor($r('app.color.page_bg'));
  }
}
