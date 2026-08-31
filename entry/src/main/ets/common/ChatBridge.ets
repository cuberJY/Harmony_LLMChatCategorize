/**
 * 跨页面对话桥接总线（ChatBridge）
 * 宽屏分栏模式下，左栏侧边栏以「嵌入式」渲染（非路由 NavDestination），
 * 无法再通过 pop(conv) 的 onPop 链把选中的对话回传给右栏 ChatPage。
 * 改用 AppStorageV2 全局响应式总线：
 * - SideBarPage 嵌入式选中对话 → 写 pendingSelection + 递增 selectionVersion
 * - ChatPage 用 @Monitor 监听 selectionVersion → vm.loadConversation 消费
 * - ChatPage 每次 onShown（从其他页面返回）→ 递增 sidebarRefreshVersion
 * - SideBarPage 嵌入式用 @Monitor 监听 → 刷新收藏/历史列表
 */

import { AppStorageV2 } from "@kit.ArkUI";
import { ConversationSelection } from "../model/Conversation";

@ObservedV2
export class ChatBridgeState {
  /** 待加载对话（宽屏嵌入式侧边栏选中 → ChatPage 消费）。
      非 @Trace：消费由 @Monitor('selectionVersion') 驱动，无需 UI 观察该字段 */
  pendingSelection: ConversationSelection | null = null;
  /** 待加载对话版本号：递增触发 ChatPage 消费（避免同引用对象不触发 @Trace） */
  @Trace selectionVersion: number = 0;
  /** 侧边栏数据刷新信号（ChatPage onShown 时递增 → 嵌入式侧边栏刷新列表） */
  @Trace sidebarRefreshVersion: number = 0;
  /** 当前打开对话 id（宽屏嵌入式侧边栏高亮用，ChatPage onShown 时更新） */
  @Trace currentConversationId: string = "";
}

/* 单例引用缓存（AppStorageV2.connect 幂等，重复连接返回同一实例） */
let cachedChatBridge: ChatBridgeState | undefined = undefined;

/** 获取全局对话桥接单例（页面内调用，@Trace 字段变化驱动 UI/@Monitor 刷新） */
export function getChatBridge(): ChatBridgeState {
  /* 局部变量承接，确保 ArkTS 出口类型窄化可靠（connect 返回 T | undefined，兜底 new 保证非空） */
  let s = cachedChatBridge;
  if (s === undefined) {
    s = AppStorageV2.connect(ChatBridgeState, "chatBridge", () => new ChatBridgeState());
    if (s === undefined) {
      s = new ChatBridgeState();
    }
    cachedChatBridge = s;
  }
  return s;
}
