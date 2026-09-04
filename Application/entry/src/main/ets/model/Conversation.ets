/**
 * 对话数据模型（状态管理 V2）
 * @ObservedV2 + @Trace 属性级观察：收藏状态、标题、更新时间变化时直接驱动列表项刷新
 */
import { generateId } from "../common/Utils";

@ObservedV2
export class Conversation {
  @Trace id: string = ""; // UUID
  @Trace title: string = ""; // 对话标题（取首条用户消息截断，或 AI 自动概括）
  @Trace categoryId: string = ""; // 收藏位置（文件夹）ID，空字符串 = 未放入文件夹（仅对已收藏对话有意义）
  @Trace isFavorite: boolean = false; // 是否已收藏：只有收藏的对话才参与文件夹分类
  @Trace isPinned: boolean = false; // 是否置顶
  @Trace isUserNamed: boolean = false; // 标题是否被用户手动命名（true = 不再自动生成 AI 标题）
  @Trace createdAt: number = 0; // 创建时间戳（毫秒）
  @Trace updatedAt: number = 0; // 最后更新时间戳（最后一条消息时间）

  constructor(title?: string) {
    this.id = generateId();
    if (title) this.title = title;
    this.createdAt = Date.now();
    this.updatedAt = Date.now();
  }
}

/**
 * 对话选中结果（搜索面板回传）：打开对话的同时定位到命中的那条消息
 * 侧边栏搜索面板选中结果时 pop 此对象；ChatPage 的 onPop 据此区分
 * 老路径（pop(Conversation)，仅打开对话）与新路径（pop(ConversationSelection)，打开并定位）
 */
export interface ConversationSelection {
  conv: Conversation; // 选中的对话
  focusMessageId: string; // 定位的消息 ID（标题命中/无定位目标时为空串，回退正常打开）
}
