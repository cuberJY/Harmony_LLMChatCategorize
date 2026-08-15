import { common } from "@kit.AbilityKit";
import { window } from "@kit.ArkUI";
import { Message } from "../model/Message";
import { Conversation } from "../model/Conversation";
import { SideBarParams } from "../model/SideBarParams";
import { MessageBubble } from "../components/chat/MessageBubble";
import { ChatInput } from "../components/chat/ChatInput";
import { formatSmartTime } from "../common/TimeUtil";
import { NavTransitionManager } from "../common/NavTransitionManager";
import { showToast } from "../common/Utils";
import { ChatViewModel } from "../viewmodel/ChatViewModel";
import { Markdown, MarkdownController } from "@luvi/lv-markdown-in";

/**
 * 状态管理 V2 结构：
 * 页面只保留 build 布局、路由跳转、页面过渡动画；
 * 数据与业务逻辑（消息列表、发送、流式回复、滚动控制）全部收敛到 ChatViewModel（@ObservedV2）
 */
@ComponentV2
export struct ChatPage {
  /* 路由栈（NavDestination.onReady 获取）：用于跳转侧边栏并接收返回结果 */
  private pathStack: NavPathStack = new NavPathStack();
  /**
   * 本页作为抽屉动画的底板：保持原位，不参与位移动画（SideBarPage 覆盖其上滑动）。
   * 业务状态与逻辑（@Trace 状态 + 数据源 + 滚动控制）
   */
  private vm: ChatViewModel = new ChatViewModel();
  /* Markdown 库预热控制器（仅用于触发库初始化，不参与实际渲染） */
  private mdPreloadController: MarkdownController = new MarkdownController();
  /* 键盘是否弹出（keyboardHeightChange 监听维护）：返回键拦截用——键盘弹出时返回键只收键盘 */
  private isKeyboardShowing: boolean = false;
  /* 主窗口引用（注销键盘监听用） */
  private mainWindow?: window.Window;
  /**
   * 编辑态键盘弹出后的重新对齐防抖定时器（-1 = 无挂起）：
   * 等键盘动画停稳（RESIZE 压缩视口完成）再滚动，避免视口尺寸变化过程中多次跳动
   */
  private editAlignTimerId: number = -1;
  /* 侧边栏入栈中标记（防连点双开） */
  private isSideBarPushing: boolean = false;

  aboutToAppear(): void {
    /* 初始化数据库（页面级 UIAbilityContext） */
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.vm.aboutToAppear(context);
    /* 注入正文生成阶段的平滑跟随动画：思考阶段即时钉底，正文阶段用 200ms EaseOut 过渡保留顺滑 */
    this.vm.setScrollAnimator((action: () => void): void => {
      /* animateTo 的 curve 支持字符串（'easeOut'），避免依赖 Curve 枚举导出 */
      this.getUIContext().animateTo({ duration: 200, curve: 'easeOut' }, action);
    });
    /**
     * 模型名/标题等显示期状态在 onShown 中刷新（首次与每次从其他页面返回都触发）。
     * 监听键盘高度变化：返回键拦截用（鸿蒙缺陷：键盘弹出时按返回键，系统收键盘的同时会
     * 把返回键交给应用执行返回逻辑；若不区分"键盘弹出"，收键盘那一下就会误取消编辑/退出应用）
     */
    window.getLastWindow(context).then((win: window.Window) => {
      this.mainWindow = win;
      win.on('keyboardHeightChange', (height: number) => {
        this.isKeyboardShowing = height > 0;
        /**
         * 编辑态 + 键盘弹出：RESIZE 会把 List 视口压缩、ChatInput 顶起，
         * startEdit 时（键盘未弹）的对齐基于旧视口尺寸，需等键盘动画停稳后重新对齐
         */
        if (height > 0 && this.vm.editingMessageId.length > 0) {
          if (this.editAlignTimerId !== -1) {
            clearTimeout(this.editAlignTimerId);
          }
          this.editAlignTimerId = setTimeout(() => {
            this.editAlignTimerId = -1;
            this.vm.scrollToEditTarget();
          }, 100);
        }
      });
    });
  }

  aboutToDisappear(): void {
    /* 页面销毁时清理定时器，防止内存泄漏 */
    this.vm.aboutToDisappear();
    /* 注销转场动画回调（本页是路由栈首页，索引恒为 0） */
    NavTransitionManager.getInstance().unregister(0);
    /* 清理编辑态重新对齐的防抖定时器，防止回调泄漏 */
    if (this.editAlignTimerId !== -1) {
      clearTimeout(this.editAlignTimerId);
      this.editAlignTimerId = -1;
    }
    /* 注销键盘高度监听，防止回调泄漏 */
    if (this.mainWindow !== undefined) {
      this.mainWindow.off('keyboardHeightChange');
      this.mainWindow = undefined;
    }
  }

