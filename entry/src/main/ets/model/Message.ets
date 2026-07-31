// 消息角色类型
export type MessageRole = "user" | "assistant" | "system";

/**
 * 单条消息数据模型
 * 一条消息属于一个对话
 */

@Observed
export class Message {
  id: string = ""; // UUID 主键
  conversationId: string = ""; // 所属对话 ID（外键）
  role: MessageRole = "user"; // 消息角色：用户 or AI
  content: string = ""; // 消息正文（AI 消息可能包含 Markdown）
  reasoning: string = ""; // AI 思考内容（仅 assistant 有值）
  isThinking: boolean = false; // 是否正在思考中（用于 UI 状态）
  isSearching: boolean = false; // 是否正在联网搜索（用于 UI 状态）
  searchFailed: boolean = false; // 联网搜索是否失败（已降级普通模式）
  thinkingStartTime: number = 0; // 思考开始时间戳
  thinkingDuration: number = 0; // 思考耗时（秒），思考完成时赋值
  createdAt: number = 0; // 发送时间戳（毫秒）

  constructor(conversationId: string, role: MessageRole, content: string) {
    this.id = this.generateId();
    this.conversationId = conversationId;
    this.role = role;
    this.content = content;
    this.createdAt = Date.now();
  }
  // 生成唯一随机 UUID
  private generateId(): string {
    return `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }

  // 是否为用户消息
  isUser(): boolean {
    return this.role === "user";
  }
}
