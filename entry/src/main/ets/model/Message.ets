import { generateId } from "../common/Utils";

// 消息角色类型
export type MessageRole = "user" | "assistant" | "system";

/**
 * 单条消息数据模型（状态管理 V2）
 * 一条消息属于一个对话
 *
 * @ObservedV2：类级观察装饰器，配合 @Trace 实现属性级观察
 * @Trace：标记需要被 UI 观察的属性，属性变化时自动通知依赖它的组件刷新
 *（流式输出过程中 content / reasoning / isThinking 等频繁变化，由 @Trace 驱动 MessageBubble 实时重绘）
 */

@ObservedV2
export class Message {
  @Trace id: string = ""; // UUID 主键
  @Trace conversationId: string = ""; // 所属对话 ID（外键）
  @Trace role: MessageRole = "user"; // 消息角色：用户 or AI
  @Trace content: string = ""; // 消息正文（AI 消息可能包含 Markdown）
  @Trace reasoning: string = ""; // AI 思考内容（仅 assistant 有值）
  @Trace isThinking: boolean = false; // 是否正在思考中（用于 UI 状态）
  @Trace isSearching: boolean = false; // 是否正在联网搜索（用于 UI 状态）
  @Trace searchFailed: boolean = false; // 联网搜索是否失败（已降级普通模式）
  @Trace thinkingStartTime: number = 0; // 思考开始时间戳
  @Trace thinkingDuration: number = 0; // 思考耗时（秒），思考完成时赋值
  @Trace createdAt: number = 0; // 发送时间戳（毫秒）

  constructor(conversationId: string, role: MessageRole, content: string) {
    this.id = generateId();
    this.conversationId = conversationId;
    this.role = role;
    this.content = content;
    this.createdAt = Date.now();
  }

  // 是否为用户消息
  isUser(): boolean {
    return this.role === "user";
  }
}
