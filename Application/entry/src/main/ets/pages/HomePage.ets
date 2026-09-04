/**
 * 宿主页面（Navigation 路由容器）
 * Navigation 路由重构
 * - 唯一的 @Entry 入口页面（其余页面作为 NavDestination，不再单独注册）
 * - 持有 NavPathStack 统一管理页面路由：入栈 / 出栈 / 参数传递 / 返回结果
 * - ChatPage 作为路由栈首页（isEntry 入栈，不可出栈），其余为栈内 NavDestination
 * - customNavContentTransition 实现抽屉式覆盖切换动画（150ms EaseOut）：
 *     打开侧边栏（Push）：ChatPage 保持原位 + SideBarPage 从左侧 -100% 滑入覆盖其上
 *     关闭侧边栏（Pop）：SideBarPage 向左滑出 -100%，露出底层的 ChatPage
 *
 * 页面间传参约定（替代 router + AppConfig.selectedConversation）：
 *   - 正向传参：pushPathByName(name, param)，页面从 @Param 或 getParamByName 接收
 *   - 返回传参：pop(result)，发起方在 pushPathByName 的 onPop 回调中接收
 *   - 跨页返回链路示例：ChatPage → SideBarPage → FolderPage
 *     FolderPage.pop(conv) → SideBarPage 注册的 onPop 转发 → SideBarPage.pop(conv)
 *     → ChatPage 注册的 onPop 接收并加载对话
 */

/* 引入各页面组件（Navigation 以组件形式挂载，须显式 import；不再通过路由字符串注册） */
import { ChatPage } from "./ChatPage";
import { SideBarPage } from "./SideBarPage";
import { FolderPage } from "./FolderPage";
import { SettingsPage } from "./SettingsPage";
import { ModelConfigPage } from "./ModelConfigPage";
import { AccountSyncPage } from "./AccountSyncPage";
import { ImagePreviewPage, ImagePreviewParams } from "./ImagePreviewPage";
import { MarkdownPreviewPage, MarkdownPreviewParams } from "./MarkdownPreviewPage";
/* FolderPage 路由参数（pushPathByName 的第二个参数） */
import { FolderParams } from "../model/FolderParams";
/* SideBarPage 路由参数 */
import { SideBarParams } from "../model/SideBarParams";
/* 页面转场动画回调管理（配合 customNavContentTransition 驱动各页面自身的位移动画） */
import { NavTransitionManager } from "../common/NavTransitionManager";
/* 键盘返回键辅助器（解决键盘弹出时按返回键被系统直接执行根页面返回的缺陷） */
import { KeyboardBackHelper } from "../common/Utils";
import { inputMethod } from '@kit.IMEKit';
import { display, window } from "@kit.ArkUI";
import { getDeviceState, DeviceState, getWindowWidthVp, calcBreakpoint, isWideLayout, getFoldState } from "../common/DeviceAdapt";

@Entry
@ComponentV2
struct HomePage {
  /* 路由栈：唯一持有者，注入给需要导航的页面 */
  private pathStack: NavPathStack = new NavPathStack();
  /* 全局设备状态（断点 + 折叠状态，@Trace 驱动布局重排） */
  private deviceState: DeviceState = getDeviceState();
  /* 主窗口引用（注销窗口尺寸监听用） */
  private mainWindow?: window.Window;
  /* 折叠状态监听回调（命名引用，便于注销） */
  private foldListener: (status: display.FoldStatus) => void = (_status: display.FoldStatus) => {
    this.updateDeviceState(this.getWindowWidthVp());
  };
  /* 窗口尺寸监听回调（折叠/旋转/分屏/自由窗口触发）：size.width 为窗口物理像素宽，÷密度换算 vp */
  private windowSizeListener: (size: window.Size) => void = (size: window.Size) => {
    const density: number = display.getDefaultDisplaySync().densityPixels;
    this.updateDeviceState(size.width / density);
  };

  aboutToAppear(): void {
    /**
     * 将 ChatPage 作为路由栈首页入栈（isEntry 恒在栈底），animated:false 避免首屏闪动；
     * 首页参与 customNavContentTransition 的 from/to 转场，使双向抽屉动画能覆盖聊天页本身
     */
    this.pathStack.pushPath({ name: "ChatPage", isEntry: true }, false);
    /* 初始化断点 + 注册折叠/窗口尺寸监听（折叠屏展开↔折叠、平板旋转时实时重排布局） */
    this.updateDeviceState();
    display.on('foldStatusChange', this.foldListener);
    const context = this.getUIContext().getHostContext();
    if (context) {
      window.getLastWindow(context).then((win: window.Window) => {
        this.mainWindow = win;
        win.on('windowSizeChange', this.windowSizeListener);
        /* 主窗口就绪后：用窗口实际宽度（而非物理屏宽）重新计算断点，
           修正分屏/自由窗口下窗口宽 < 物理屏宽导致的误判 */
        this.updateDeviceState(this.getWindowWidthVp());
      });
    }
  }

