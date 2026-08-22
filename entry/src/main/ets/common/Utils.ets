/**
 * 通用工具模块
 * 集中管理跨页面复用的轻量公共能力：ID 生成、Toast 提示、删除二次确认弹窗、键盘返回键辅助；
 * 不依赖业务模块（模型/数据库），避免循环依赖
 */

import { promptAction, UIContext, window } from "@kit.ArkUI";
import { common } from "@kit.AbilityKit";

/**
 * 沉浸式安全区辅助器：
 * 统一提供标题栏高度（vp）读取。状态栏/导航条高度由 EntryAbility 存入 AppStorage，
 * 页面侧用 @StorageProp('statusBarHeightVp'/'navBarHeightVp') 读取后做显式 padding 避让，
 * 避免 expandSafeArea + safeAreaPadding 在固定高度组件上避让失效（内容顶到系统栏）的问题。
 */
export class SafeAreaHelper {
  /** 标题栏高度（vp）：读取 app.float.title_bar_height 资源（px→vp） */
  static getTitleBarHeight(uiContext: UIContext): number {
    const host = uiContext.getHostContext() as common.UIAbilityContext;
    const px = host.resourceManager.getNumber($r('app.float.title_bar_height').id);
    return uiContext.px2vp(px);
  }

  /** 状态栏高度（vp）：AppStorage 读取（EntryAbility 启动时注入，非响应式一次性读取） */
  static getStatusBarHeight(): number {
    return AppStorage.get<number>('statusBarHeightVp') ?? 0;
  }

  /** 导航条高度（vp）：AppStorage 读取（EntryAbility 启动时注入，非响应式一次性读取） */
  static getNavBarHeight(): number {
    return AppStorage.get<number>('navBarHeightVp') ?? 0;
  }

  /**
   * 半模态面板可用高度（vp）：窗口高度 - 状态栏高度 - 标题栏高度。
   * ChatPage / SideBarPage / FolderPage 的分享、搜索半模态面板共用，
   * 抽离三处重复的窗口/安全区计算逻辑
   */
  static getSheetHeight(uiContext: UIContext): number {
    try {
      const host = uiContext.getHostContext() as common.UIAbilityContext | undefined;
      if (host === undefined || host.windowStage === undefined) {
        return 500; // 兜底高度
      }
      /* 标题栏高度（float 资源带 'vp' 单位，getNumber 返回 px，需转回 vp） */
      const titleBarHeightPx = host.resourceManager.getNumber($r('app.float.title_bar_height').id);
      const titleBarHeight = uiContext.px2vp(titleBarHeightPx);
      const win = host.windowStage.getMainWindowSync();
      /* 窗口总高度（px） */
      const windowHeightPx = win.getWindowProperties().windowRect.height;
      /* 状态栏（顶部安全区）高度（px），非沉浸式窗口时为 0 */
      const safeTopPx = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height;
      const windowHeight = uiContext.px2vp(windowHeightPx);
      const safeTop = uiContext.px2vp(safeTopPx);
      return Math.max(200, windowHeight - safeTop - titleBarHeight);
    } catch (e) {
      return 500; // 异常兜底，保证面板可显示
    }
  }
}

/**
 * 生成唯一随机 ID（毫秒时间戳 + 随机串），统一 Conversation 与 Category 的 ID 生成逻辑
 */
export function generateId(): string {
  /* padStart 保证随机段恒为 7 位（极小随机值不再产生退化短串） */
  return `${Date.now()}_${Math.random().toString(36).substring(2, 9).padStart(7, "0")}`;
}

/**
 * 去掉常见 Markdown 标记，得到近似纯文本（复制按钮用，避免粘贴出粗体/标题等源码标记）
 */
