/**
 * 图片全屏预览页（独立路由页）
 * 以独立路由页承载图片预览，而非 ChatPage 内的覆盖层：
 * - 预览页在路由栈上 → 系统手势返回 / 物理返回键都走弹栈回 ChatPage（根因修复：
 *   ChatPage 是栈底，页面内覆盖层时手势返回被系统抢先退桌面）
 * - 视觉：纯深色不透明遮罩（Navigation 对栈下 ChatPage 不渲染，故自身不透明避免露出空白）
 *   + Navigation.customNavContentTransition 淡入淡出（opacity 0→1 / 1→0），ChatPage 保持静止
 */
import { common } from "@kit.AbilityKit";
import { display, window } from "@kit.ArkUI";
import { ImageAttachment } from "../model/Message";
import { NavTransitionManager } from "../common/NavTransitionManager";
import { SafeAreaHelper } from "../common/Utils";

/* 缩放上限（双指/双击放大到 4x 封顶，避免过度放大失真） */
const MAX_ZOOM: number = 4.5;
/* 缩放下限（1x 下可继续缩小到 0.5x，露出背景；松手回弹回 1x，类系统相册） */
const MIN_ZOOM: number = 0.5;
/* 双击放大倍数（1x ↔ 2x 切换） */
const DOUBLE_TAP_ZOOM: number = 2;
/* 垂直拖动关闭阈值（vp）：scale=1 时单指上下拖动超过该值，松手即关闭预览（类系统相册） */
const CLOSE_DRAG_THRESHOLD: number = 100;

/**
 * 单页图片的缩放/平移状态（@ObservedV2/@Trace：手势过程中原地更新，触发该页 Image 重绘）
 * baseScale/baseX/baseY 为手势过程临时值（Pinch/Pan 的起始快照，非响应式）
 */
@ObservedV2
class ZoomImageState {
  @Trace scale: number = 1;
  @Trace offsetX: number = 0;
  @Trace offsetY: number = 0;
  baseScale: number = 1;
  baseX: number = 0;
  baseY: number = 0;
}

/* 预览页路由参数（ChatPage pushPathByName 注入） */
export interface PreviewParams {
  images: ImageAttachment[];
  index: number;
}

@ComponentV2
export struct PreviewPage {
  /* 路由参数：图片列表（引用 ChatPage 传入的数组） */
  @Param images: ImageAttachment[] = [];
  /* 路由参数：打开时的起始页码 */
  @Param startIndex: number = 0;
  /* 路由栈（NavDestination.onReady 获取）：关闭预览 = pop 弹栈回 ChatPage */
  private pathStack: NavPathStack = new NavPathStack();
  /* 本页在路由栈中的索引（注册/注销转场回调用，onReady 时确定） */
  private transitionIndex: number = -1;
  /* 遮罩透明度（Navigation.customNavContentTransition 驱动：0=透明 1=不透明，实现淡入淡出覆盖效果） */
  @Local maskOpacity: number = 1;
  /* 当前页码（Swiper 同步，页码指示用） */
  @Local currentIndex: number = 0;
  /* 状态栏高度（vp，AppStorage 注入）：返回键定位在状态栏下方 */
  @Local statusBarHeightVp: number = 0;
  /* 每张图的独立缩放/平移状态（与 images 一一对应） */
  @Local zoomStates: ZoomImageState[] = [];
  /* 屏幕宽高（vp）：平移边界 = (scale-1)/2 * 屏宽/屏高 */
  @Local screenW: number = 0;
  @Local screenH: number = 0;
  /* UI 控件（返回键/页码）显隐：单击图片切换 → 沉浸全屏浏览（类系统相册） */
  @Local uiVisible: boolean = true;
  /* 主窗口引用（单击隐藏/显示系统状态栏用，aboutToAppear 异步获取） */
  private mainWindow?: window.Window;

  aboutToAppear(): void {
    /* 读取状态栏高度：返回键避开系统状态栏（一次性读取） */
    this.statusBarHeightVp = SafeAreaHelper.getStatusBarHeight();
    /* build 前定位起始页：避免 Swiper 首帧按 0 渲染再跳转造成闪跳 */
    this.currentIndex = this.startIndex;
    /* 每张图一个独立缩放状态（build 前就绪，Swiper 首帧可直接引用） */
    this.zoomStates = [];
    for (let i = 0; i < this.images.length; i++) {
      this.zoomStates.push(new ZoomImageState());
    }
    /* 屏幕尺寸（px → vp）：平移边界计算用 */
    const d = display.getDefaultDisplaySync();
    this.screenW = px2vp(d.width);
    this.screenH = px2vp(d.height);
    /* 异步获取主窗口：单击隐藏/恢复系统状态栏用 */
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (ctx) {
      window.getLastWindow(ctx).then((win: window.Window) => {
        this.mainWindow = win;
      });
    }
  }