  aboutToDisappear(): void {
    /* 注销监听，防止回调泄漏 */
    display.off('foldStatusChange', this.foldListener);
    if (this.mainWindow !== undefined) {
      this.mainWindow.off('windowSizeChange', this.windowSizeListener);
      this.mainWindow = undefined;
    }
  }

  /**
   * 依据窗口宽度与折叠状态刷新全局设备状态（断点 + 宽屏标志）
   * @param windowWidthVp 窗口实际宽度（vp）；未传或 <=0 时回退物理屏宽兜底
   */
  private updateDeviceState(windowWidthVp?: number): void {
    const prevWide: boolean = this.deviceState.isWide;
    const widthVp: number =
      windowWidthVp !== undefined && windowWidthVp > 0 ? windowWidthVp : this.getWindowWidthVp();
    this.deviceState.breakpoint = calcBreakpoint(widthVp);
    this.deviceState.isWide = isWideLayout(this.deviceState.breakpoint);
    /* 折叠状态（字符串常量，非折叠屏返回 unknown） */
    this.deviceState.foldStatus = getFoldState();
    /* 变宽屏（如折叠屏展开）：左栏侧边栏已常驻，栈内不应再有任何抽屉式 SideBarPage。
       边缘场景——多页面叠放时折叠展开（如 ChatPage→SideBarPage→FolderPage→SettingsPage），
       SideBarPage 可能不在栈顶，逐层残留会在右栏浮现重复侧边栏。
       故用 popToName 清到 ChatPage 栈底，彻底移除所有 SideBarPage。
       宽屏下 FolderPage/SettingsPage 本就应从 NavBar 重新进入，此处一并弹出无副作用 */
    if (this.deviceState.isWide && !prevWide) {
      const names: string[] = this.pathStack.getAllPathName();
      if (names.length > 1 && names.indexOf("SideBarPage") >= 0) {
        this.pathStack.popToName("ChatPage");
      }
    }
  }

  /** 获取窗口实际宽度（vp）：优先取主窗口 windowRect，未就绪回退物理屏宽 */
  private getWindowWidthVp(): number {
    if (this.mainWindow !== undefined) {
      try {
        const w: number = this.mainWindow.getWindowProperties().windowRect.width;
        const density: number = display.getDefaultDisplaySync().densityPixels;
        if (w > 0 && density > 0) {
          return w / density;
        }
      } catch (e) {
        /* 窗口属性读取异常 → 回退物理屏宽 */
      }
    }
    return getWindowWidthVp();
  }

  /**
   * @Entry 页面返回键拦截（关键修复）：
   * 实测证实：冷启动首次弹键盘时按返回键，事件绕过 NavDestination.onBackPressed 直接到达本回调，
   * 且此刻键盘仍处于弹出状态（onBlur / keyboardHeightChange=0 在 onBackPress 之后才到达）。
   * 若返回 false（默认返回），ChatPage 是栈底 isEntry 页无处可弹 → 系统终止应用退桌面。
   * 因此：键盘弹出时 → 消费返回(true)+主动 stopInput，仅收键盘不退出；
   * 键盘已收起 → 放行默认返回(false)，正常退出应用。
   * 注：栈上有 SideBarPage/FolderPage 等页面时，返回由 Navigation 弹栈处理，不会走到本回调。
   */
  onBackPress(): boolean {
    if (KeyboardBackHelper.consumeKeyboardBack()) {
      /* 兜底：主动收起键盘（键盘收起事件由系统在返回处理后触发，无需等待） */
      inputMethod.getController().stopInput();
      return true;
    }
    return false;
  }

  /**
   * 路由表：将路由名映射到对应页面组件
   * Navigation 的 navDestination 属性在页面入栈时调用本方法创建目标页面
   * @param name 路由名（pushPathByName 的第一个参数）
   * @param param 路由参数（pushPathByName 的第二个参数）
   */
  @Builder
  pageMap(name: string, param: object) {
    if (name === "ChatPage") {
      ChatPage()
    } else if (name === "SideBarPage") {
      SideBarPage({
        currentConversationId: (param as SideBarParams | undefined)?.currentConversationId ?? "",
      })
    } else if (name === "FolderPage") {
      /* FolderPage 的 @Param 由路由参数初始化（folderId / folderName） */
      FolderPage({
        folderId: (param as FolderParams).folderId,
        folderName: (param as FolderParams).folderName,
      })
    } else if (name === "SettingsPage") {
      SettingsPage()
    } else if (name === "ModelConfigPage") {
      ModelConfigPage()
    } else if (name === "AccountSyncPage") {
      AccountSyncPage()
    } else if (name === "ImagePreviewPage") {
      /* 图片全屏预览：路由参数注入图片列表与起始页码（ChatPage pushPathByName 传入） */
      ImagePreviewPage({
        images: (param as ImagePreviewParams).images,
        startIndex: (param as ImagePreviewParams).index,
      })
    } else if (name === "MarkdownPreviewPage") {
      /* Markdown 文件预览：路由参数注入 md 文件附件（ChatPage 气泡点击跳转） */
      MarkdownPreviewPage({
        file: (param as MarkdownPreviewParams).file,
      })
    }
  }

