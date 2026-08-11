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

// 引入各页面组件（Navigation 以组件形式挂载，须显式 import；不再通过路由字符串注册）
import { ChatPage } from "./ChatPage";
import { SideBarPage } from "./SideBarPage";
import { FolderPage } from "./FolderPage";
import { SettingsPage } from "./SettingsPage";
// FolderPage 路由参数（pushPathByName 的第二个参数）
import { FolderParams } from "../model/FolderParams";
// SideBarPage 路由参数
import { SideBarParams } from "../model/SideBarParams";
// 页面转场动画回调管理（配合 customNavContentTransition 驱动各页面自身的位移动画）
import { NavTransitionManager } from "../common/NavTransitionManager";

@Entry
@ComponentV2
struct HomePage {
  // 路由栈：唯一持有者，注入给需要导航的页面
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    // 将 ChatPage 作为路由栈首页入栈（isEntry：始终在栈底，不可出栈）。
    // animated:false 表示首页加载不播放转场动画，避免首屏闪动。
    // 这样首页也参与 customNavContentTransition 的 from/to 转场，
    // 使「聊天页右移 + 侧边栏左滑入」的双向抽屉动画能够覆盖聊天页本身。
    this.pathStack.pushPath({ name: "ChatPage", isEntry: true }, false);
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
      // FolderPage 的 @Param 由路由参数初始化（folderId / folderName）
      FolderPage({
        folderId: (param as FolderParams).folderId,
        folderName: (param as FolderParams).folderName,
      })
    } else if (name === "SettingsPage") {
      SettingsPage()
    }
  }

  build() {
    Navigation(this.pathStack) {
      // 首页为路由栈中的 ChatPage（aboutToAppear 中 pushPath 入栈），此处内容区留空
      Column() {}
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    // 各页面自绘标题栏，隐藏 Navigation 自带的标题栏
    .hideTitleBar(true)
    .width("100%")
    .height("100%")
    // 自定义页面切换转场：SideBarPage 抽屉式覆盖在 ChatPage 上
    .customNavContentTransition(
      (from: NavContentInfo, to: NavContentInfo, operation: NavigationOperation) => {
        // 仅处理「ChatPage ↔ SideBarPage」之间的转场；
        // 其余页面（文件夹 / 设置）返回 undefined，走系统默认转场动画
        const isChatSide =
          (from.name === "ChatPage" && to.name === "SideBarPage") ||
          (from.name === "SideBarPage" && to.name === "ChatPage");
        if (from.index === -1 || to.index === -1 || !isChatSide) {
          return undefined;
        }
        return {
          // 超时兜底：若动画未正常结束，系统会在超时后强制结束转场，防止页面卡死
          timeout: 2000,
          transition: (transitionProxy: NavigationTransitionProxy) => {
            // 按路由栈索引取出进出场页面注册的动画回调
            const fromParam = NavTransitionManager.getInstance().get(from.index);
            const toParam = NavTransitionManager.getInstance().get(to.index);
            if (fromParam === undefined || toParam === undefined) {
              transitionProxy.finishTransition();
              return;
            }
            const isPush = operation === NavigationOperation.PUSH;
            // 打开侧边栏（滑入覆盖）用较慢时长，让用户看清侧边栏内容；关闭（滑出）保持原速
            const transitionDuration = isPush ? 250 : 150;
            // 1. 同步设置进出场页面的初始位置（无动画，本帧直接生效）
            fromParam.start(isPush, true);
            toParam.start(isPush, false);
            // 2. animateTo 驱动页面状态变化：从初始位置动画到目标位置
            this.getUIContext().animateTo({
              duration: transitionDuration,
              curve: Curve.EaseOut,
              onFinish: () => {
                // 3. 动画结束：重置状态 + 通知系统结束自定义转场
                fromParam.onFinish();
                toParam.onFinish();
                transitionProxy.finishTransition();
              },
            }, () => {
              fromParam.finish(isPush, true);
              toParam.finish(isPush, false);
            });
          },
        };
      },
    )
  }
}
