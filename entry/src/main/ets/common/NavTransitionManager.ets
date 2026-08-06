/**
 * 页面转场动画回调管理器
 * 配合 Navigation.customNavContentTransition 使用，实现页面级自定义转场动画。
 *
 * 设计（参考官方 FAQ「Navigation如何实现从0至1渐变出现的跳转动画」）：
 * - 需要动画的页面在 onReady 时按「路由栈索引」注册 start / finish / onFinish 三个回调
 * - start：   转场开始时同步设置页面初始状态（如初始位移），无动画
 * - finish：  HomePage 在 animateTo 闭包内调用，驱动状态从初始值动画到目标值
 * - onFinish：动画结束后重置状态，供下次转场使用
 *
 * 回调参数 isPush / isExit 语义：
 * - isPush：当前操作是否为 push（true=push，false=pop）
 * - isExit：本页面是退出方（from，true）还是进入方（to，false）
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

  // 注册某路由栈索引页面的转场回调
  register(index: number, callback: NavTransitionCallback): void {
    this.callbackMap.set(index, callback);
  }

  // 移除某路由栈索引页面的转场回调（页面销毁时调用）
  unregister(index: number): void {
    this.callbackMap.delete(index);
  }

  // 获取某路由栈索引页面的转场回调（可能不存在，调用方需判空）
  get(index: number): NavTransitionCallback | undefined {
    return this.callbackMap.get(index);
  }
}
