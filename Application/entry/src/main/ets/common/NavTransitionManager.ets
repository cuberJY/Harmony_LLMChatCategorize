/**
 * 页面转场动画回调管理器
 * 配合 Navigation.customNavContentTransition 使用：页面 onReady 时按路由栈索引注册
 * start / finish / onFinish 回调，实现页面级自定义转场动画
 * 回调参数：isPush = push/pop；isExit = 本页面是退出方（from）还是进入方（to）
 */

export interface NavTransitionCallback {
  start: (isPush: boolean, isExit: boolean) => void;
  finish: (isPush: boolean, isExit: boolean) => void;
  onFinish: () => void;
}

export class NavTransitionManager {
  private static instance: NavTransitionManager = new NavTransitionManager();
  private callbackMap: Map<number, NavTransitionCallback> = new Map<number, NavTransitionCallback>();

  static getInstance(): NavTransitionManager {
    return NavTransitionManager.instance;
  }

  /* 注册某路由栈索引页面的转场回调 */
  register(index: number, callback: NavTransitionCallback): void {
    this.callbackMap.set(index, callback);
  }

  /* 移除某路由栈索引页面的转场回调（页面销毁时调用） */
  unregister(index: number): void {
    this.callbackMap.delete(index);
  }

  /* 获取某路由栈索引页面的转场回调（可能不存在，调用方需判空） */
  get(index: number): NavTransitionCallback | undefined {
    return this.callbackMap.get(index);
  }
}
