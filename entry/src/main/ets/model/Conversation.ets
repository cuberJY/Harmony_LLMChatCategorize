/** 
* 对话数据模型
* 对应一次完整的聊天会话
*/
@Observed
export class Conversation {
  id: string = ""; // UUID
  title: string = ""; // 对话标题（取首条用户消息截断，或 AI 自动概括）
  categoryId: string = ""; // 所属分类 ID，空字符串表示未分类
  createdAt: number = 0; // 创建时间戳（毫秒）
  updatedAt: number = 0; // 最后更新时间戳（最后一条消息时间）

  constructor(title?: string) {
    this.id = this.generateId();
    if (title) this.title = title;
    this.createdAt = Date.now();
    this.updatedAt = Date.now();
  }

  // 生成唯一随机 UUID
  private generateId(): string {
    return `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }
}