export function stripMarkdown(md: string): string {
  return md
    .split('\n')
    .map((line: string) => line
      .replace(/^#{1,6}\s+/, '')
      .replace(/^>\s?/, '')
      .replace(/^[-*+]\s+/, '')
      .replace(/^\d+\.\s+/, '')
      .replace(/```.*$/, '')
      .replace(/\*\*(.+?)\*\*/g, '$1')
      .replace(/`([^`]+)`/g, '$1'))
    .join('\n');
}

/**
 * 统一 Toast 提示（行为与直接调用 promptAction.showToast({ message }) 一致）
 * @param message 提示文案
 * @param bottom Toast 底部与屏幕底部的距离（vp，越大越靠上）。不传则用默认值（160vp）
 */
export function showToast(message: string | Resource, bottom: number = 160): void {
  const options: promptAction.ShowToastOptions = { message: message };
  if (bottom !== undefined) {
    options.bottom = bottom;
  }
  promptAction.showToast(options);
}

/**
 * 文件大小格式化（字节 → 可读文本）
 * < 1KB 显示 B；< 1MB 显示 KB；其余显示 MB（保留 1 位小数）
 */
export function formatFileSize(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * 统一的"删除"二次确认弹窗
 * 标题 + 说明 + 取消/删除（红色），确认后执行回调
 * @param uiContext 页面 UIContext（调用处传 this.getUIContext()）
 * @param title 弹窗标题
 * @param message 删除说明文案
 * @param onConfirm 确认删除后的回调
 */
export function showDeleteConfirm(
  uiContext: UIContext,
  title: string | Resource,
  message: string | Resource,
  onConfirm: () => void,
): void {
  uiContext.showAlertDialog({
    title: title,
    message: message,
    primaryButton: {
      value: "取消",
      fontColor: $r('app.color.font_emphasize'),
      action: () => {
      },
    },
    secondaryButton: {
      value: "删除",
      fontColor: $r('app.color.text_danger'),
      action: () => {
        onConfirm();
      },
    },
  });
}

/**
 * 键盘返回键辅助器（解决「键盘弹出时按返回键被系统直接执行根页面返回」缺陷）
 *
 * 现象（经 hilog 实测证实）：
 * 冷启动首次弹键盘时按返回键，返回键绕过 NavDestination.onBackPressed（该回调不会触发），
 * 而是直接走到 @Entry HomePage.onBackPress——此时键盘仍处于弹出状态，onBlur /
 * keyboardHeightChange=0 在 onBackPress 之后才到达（实测 47.322 onBackPress → 47.323 onBlur
 * → 47.327 height=0）。若 onBackPress 返回 false（默认返回），ChatPage 是栈底 isEntry 页
 * 无处可弹 → 系统终止应用退桌面。
 *
 * 方案：维护全局「键盘当前是否弹出」标志，由 onFocus + keyboardHeightChange 双源驱动：
 * - @Entry onBackPress 中调用 consumeKeyboardBack()：键盘弹出 → 消费返回(true)+主动 stopInput，
 *   仅收键盘不退出；键盘已收起 → 返回 false，放行默认返回（正常退出应用）。
 *
 * 注意：键盘状态不能在 onBlur 时清零——失焦不一定收键盘（如点到空白处），
 * 收起以 keyboardHeightChange<=0 为权威信号。
 */
export class KeyboardBackHelper {
  /** 键盘当前是否弹出 */
  private static isKeyboardUp: boolean = false;

  /** 输入框聚焦（onFocus）时调用：聚焦必弹键盘，置 true（弥补 keyboardHeightChange>0 丢失的兜底） */
  static onInputFocus(): void {
    KeyboardBackHelper.isKeyboardUp = true;
  }

  /** 键盘弹出（keyboardHeightChange>0）时调用 */
  static onKeyboardShown(): void {
    KeyboardBackHelper.isKeyboardUp = true;
  }

  /** 键盘收起（keyboardHeightChange<=0）时调用：置 false（权威信号） */
  static onKeyboardCollapsed(): void {
    KeyboardBackHelper.isKeyboardUp = false;
  }

  /** 键盘当前是否弹出（供 ChatPage 等同步查询，避免重复维护状态） */
  static isKeyboardUpNow(): boolean {
    return KeyboardBackHelper.isKeyboardUp;
  }

  /**
   * @Entry onBackPress 中调用：键盘弹出时按返回 → 消费该返回（仅收键盘不退出）。
   * 消费后置 false，保证键盘收起后下一次返回正常退出。
   */
  static consumeKeyboardBack(): boolean {
    if (KeyboardBackHelper.isKeyboardUp) {
      KeyboardBackHelper.isKeyboardUp = false;
      return true;
    }
    return false;
  }
}