  /* 右下角"回到底部"悬浮按钮 */
  @Builder
  scrollToBottomFab() {
    Button() {
      SymbolGlyph($r("sys.symbol.chevron_down"))
        .fontSize($r('app.float.font_icon_xl'))
        .fontWeight(700)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(32)
    .height(32)
    .type(ButtonType.Circle)
    .backgroundColor($r('app.color.bubble_bg_ai'))
    .border({ width: 1, color: $r('app.color.divider') })
    .margin({
      right: $r('app.float.space_xl'),
      bottom: $r('app.float.space_xl')
    })
    .onClick(() => {
      /* 强制滚动到最底部（绕过自动跟随守卫） */
      this.vm.jumpToBottom();
    })
  }

  build() {
    /* ChatPage 作为 NavDestination 首页（isEntry 入栈），使 customNavContentTransition 能同时驱动聊天页与侧边栏位移动画 */
    NavDestination() {
    Column() {
      Row() {
        Row() {
          /* "三横线"图标，点击弹出侧边栏 */
          SymbolGlyph($r("sys.symbol.sort"))
            .fontSize($r('app.float.font_icon_xl'))
            .fontWeight(700)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(40)
        .justifyContent(FlexAlign.Start)
        .onClick(() => {
          this.pushSideBar();
        })

        Text(this.vm.title)
          .fontSize($r('app.float.font_title'))
          .fontWeight(700)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Row() {
          SymbolGlyph($r("sys.symbol.message_badge_plus"))
            .fontSize($r('app.float.font_icon_xxl'))
            .fontWeight(700)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(40)
        .justifyContent(FlexAlign.End)
        .onClick(() => {
          /* 已在空白"新对话"中 → 提示，不重复创建 */
          if (this.vm.messageDataSource.totalCount() === 0) {
            showToast($r('app.string.already_in_new_conversation'));
            return;
          }
          /* 创建新对话对象，清空消息列表（不立即入库，等待首条用户消息） */
          this.vm.newConversation();
        })
      }
      .width("100%")
      .height($r('app.float.title_bar_height'))
      .padding({ left: $r('app.float.space_xl'), right: $r('app.float.space_xl') })
      .backgroundColor($r('app.color.title_bar_bg'))
      .border({
        width: { bottom: 1 },
        color: { bottom: $r('app.color.divider') },
      })

      /* 消息列表区域（Stack 叠加右下角"回到底部"悬浮按钮） */
      Stack({ alignContent: Alignment.BottomEnd }) {
      List({ scroller: this.vm.listScroller }) {
        /* LazyForEach：懒加载只渲染可视区消息，减少渲染开销；@Trace 属性变化驱动 MessageBubble 自动更新 */
        LazyForEach(
          this.vm.messageDataSource,
          (msg: Message, index: number) => {
            ListItem() {
              Column() {
                if (this.vm.shouldShowTimeDivider(index)) {
                  Text(formatSmartTime(msg.createdAt))
                    .fontSize($r('app.float.font_time')) // 11sp
                    .fontColor($r('app.color.text_secondary')) // #999999
                    .width("100%")
                    .textAlign(TextAlign.Center)
                    .padding({ top: $r('app.float.space_lg'), bottom: $r('app.float.space_xs') });
                }

                MessageBubble({
                  message: msg,
                  /* 分支变体信息：驱动 "< 当前 / 总数 >"；getVariantInfo 已缓存，二次调用 O(1) */
                  variantCurrent: this.vm.getVariantInfo(msg).current,
                  variantTotal: this.vm.getVariantInfo(msg).total,
                  /* 是否激活链最后一条：仅最后一条显示「换个回答」（防止在历史消息上重新生成导致上下文混乱） */
                  isLastMessage: index === this.vm.messageDataSource.totalCount() - 1,
                  /* 正在编辑的用户消息 id：编辑中的消息禁止删除（点击直接 toast） */
                  editingMessageId: this.vm.editingMessageId,
                  /* 换个回答：覆盖当前 AI 回复 */
                  onRegenerate: (m: Message) => {
                    this.vm.regenerateMessage(m);
                  },
                  /* 生成新回复：保留旧回复生成新变体 */
                  onCreateBranch: (m: Message) => {
                    this.vm.createBranch(m);
                  },
                  /* 编辑：回填输入框（发送时创建新分支） */
                  onEdit: (m: Message) => {
                    this.vm.startEdit(m);
                  },
                  /* 切换分支：在变体间 ±1 循环 */
                  onSwitchBranch: (m: Message, delta: number) => {
                    this.vm.switchBranch(m, delta);
                  },
                  /* 删除：删除该消息及其后续所有分支（子树整体删除） */
                  onDelete: (m: Message) => {
                    this.vm.deleteMessage(m);
                  },
                  /* 继续生成：暂停态下从未完成处续写（传入被点击的消息，按消息定位任务） */
                  onResume: (m: Message) => {
                    this.vm.resumeStreaming(m);
                  },
                })
              }.width("100%")
              .onAreaChange((oldArea: Area, newArea: Area) => {
                /* 消息项高度变化（Markdown 异步渲染增高）→ 立即重新钉底；Area.height 运行时为 number，用 Number() 数值化求增量 */
                this.vm.onListItemHeightChanged(Number(newArea.height) - Number(oldArea.height));
              })
            }.width("100%");
          },
          (msg: Message) => msg.id,
        )
      }
      .height("100%")
      /* 列表自上而下排布，超出屏幕后的钉底由 scrollToBottom() 的 scrollToIndex(END) 保证 */
      .onAreaChange((oldValue: Area, newValue: Area) => {
        /* 首帧布局完成（首次回调）→ 通知 ViewModel 开始钉底，避免"打开瞬间停留在列表顶部" */
        this.vm.onListFirstLayout();
        /* 可视区变矮 = 键盘弹出窗口被压缩 → 重新钉到底部 */
        if (newValue.height < oldValue.height) {
          this.vm.scrollToBottom();
        }
      })
      .onTouch((event: TouchEvent) => {
        /* 手指按下列表 = 用户正在操作（滚动/长按/选择文本等） */
        if (event.type === TouchType.Down) {
          /* 生成期间用户触摸屏幕操作内容 → 标记"操作中"，完成生成时不自动滚到底 */
          this.vm.markUserOperating(true);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          /* 手指抬起 → 拖动结束，恢复流式 UI 写入与自动跟随 */
          this.vm.setUserScrolling(false);
          this.vm.markUserOperating(false);
        }
      })
      /* 用户主动滚动取消自动跟随；排除代码滚动（SCROLLER/SCROLLER_ANIM）与边缘回弹，避免打断自动钉底 */
      .onWillScroll(
        (scrollOffset: number, scrollState: ScrollState, scrollSource: ScrollSource) => {
          /* 判定本次滚动是否来自用户手势（拖动/惯性/滚动条/其他输入） */
          const isUserGesture = scrollSource === ScrollSource.DRAG || scrollSource === ScrollSource.FLING
            || scrollSource === ScrollSource.OTHER_USER_INPUT
            || scrollSource === ScrollSource.SCROLL_BAR
            || scrollSource === ScrollSource.SCROLL_BAR_FLING;
          /* 记录来源，供 onReachEnd 区分"用户滚回底部"与"代码滚动到底" */
          this.vm.setLastScrollSource(isUserGesture);
          /* 用户滚动手势（DRAG/FLING/滚动条等）期间暂停流式 UI 写入，避免底部高度变化与滚动竞争抖动 */
          this.vm.setUserScrolling(isUserGesture);
          /* 用户主动滚动 → 取消自动跟随（代码滚动 SCROLLER/SCROLLER_ANIM 不取消） */
          if (isUserGesture) {
            this.vm.setAtBottom(false);
          }
        },
      )
      /* 真正滚到列表底部边缘 → 恢复自动跟随（同时清除"操作中"标记与滚动操作状态） */
      .onReachEnd(() => {
        this.vm.handleReachEnd();
      })
      /* 滚动停止（含惯性）→ 恢复流式 UI 写入并放行挂起折叠；兜底 onTouch Up 可能被文本选择手势拦截 */
      .onScrollStop(() => {
        this.vm.handleScrollStop();
      })
      .width("100%")
      .backgroundColor($r('app.color.page_bg'))
      .edgeEffect(EdgeEffect.Spring)
      /* 预加载上下各 5 条：缓解 Markdown 异步渲染的 item 高度突变与白块（气泡渲染较重，默认 1 不够） */
      .cachedCount(5)
      /* 保持可见内容位置不变：避免流式输出底部 item 长高时向上翻历史被顶跳 */
      .maintainVisibleContentPosition(true)

        /* 悬浮"回到底部"按钮：非底部且非编辑态时显示；编辑态隐藏，避免遮挡编辑中的消息 */
        if (!this.vm.isAtBottom && this.vm.editingMessageId.length === 0) {
          this.scrollToBottomFab();
        }
      }
      .layoutWeight(1)
      .width("100%")

      ChatInput({
        modelName: this.vm.modelName,
        /* 编辑态：回填原内容到输入框（vm.startEdit 后 @Trace 变化驱动刷新） */
        prefillText: this.vm.editingPrefill,
        isEditing: this.vm.editingMessageId.length > 0,
        /* 开关状态由 VM 持有（唯一真源）：发送/重新生成/新建分支读取当前值 */
        webSearch: this.vm.webSearch,
        deepThinking: this.vm.deepThinking,
        /* 流式生成状态（驱动发送/暂停键与「继续生成」按钮） */
        streamState: this.vm.streamState,
        /* 开关切换 → 同步 VM 唯一真源（@Trace 回流刷新输入区 UI） */
        onToggleChange: (webSearch: boolean, deepThinking: boolean) => {
          this.vm.updateSearchOptions(webSearch, deepThinking);
        },
        onChange: (text: string) => {
          /* 编辑态由 ViewModel 内部识别：非编辑态 = 普通发送；编辑态 = 创建新分支并重新生成 */
          this.vm.handleUserSend(text);
        },
        /* 生成中点击暂停键 → 中止流式请求，保留已生成内容 */
        onPause: () => {
          this.vm.pauseStreaming();
        },
        /* 编辑态点击顶部右侧 xmark → 退出编辑态并清空输入框（@Monitor 联动清空） */
        onCancelEdit: () => {
          this.vm.exitEditMode();
        },
      })

      /* Markdown 库预热：提前触发 lv-markdown-in worker 初始化，消除首次打开正文卡顿（Hidden 零尺寸不占布局） */
      Markdown({
        text: "**预热**",
        mode: "text",
        controller: this.mdPreloadController,
      })
        .visibility(Visibility.Hidden)
        .width(0)
        .height(0)
    }

    /* 从左向右滑 → 打开侧边栏 */
    .gesture(
      PanGesture({ direction: PanDirection.Right, distance: 40 }).onActionStart(() => {
        this.pushSideBar();
      }),
    )
    .width("100%")
    .height("100%");
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      /**
       * 注册转场动画回调（ChatPage 是路由栈首页，索引恒为 0）。
       * 本页作为底板不参与位移动画，但必须保留注册：
       * HomePage 的 customNavContentTransition 需要 from/to 双方回调都存在，才能驱动 SideBarPage 的位移
       */
      NavTransitionManager.getInstance().register(0, {
        start: () => {},
        finish: () => {},
        onFinish: () => {},
      });
    })
    .onShown(() => {
      /* 每次显示（含从侧边栏/文件夹返回）时刷新模型名与标题 */
      this.vm.onPageShow();
    })
    .onBackPressed(() => {
      /** 
       * ChatPage 是栈底主页面（isEntry 入栈）：系统返回键 = 退出应用，
       * 拦截后不弹栈，避免 NavDestination 被弹出、回到空白的 Navigation 首页内容（NavBar）
       * 返回键优先级：键盘弹出（只收键盘） > 编辑态（取消编辑） > 退出应用
       */
      if (this.isKeyboardShowing) {
        return true;
      }
      if (this.vm.editingMessageId.length > 0) {
        this.vm.exitEditMode(); // 取消编辑：清空 editingMessageId/prefill，输入框联动恢复
        return true; // 拦截本次返回，不退出应用
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.terminateSelf();
      return true; // true = 本页自行处理返回键，框架不再执行默认弹栈
    })
  }

  /**
   * 跳转侧边栏（Navigation 方式）
   * pushPathByName 的 onPop 回调在侧边栏/文件夹页面出栈返回时触发：
   *   - 刷新模型名与标题（vm.onPageShow）
   *   - 若返回时携带选中的对话（pop(conv)），则加载该对话
   */

  private pushSideBar(): void {
    /* 防重入：入栈/转场期间忽略再次触发 */
    if (this.isSideBarPushing) {
      return;
    }
    this.isSideBarPushing = true;
    this.pathStack.pushPathByName(
      "SideBarPage",
      new SideBarParams(this.vm.getCurrentConversationId()),
      (popInfo: PopInfo) => {
        this.isSideBarPushing = false;
        this.vm.onPageShow();
        const conv = popInfo.result as Conversation | undefined;
        if (conv && conv.id.length > 0) {
          this.vm.loadConversation(conv);
        }
      },
    );
  }
}