import { common } from "@kit.AbilityKit";
import { window } from "@kit.ArkUI";
import { inputMethod } from "@kit.IMEKit";
import { Message } from "../model/Message";
import { Conversation, ConversationSelection } from "../model/Conversation";
import { SideBarParams } from "../model/SideBarParams";
import { MessageBubble } from "../components/chat/MessageBubble";
import { ChatInput } from "../components/chat/ChatInput";
import { WebSheetPanel } from "../components/panel/WebSheetPanel";
import { formatSmartTime } from "../common/TimeUtil";
import { NavTransitionManager } from "../common/NavTransitionManager";
import { showToast, KeyboardBackHelper, SafeAreaHelper } from "../common/Utils";
import { ChatViewModel } from "../viewmodel/ChatViewModel";
import { ThinkingEffort } from "../config/ModelPresets";
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
  /* 主窗口引用（注销键盘监听用） */
  private mainWindow?: window.Window;
  /**
   * 编辑态键盘弹出后的重新对齐防抖定时器（-1 = 无挂起）：
   * 等键盘动画停稳（RESIZE 压缩视口完成）再滚动，避免视口尺寸变化过程中多次跳动
   */
  private editAlignTimerId: number = -1;
  /* 侧边栏入栈中标记（防连点双开） */
  private isSideBarPushing: boolean = false;
  /**
   * 半模态面板状态（页面级统一管理）：弹层生命周期与页面绑定，
   * 避免 item 级 bindSheet 在 LazyForEach 中残留遮罩（修复：弹出弹窗后页面触摸被吞）
   */
  @Local sheetShow: boolean = false; // 面板显示状态（$$ 双向绑定，拖拽/点遮罩关闭时自动置回 false）
  @Local sheetKind: "none" | "text" | "web" = "none"; // 当前面板类型：「选择文本」/「xx个网页」
  @Local sheetMsg: Message = new Message("", "user", ""); // 当前面板对应的消息（面板内容数据源）
  /* 沉浸式系统栏高度（vp，EntryAbility 注入）：aboutToAppear 一次性读取（V2 无 @StorageProp，用 @Local + 手动读取） */
  @Local statusBarHeightVp: number = 0;
  @Local navBarHeightVp: number = 0;

  aboutToAppear(): void {
    /* 读取系统栏高度（标题栏/输入区内容避让用） */
    this.statusBarHeightVp = SafeAreaHelper.getStatusBarHeight();
    this.navBarHeightVp = SafeAreaHelper.getNavBarHeight();
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
        /* 键盘高度变化驱动全局键盘标志，供 @Entry HomePage.onBackPress 判断"本次返回是否刚收起键盘" */
        if (height > 0) {
          KeyboardBackHelper.onKeyboardShown();
          /**
           * 编辑态 + 键盘弹出：RESIZE 会把 List 视口压缩、ChatInput 顶起，
           * startEdit 时（键盘未弹）的对齐基于旧视口尺寸，需等键盘动画停稳后重新对齐
           */
          if (this.vm.editingMessageId.length > 0) {
            if (this.editAlignTimerId !== -1) {
              clearTimeout(this.editAlignTimerId);
            }
            this.editAlignTimerId = setTimeout(() => {
              this.editAlignTimerId = -1;
              this.vm.scrollToEditTarget();
            }, 100);
          }
        } else {
          KeyboardBackHelper.onKeyboardCollapsed();
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
      .height(SafeAreaHelper.getTitleBarHeight(this.getUIContext()) + this.statusBarHeightVp)
      .padding({
        top: this.statusBarHeightVp,
        left: $r('app.float.space_xl'),
        right: $r('app.float.space_xl'),
      })
      .backgroundColor($r('app.color.title_bar_bg'))
      /**
       * 沉浸式：expandSafeArea 让标题栏背景向上延伸到状态栏背后（与系统栏同色融为一体）；
       * 内容改用显式 padding（真实状态栏高度）避让——safeAreaPadding 在固定高度组件上会失效导致重叠
       */
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .border({
        width: { bottom: 2 },
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
                  /* 打开半模态面板（页面级统一管理）：记录目标消息并弹出 */
                  onOpenSheet: (m: Message, kind: "text" | "web") => {
                    this.sheetMsg = m;
                    this.sheetKind = kind;
                    this.sheetShow = true;
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
          /* 手指抬起 → 拖动结束，恢复流式 UI 写入与自动跟随，并尝试放行挂起的思考块折叠 */
          this.vm.onTouchReleased();
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
      /* 预加载上下各 10 条：缓解 Markdown 异步渲染的 item 高度突变与白块（气泡渲染较重，默认 1 不够） */
      .cachedCount(10)
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
        /* 底部导航条高度（vp）：输入区内容用其手动避让，避免被导航条遮挡 */
        navBarHeightVp: this.navBarHeightVp,
        /* 编辑态：回填原内容到输入框（vm.startEdit 后 @Trace 变化驱动刷新） */
        prefillText: this.vm.editingPrefill,
        isEditing: this.vm.editingMessageId.length > 0,
        /* 开关状态由 VM 持有（唯一真源）：发送/重新生成/新建分支读取当前值 */
        webSearch: this.vm.webSearch,
        thinkingEffort: this.vm.thinkingEffort,
        /* 流式生成状态（驱动发送/暂停键与「继续生成」按钮） */
        streamState: this.vm.streamState,
        /* 开关切换 → 同步 VM 唯一真源（@Trace 回流刷新输入区 UI） */
        onWebSearchChange: (webSearch: boolean) => {
          this.vm.updateSearchOptions(webSearch, this.vm.thinkingEffort);
        },
        onThinkingChange: (effort: ThinkingEffort) => {
          this.vm.updateSearchOptions(this.vm.webSearch, effort);
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
        /* 输入框焦点变化：聚焦必弹键盘 → 同步驱动全局键盘标志（同步可靠信号，
           弥补 keyboardHeightChange 冷启动首次弹键盘事件丢失的被动缺陷） */
        onInputFocusChange: (hasFocus: boolean) => {
          if (hasFocus) {
            KeyboardBackHelper.onInputFocus();
          }
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
    .height("100%")
    /**
     * 半模态面板（「选择文本」/「xx个网页」共用，页面级统一管理）：
     * 从下方弹出，高度 = 窗口高 - 状态栏 - 标题栏；弹层生命周期与页面绑定，
     * onDisappear 兜底复位状态，杜绝 item 级 bindSheet 残留遮罩拦截触摸
     */
    .bindSheet($$this.sheetShow, this.pageSheetContent(), {
      height: this.pageSheetHeight(),
      dragBar: false,
      showClose: false,
      backgroundColor: $r('app.color.dialog_bg'),
      onDisappear: () => {
        this.sheetShow = false;
        this.sheetKind = "none";
      },
    });
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
      /* 返回时复位防重入标记：onPop 仅在 pop 传参时才触发（pop() 无参数不回调），
         改用 onShown 保证任何返回方式（顶部返回键/系统返回键/选中对话）都能立即复位，
         避免「返回后需等超时才能再次打开侧边栏」 */
      this.isSideBarPushing = false;
    })
    .onBackPressed(() => {
      const backUp = this.isKeyboardUp();
      /** 
       * ChatPage 是栈底主页面（isEntry 入栈）：系统返回键 = 退出应用，
       * 拦截后不弹栈，避免 NavDestination 被弹出、回到空白的 Navigation 首页内容（NavBar）
       * 返回键优先级：键盘弹出（只收键盘） > 编辑态（取消编辑） > 退出应用
       */
      if (backUp) {
        /* 键盘弹出：主动收起输入法并消费返回（键盘状态由全局标志同步判定，已消除事件时序误判） */
        inputMethod.getController().stopInput();
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

  /* 半模态面板内容：按当前面板类型分支渲染（sheetKind 在打开前设置，页面级统一管理） */
  @Builder
  pageSheetContent() {
    if (this.sheetKind === "text") {
      this.pageTextSheet();
    } else if (this.sheetKind === "web") {
      WebSheetPanel({
        webs: this.sheetMsg.searchedWebs,
        onClose: () => { this.sheetShow = false; },
      });
    }
  }

  /* 「选择文本」面板：居中标题 + 右上角关闭，正文为 Markdown 源码可长按复制（与上提前 item 级面板完全一致） */
  @Builder
  pageTextSheet() {
    Column() {
      /* 标题行：左右等宽占位保证标题居中 */
      Row() {
        /* 左侧占位（与右侧关闭按钮等宽，保证标题视觉居中） */
        Row().width($r('app.float.space_xxl'))
        Text($r('app.string.select_text'))
          .fontSize($r('app.float.font_title'))
          .fontWeight(700)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        /* 右上角关闭按钮（叉） */
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize($r('app.float.font_icon_lg'))
            .fontWeight(700)
            .fontColor([$r('app.color.text_primary')])
        }
        .width($r('app.float.space_xxl'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.sheetShow = false;
        })
      }
      .width("100%")
      .height($r('app.float.title_bar_height'))
      .padding({
        left: $r('app.float.space_xl'),
        right: $r('app.float.space_xl'),
      })
      /* 标题行底部分割线 */
      .border({
        width: { bottom: 2 },
        color: { bottom: $r('app.color.divider') },
      })

      /* 渲染前的原始文本（Markdown 源码），copyOption 支持长按选择与复制 */
      Scroll() {
        Text(this.sheetMsg.content)
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.text_ai'))
          .copyOption(CopyOptions.LocalDevice)
          .width("100%")
          .padding({
            left: $r('app.float.space_xl'),
            right: $r('app.float.space_xl'),
            top: $r('app.float.space_lg'),
            bottom: $r('app.float.space_lg'),
          })
      }
      .width("100%")
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width("100%")
    .height("100%")
    .backgroundColor($r('app.color.dialog_bg'))
  }

  /**
   * 计算半模态面板高度（vp）：
   * 面板从底部弹出，要求其顶部与页面顶部标题栏下缘对齐，
   * 故 高度 = 窗口高度 - 状态栏高度 - 标题栏高度（窗口/状态栏为 px，统一转 vp）。
   */
  private pageSheetHeight(): number {
    try {
      const host = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (host === undefined || host.windowStage === undefined) {
        return 500; // 兜底高度
      }
      /* 标题栏高度（float 资源带 'vp' 单位，getNumber 返回 px，需转回 vp） */
      const titleBarHeightPx = host.resourceManager.getNumber($r('app.float.title_bar_height').id);
      const titleBarHeight = this.getUIContext().px2vp(titleBarHeightPx);
      const win = host.windowStage.getMainWindowSync();
      /* 窗口总高度（px） */
      const windowHeightPx = win.getWindowProperties().windowRect.height;
      /* 状态栏（顶部安全区）高度（px），非沉浸式窗口时为 0 */
      const safeTopPx = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height;
      const windowHeight = this.getUIContext().px2vp(windowHeightPx);
      const safeTop = this.getUIContext().px2vp(safeTopPx);
      return Math.max(200, windowHeight - safeTop - titleBarHeight);
    } catch (e) {
      return 500; // 异常兜底，保证面板可显示
    }
  }

  /**
   * 同步判断键盘是否弹出（返回键拦截用）：
   * 复用全局键盘标志（onFocus + keyboardHeightChange 双源驱动），避免重复维护状态。
   * 注：实测 RESIZE 模式下 getWindowAvoidArea(TYPE_KEYBOARD) 恒为 0，不能用于判断键盘状态。
   */
  private isKeyboardUp(): boolean {
    return KeyboardBackHelper.isKeyboardUpNow();
  }

  /**
   * 跳转侧边栏（Navigation 方式）
   * pushDestinationByName 的 onPop 回调在侧边栏/文件夹页面出栈返回时触发：
   *   - 刷新模型名与标题（vm.onPageShow）
   *   - 若返回时携带选中的对话（pop(conv)），则加载该对话
   * 采用异步版本：跳转被 Navigation 忽略（如弹窗/转场占用）时可通过 catch 感知，
   * 及时复位防重入标记，避免 isSideBarPushing 永久卡死导致侧边栏再也打不开
   */

  private pushSideBar(): void {
    /* 防重入：入栈/转场期间忽略再次触发 */
    if (this.isSideBarPushing) {
      return;
    }
    this.isSideBarPushing = true;
    this.pathStack.pushDestinationByName(
      "SideBarPage",
      new SideBarParams(this.vm.getCurrentConversationId()),
      (popInfo: PopInfo) => {
        /* 选中对话返回：
           老路径 pop(Conversation) → 仅加载对话；
           搜索面板 pop(ConversationSelection) → 加载对话并定位到命中消息（focusMessageId）。
           标题/模型名刷新与防重入复位由 NavDestination.onShown 统一负责 */
        const result = popInfo.result;
        if (result === undefined || result === null) {
          return;
        }
        const selection = result as ConversationSelection;
        if (selection.conv !== undefined && selection.focusMessageId !== undefined) {
          this.vm.loadConversation(selection.conv, selection.focusMessageId);
          return;
        }
        const conv = result as Conversation;
        if (conv.id.length > 0) {
          this.vm.loadConversation(conv);
        }
      },
    ).catch(() => {
      /* 跳转失败（Navigation 状态异常/被占用）：复位防重入标记，允许用户再次尝试。
         此路径 onShown 不会触发（ChatPage 未被覆盖），故必须在此复位 */
      this.isSideBarPushing = false;
    });
  }
}