  aboutToDisappear(): void {
    /* 页面销毁：注销转场回调，防止泄漏 */
    if (this.transitionIndex >= 0) {
      NavTransitionManager.getInstance().unregister(this.transitionIndex);
      this.transitionIndex = -1;
    }
    /* 离开预览页：恢复系统状态栏显示 */
    if (this.mainWindow) {
      this.mainWindow.setSpecificSystemBarEnabled('status', true);
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        /* 纯深色遮罩背景（不透明：Navigation 对栈下 ChatPage 不渲染，需自身不透明避免露出空白）
           单击不退出预览（退出仅通过左上返回键 / 系统返回） */
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#FF121212')

        /* Swiper 图片浏览：Base64 data URL 直接渲染，Contain 完整展示
           每页独立缩放/平移（@Trace 驱动 scale/translate）；放大后禁翻页 + 启用平移 */
        Swiper() {
          ForEach(
            this.images,
            (img: ImageAttachment, idx: number) => {
              Image('data:' + img.mimeType + ';base64,' + img.data)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
                /* 共享元素转场：与消息气泡缩略图同 id（preview_+img.id），打开/关闭时图片放大/缩小衔接
                   Navigation 环境下用 geometryTransition（sharedTransition 仅 router 路由生效） */
                .geometryTransition('preview_' + img.id)
                .scale({ x: this.zoomStates[idx].scale, y: this.zoomStates[idx].scale })
                .translate({ x: this.zoomStates[idx].offsetX, y: this.zoomStates[idx].offsetY })
                .gesture(
                  GestureGroup(GestureMode.Exclusive,
                    /* 双指缩放：以两指中点为锚点（pinchCenter），结束松手回弹吸附（类系统相册） */
                    PinchGesture()
                      .onActionStart(() => {
                        const st = this.zoomStates[idx];
                        st.baseScale = st.scale;
                        st.baseX = st.offsetX;
                        st.baseY = st.offsetY;
                      })
                      .onActionUpdate((event: PinchGestureEvent) => {
                        /* 每次从手势起始快照重新计算：scale 跟随手指比例（1x 下可缩到 MIN_ZOOM），锚点跟随捏合中心 */
                        this.zoomAt(idx, event.pinchCenterX, event.pinchCenterY,
                          this.clamp(this.zoomStates[idx].baseScale * event.scale, MIN_ZOOM, MAX_ZOOM));
                      })
                      .onActionEnd(() => {
                        this.settleZoom(idx);
                      }),
                    /* 双击：1x ↔ 2.5x，以点击位置为锚点放大（SDK 无 DoubleTapGesture，用 count=2 实现） */
                    TapGesture({ count: 2 })
                      .onAction((event: TapGestureEvent) => {
                        const st = this.zoomStates[idx];
                        if (st.scale > 1) {
                          this.resetZoom(idx);
                        } else {
                          const loc = event.tapLocation;
                          this.setZoomAt(idx, DOUBLE_TAP_ZOOM,
                            loc ? loc.x : this.screenW / 2,
                            loc ? loc.y : this.screenH / 2);
                        }
                      }),
                    /* 单击：切换 UI（返回键/页码/状态栏）显隐 → 沉浸全屏浏览（不参与缩放/复位，还原靠双击） */
                    TapGesture({ count: 1 })
                      .onAction(() => {
                        this.toggleUi();
                      }),
                  )
                )
            },
            (img: ImageAttachment) => img.id,
          )
        }
        .index(this.currentIndex)
        .onChange((idx: number) => {
          this.currentIndex = idx;
        })
        /* 当前页放大时禁翻页（缩放态拖动归平移手势，避免与 Swiper 滑动冲突） */
        .disableSwipe(this.currentIndex >= 0 && this.currentIndex < this.zoomStates.length &&
          this.zoomStates[this.currentIndex].scale > 1)
        .width('100%')
        .height('100%')
        .indicator(false)
        .backgroundColor(Color.Transparent)

        /* 左上角返回键：点击弹栈回 ChatPage */
        Button() {
          SymbolGlyph($r("sys.symbol.chevron_left"))
            .fontSize(32)
            .fontColor([$r('app.color.font_on_primary')])
        }
        .width(40)
        .height(40)
        .type(ButtonType.Circle)
        .backgroundColor('#FF212121')
        .padding({
          left: $r('app.float.space_xs'),
          right: 6,
          top: $r('app.float.space_xs'),
          bottom: $r('app.float.space_xs'),
        })
        .position({ x: 12, y: this.statusBarHeightVp + 12 })
        /* 沉浸全屏：uiVisible=false 时隐藏返回键 */
        .opacity(this.uiVisible ? 1 : 0)
        .onClick(() => {
          this.closePreview();
        })

        /* 页码指示：当前页 / 总页数 */
        Text(`${this.currentIndex + 1} / ${this.images.length}`)
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.font_on_primary'))
          .padding({
            left: $r('app.float.space_sm'),
            right: $r('app.float.space_sm'),
            top: $r('app.float.space_xxs'),
            bottom: $r('app.float.space_xxs'),
          })
          .width('100%')
          .textAlign(TextAlign.Center)
          .position({ y: '90%' })
          /* 沉浸全屏：uiVisible=false 时隐藏页码 */
          .opacity(this.uiVisible ? 1 : 0)
      }
      /* 单指手势（挂在根 Stack：放大态 Swiper disableSwipe 后由它接管平移；
         原尺寸时 Swiper 子组件优先翻页，垂直拖动则交给它执行关闭手势） */
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.All })
          .onActionStart(() => {
            const st = this.zoomStates[this.currentIndex];
            if (st) {
              st.baseX = st.offsetX;
              st.baseY = st.offsetY;
            }
          })
          .onActionUpdate((event: PanGestureEvent) => {
            const st = this.zoomStates[this.currentIndex];
            if (!st) {
              return;
            }
            if (st.scale > 1) {
              /* 放大态：平移图片（含边界限制） */
              this.panZoom(this.currentIndex, event.offsetX, event.offsetY);
            } else {
              /* 原尺寸：垂直拖动让图片跟随手指（关闭手势），水平拖动留给 Swiper 翻页 */
              st.offsetY = st.baseY + event.offsetY;
            }
          })
          .onActionEnd(() => {
            const st = this.zoomStates[this.currentIndex];
            if (!st) {
              return;
            }
            if (st.scale > 1) {
              /* 放大态：松手回弹到合法范围 */
              this.settleZoom(this.currentIndex);
            } else {
              /* 原尺寸/缩小态：垂直拖动超过阈值松手关闭，否则回弹（scale 回 1、offset 归零） */
              if (Math.abs(st.offsetY) > CLOSE_DRAG_THRESHOLD) {
                this.closePreview();
              } else {
                this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                  st.scale = 1;
                  st.offsetX = 0;
                  st.offsetY = 0;
                  /* 回到 1x：恢复 UI 显示 */
                  this.syncUiWithZoom(st);
                });
              }
            }
          }),
      )
      /* 遮罩淡入淡出：opacity 整体驱动（0 时下层 ChatPage 完全可见） */
      .opacity(this.maskOpacity)
      /* 全屏遮罩：向系统安全区（状态栏 / 导航栏）扩展，覆盖整个屏幕 */
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
    }
    .backgroundColor('#FF121212')
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      /* 注册转场回调：opacity 淡入淡出（配合 Navigation.customNavContentTransition，ChatPage 保持静止） */
      this.transitionIndex = this.pathStack.getAllPathName().length - 1;
      NavTransitionManager.getInstance().register(this.transitionIndex, {
        start: (isPush: boolean, isExit: boolean) => {
          /* 初始：作为 to（打开预览）先透明；作为 from（关闭预览）留在原位 */
          this.maskOpacity = isExit ? 1 : 0;
        },
        finish: (isPush: boolean, isExit: boolean) => {
          /* 目标：作为 to 淡入到 1；作为 from 淡出到 0 */
          this.maskOpacity = isExit ? 0 : 1;
        },
        onFinish: () => {
          /* 动画结束重置，供下次转场使用 */
          this.maskOpacity = 1;
        },
      });
    })
    .onBackPressed(() => {
      /* 预览页在栈上：返回键 = 弹栈回 ChatPage（系统手势返回同样走此弹栈，不会退桌面） */
      this.closePreview();
      return true;
    })
  }

  /* 关闭预览：恢复状态栏 + animateTo 包 pop，为 geometryTransition 反向（全屏 → 缩略图）提供动画上下文 */
  private closePreview(): void {
    if (this.mainWindow) {
      this.mainWindow.setSpecificSystemBarEnabled('status', true);
    }
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.pathStack.pop();
    });
  }

  /* 数值裁剪到 [min, max] */
  private clamp(v: number, min: number, max: number): number {
    return Math.min(Math.max(v, min), max);
  }

  /**
   * 锚点缩放（实时，捏合用）：以手势中心 (cx, cy) 为锚点，让该点处图片内容保持原位。
   * 推导：图片坐标 img = (P - center - offset)/scale 不变 → offset' = (P-center)(1-r) + offset*r，r = 目标缩放/起始缩放
   */
  private zoomAt(idx: number, cx: number, cy: number, target: number): void {
    const st = this.zoomStates[idx];
    if (!st) {
      return;
    }
    const ratio = target / st.baseScale;
    const centerX = this.screenW / 2;
    const centerY = this.screenH / 2;
    st.offsetX = (cx - centerX) * (1 - ratio) + st.baseX * ratio;
    st.offsetY = (cy - centerY) * (1 - ratio) + st.baseY * ratio;
    st.scale = target;
    /* 缩放中：非 1x 自动隐藏 UI（返回键/页码/状态栏），回到 1x 恢复 */
    this.syncUiWithZoom(st);
  }

  /* 锚点缩放（动画版，双击放大用）：以点击位置 (cx, cy) 为锚点平滑放大到 target */
  private setZoomAt(idx: number, target: number, cx: number, cy: number): void {
    const st = this.zoomStates[idx];
    if (!st) {
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      const ratio = target / st.scale;
      const centerX = this.screenW / 2;
      const centerY = this.screenH / 2;
      st.offsetX = (cx - centerX) * (1 - ratio) + st.offsetX * ratio;
      st.offsetY = (cy - centerY) * (1 - ratio) + st.offsetY * ratio;
      st.scale = target;
      /* 放大后限制偏移不越界：锚点在边缘时避免图片被推出可视区露出空白 */
      const maxX = (st.scale - 1) * this.screenW / 2;
      const maxY = (st.scale - 1) * this.screenH / 2;
      st.offsetX = this.clamp(st.offsetX, -maxX, maxX);
      st.offsetY = this.clamp(st.offsetY, -maxY, maxY);
      /* 放大后：非 1x 隐藏 UI */
      this.syncUiWithZoom(st);
    });
  }

  /* 复位到原尺寸（双击/单击还原） */
  private resetZoom(idx: number): void {
    const st = this.zoomStates[idx];
    if (!st) {
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      st.scale = 1;
      st.offsetX = 0;
      st.offsetY = 0;
      /* 回到 1x：恢复 UI 显示 */
      this.syncUiWithZoom(st);
    });
  }

  /* 松手回弹：scale 低于 1 吸附回原尺寸；放大态 offset 越界回弹到合法范围（类系统相册弹性） */
  private settleZoom(idx: number): void {
    const st = this.zoomStates[idx];
    if (!st) {
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      if (st.scale < 1) {
        st.scale = 1;
        st.offsetX = 0;
        st.offsetY = 0;
      } else {
        const maxX = (st.scale - 1) * this.screenW / 2;
        const maxY = (st.scale - 1) * this.screenH / 2;
        st.offsetX = this.clamp(st.offsetX, -maxX, maxX);
        st.offsetY = this.clamp(st.offsetY, -maxY, maxY);
      }
      /* 回弹后同步 UI：回到 1x 恢复显示，仍放大/缩小则保持隐藏 */
      this.syncUiWithZoom(st);
    });
  }

  /* 切换沉浸全屏：隐藏/显示返回键、页码 + 系统状态栏（单击图片触发） */
  private toggleUi(): void {
    this.uiVisible = !this.uiVisible;
    if (this.mainWindow) {
      this.mainWindow.setSpecificSystemBarEnabled('status', this.uiVisible);
    }
  }

  /**
   * 缩放状态同步 UI：scale 偏离 1x（放大或缩小）时自动隐藏返回键/页码/状态栏，
   * 回到 1x 时自动恢复显示。在各缩放入口（捏合/双击/回弹）改动 scale 后调用。
   */
  private syncUiWithZoom(st: ZoomImageState): void {
    const shouldShow = Math.abs(st.scale - 1) <= 0.001;
    if (this.uiVisible !== shouldShow) {
      this.uiVisible = shouldShow;
      if (this.mainWindow) {
        this.mainWindow.setSpecificSystemBarEnabled('status', this.uiVisible);
      }
    }
  }

  /* 平移边界限制：放大倍率越高可平移范围越大（不超过 (scale-1)/2 * 屏尺寸） */
  private panZoom(idx: number, dx: number, dy: number): void {
    const st = this.zoomStates[idx];
    if (!st) {
      return;
    }
    const maxX = (st.scale - 1) * this.screenW / 2;
    const maxY = (st.scale - 1) * this.screenH / 2;
    st.offsetX = this.clamp(st.baseX + dx, -maxX, maxX);
    st.offsetY = this.clamp(st.baseY + dy, -maxY, maxY);
  }
}
