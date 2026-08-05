// 主聊天页面
import { router } from "@kit.ArkUI";
import { common } from "@kit.AbilityKit";
import { Message } from "../model/Message";
import { MessageBubble } from "../components/MessageBubble";
import { ChatInput } from "../components/ChatInput";
import { formatSmartTime } from "../common/TimeUtil";
import { ChatViewModel } from "../viewmodel/ChatViewModel";

/**
 * 状态管理 V2 结构：
 * 页面只保留 build 布局、路由跳转、页面过渡动画；
 * 数据与业务逻辑（消息列表、发送、流式回复、滚动控制）全部收敛到 ChatViewModel（@ObservedV2）
 */
@Entry
@ComponentV2
struct ChatPage {
  // 业务状态与逻辑（@Trace 状态 + 数据源 + 滚动控制）
  private vm: ChatViewModel = new ChatViewModel();

  aboutToAppear(): void {
    // 初始化数据库（页面级 UIAbilityContext）
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.vm.aboutToAppear(context);
  }

  aboutToDisappear(): void {
    // 页面销毁时清理定时器，防止内存泄漏
    this.vm.aboutToDisappear();
  }

  /**
   * 页面每次显示时触发（首次启动 + 从 SideBarPage 返回）
   * 检查 AppConfig.selectedConversation：有值则加载该历史对话
   */
  onPageShow(): void {
    this.vm.onPageShow();
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        // 左侧：侧边栏入口
        Row() {
          // "三横线"图标，点击弹出侧边栏
          SymbolGlyph($r("sys.symbol.sort"))
            .fontSize($r('app.float.font_icon_xl'))
            .fontWeight(700)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(40)
        // 固定宽度保持对称
        .justifyContent(FlexAlign.Start)
        .onClick(() => {
          router.pushUrl({ url: "pages/SideBarPage" });
        })

        // 中间：APP 标题
        Text(this.vm.title)
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          // 占据中间剩余空间
          .textAlign(TextAlign.Center)

        // 右侧：「新建对话」按钮
        Row() {
          SymbolGlyph($r("sys.symbol.plus"))
            .fontSize($r('app.float.font_icon_xl'))
            .fontWeight(700)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(40)
        .justifyContent(FlexAlign.End)
        .onClick(() => {
          // 创建新对话对象，清空消息列表（不立即入库，等待首条用户消息）
          this.vm.newConversation();
        })
      }
      .width("100%")
      .height($r('app.float.title_bar_height'))
      .padding({ left: $r('app.float.space_xl'), right: $r('app.float.space_xl') })
      .backgroundColor($r('app.color.title_bar_bg'))
      // 底部分割线
      .border({
        width: { bottom: 1 },
        color: { bottom: $r('app.color.divider') },
      })

      // 消息列表区域
      List({ scroller: this.vm.listScroller }) {
        /**
         * LazyForEach：懒加载列表，只渲染可视区域内的消息（方案 C）
         * 相比 ForEach 全量渲染，消息量大时显著减少渲染开销
         * Message 是 @ObservedV2 类，属性变化由 @Trace 驱动 MessageBubble（@Param）自动感知
         */
        LazyForEach(
          this.vm.messageDataSource,
          (msg: Message, index: number) => {
            ListItem() {
              Column() {
                // 判断是否需要时间分割线
                if (this.vm.shouldShowTimeDivider(index)) {
                  Text(formatSmartTime(msg.createdAt))
                    .fontSize($r('app.float.font_time')) // 11sp
                    .fontColor($r('app.color.text_secondary')) // #999999
                    .width("100%")
                    .textAlign(TextAlign.Center) // ← 居中显示
                    .padding({ top: $r('app.float.space_lg'), bottom: $r('app.float.space_xs') });
                }

                // 气泡本体
                MessageBubble({ message: msg })
              }.width("100%")
            }.width("100%");
          },
          (msg: Message) => msg.id, // 用 msg.id 作为唯一 key
        )
      }
      // layoutWeight(1)：占据 Column 去掉标题栏和输入框后的全部剩余空间
      .layoutWeight(1)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        // 可视区变矮 = 键盘弹出窗口被压缩 → 重新钉到底部
        if (newValue.height < oldValue.height) {
          this.vm.scrollToBottom();
        }
      })
      .onTouch((event: TouchEvent) => {
        // 手指按下列表 = 用户正在操作
        if (event.type === TouchType.Down) {
          this.vm.setUserScrolling(true);
        }
      })
      .onScrollStop(() => {
        // 滚动完全停止（含手指松开后的惯性滑完）→ 用户操作结束
        this.vm.setUserScrolling(false);
      })
      // 用户手指拖动或惯性滑动 → 取消自动跟随）
      .onWillScroll(
        (scrollOffset: number, scrollState: ScrollState, scrollSource: ScrollSource) => {
          // 只有用户手指拖动/惯性滑动才取消自动跟随
          if (scrollSource === ScrollSource.DRAG || scrollSource === ScrollSource.FLING) {
            this.vm.setAtBottom(false);
          }
        },
      )
      // 真正滚到列表底部边缘 → 恢复自动跟随
      .onReachEnd(() => {
        this.vm.setAtBottom(true);
      })
      .width("100%")
      .backgroundColor($r('app.color.page_bg'))
      // 列表宽高反向排列（新消息在底部）→ 不需要，正常从上到下即可
      .edgeEffect(EdgeEffect.Spring) // 滑动到顶/底部有弹性效果

      // 底部输入区域
      ChatInput({
        modelName: this.vm.modelName, // 从配置获取当前模型名称
        onChange: (text: string, webSearch: boolean, deepThinking: boolean) => {
          this.vm.handleUserSend(text, webSearch, deepThinking);
        },
      })
    }

    // 从左向右滑→ 跳转历史页
    .gesture(
      PanGesture({ direction: PanDirection.Right, distance: 40 }).onActionStart(() => {
        router.pushUrl({ url: "pages/SideBarPage" });
      }),
    )
    // Column 占满整个屏幕
    .width("100%")
    .height("100%");
  }

  // 对话页面过渡动画
  pageTransition() {
    // 打开（Push）：ChatPage 同时向右移动，把位置让给侧边栏
    PageTransitionExit({ type: RouteType.Push, duration: 150, curve: Curve.EaseOut }).translate({
      x: "100%",
    });
    // 返回（Pop）：ChatPage 从右侧滑回原位（向左移动）
    PageTransitionEnter({ type: RouteType.Pop, duration: 150, curve: Curve.EaseOut }).translate({
      x: "100%",
    });
  }
}