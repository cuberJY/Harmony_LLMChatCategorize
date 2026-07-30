// 消息角色类型
export type MessageRole = "user" | "assistant";

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

// 是否为 AI 消息
  isAssistant(): boolean {
    return this.role === "assistant";
  }

// 是否为用户消息
  isUser(): boolean {
    return this.role === "user";
  }
}
