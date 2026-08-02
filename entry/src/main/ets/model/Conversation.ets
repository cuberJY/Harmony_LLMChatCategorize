/** 
* 对话数据模型
* 对应一次完整的聊天会话
*/
@Observed
export class Conversation {
  id: string = ""; // UUID
  title: string = ""; // 对话标题（取首条用户消息截断，或 AI 自动概括）
  categoryId: string = ""; // 收藏位置（文件夹）ID，空字符串 = 未放入文件夹（仅对已收藏对话有意义）
  isFavorite: boolean = false; // 是否已收藏：只有收藏的对话才参与文件夹分类
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