  build() {
    /* 原生分栏重构：单一 Navigation 动态切换 Stack/Split（替代 Row 手写双栏）。
       宽屏(Split)：NavBar=SideBarPage 左栏常驻 + NavDestination 右栏（ChatPage 栈底），自带分割线与拖拽调宽；
       窄屏(Stack)：NavBar 隐藏，ChatPage 全屏，SideBarPage 走抽屉 push（现状）。
       Navigation 组件本身不随宽窄屏重建 → 路由栈保留，ChatPage 状态不丢 */
    Navigation(this.pathStack) {
      /* 宽屏：NavBar = SideBarPage 左栏常驻；窄屏：NavBar 隐藏（被右栏 NavDestination 覆盖） */
      if (this.deviceState.isWide) {
        SideBarPage({
          embedded: true,
          hostPathStack: this.pathStack,
        })
      } else {
        Column() {}
      }
    }
    .navDestination(this.pageMap)
    .mode(this.deviceState.isWide ? NavigationMode.Split : NavigationMode.Stack)
    /* 各页面自绘标题栏，隐藏 Navigation 自带的标题栏 */
    .hideTitleBar(true)
    /* 原生分栏：分割线 + 拖拽调宽（宽屏 Split 生效；API 20 分割线样式为系统默认灰色）。
       - 左栏初始占 30%
       - 拖拽时左栏可调范围 25%~75% */
    .navBarWidth('30%')
    .navBarWidthRange(['240vp', '75%'])
    .enableDragBar(true)
    /* 自定义页面切换转场：SideBarPage 抽屉式覆盖在 ChatPage 上 */
    .customNavContentTransition(
      (from: NavContentInfo, to: NavContentInfo, operation: NavigationOperation) => {
        /**
         * 仅处理「ChatPage ↔ SideBarPage」与「ChatPage ↔ ImagePreviewPage」之间的转场：
         * - SideBarPage：抽屉式平移覆盖在 ChatPage 上
         * - ImagePreviewPage：淡入淡出遮罩覆盖在 ChatPage 上（ChatPage 保持静止，不产生默认左移）
         * 其余页面（文件夹 / 设置）返回 undefined，走系统默认转场动画
         */
        const isChatSide =
          (from.name === "ChatPage" && to.name === "SideBarPage") ||
          (from.name === "SideBarPage" && to.name === "ChatPage");
        const isPreview =
          (from.name === "ChatPage" && to.name === "ImagePreviewPage") ||
          (from.name === "ImagePreviewPage" && to.name === "ChatPage");
        if (from.index === -1 || to.index === -1 || (!isChatSide && !isPreview)) {
          return undefined;
        }
        return {
          /* 超时兜底：若动画未正常结束，系统会在超时后强制结束转场，防止页面卡死 */
          timeout: 2000,
          transition: (transitionProxy: NavigationTransitionProxy) => {
            /* 按路由栈索引取出进出场页面注册的动画回调 */
            const fromParam = NavTransitionManager.getInstance().get(from.index);
            const toParam = NavTransitionManager.getInstance().get(to.index);
            if (fromParam === undefined || toParam === undefined) {
              transitionProxy.finishTransition();
              return;
            }
            const isPush = operation === NavigationOperation.PUSH;
            /* 时长：预览（淡入 / 淡出）；侧边栏（滑入 / 滑出） */
            const transitionDuration = isPreview ? (isPush ? 300 : 100) : (isPush ? 250 : 150);
            /* 预览淡入淡出，侧边栏曲线 */
            const transitionCurve = isPreview ? (isPush ? Curve.EaseIn : Curve.Sharp) : Curve.EaseOut;
            /* 幂等收尾：确保 finishTransition 只被调用一次（onFinish 与兜底定时器可能同时触发） */
            let finished = false;
            const finish = (): void => {
              if (finished) {
                return;
              }
              finished = true;
              /* 动画结束：重置状态 + 通知系统结束自定义转场 */
              fromParam.onFinish();
              toParam.onFinish();
              transitionProxy.finishTransition();
            };
            /**
             * 兜底：若 animateTo 被系统弹窗（bindSheet 等）动画打断导致 onFinish 不触发，
             * 超时后强制收尾，避免 Navigation 卡在转场中、后续 push 失效。
             * 正常转场在 transitionDuration 内完成（finished 已置 true），此兜底不会产生副作用。
             */
            setTimeout(finish, transitionDuration + 120);
            /* 1. 同步设置进出场页面的初始位置（无动画，本帧直接生效） */
            fromParam.start(isPush, true);
            toParam.start(isPush, false);
            /* 2. animateTo 驱动页面状态变化：从初始位置动画到目标位置 */
            this.getUIContext().animateTo({
              duration: transitionDuration,
              curve: transitionCurve,
              onFinish: finish,
            }, () => {
              fromParam.finish(isPush, true);
              toParam.finish(isPush, false);
            });
          },
        };
      },
    )
    .width("100%")
    .height("100%")
  }
}
