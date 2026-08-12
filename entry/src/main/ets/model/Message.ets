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
  @Trace generationStatus: "complete" | "partial" = "complete"; // 生成状态（持久化）：complete 完整 / partial 未完成
  //（进程终止/网络中断/暂停/生成中均为 partial；重启加载对话时据此恢复「继续生成」按钮）
  @Trace isThinking: boolean = false; // 是否正在思考中（用于 UI 状态）
  @Trace isSearching: boolean = false; // 是否正在联网搜索（用于 UI 状态）
  @Trace searchFailed: boolean = false; // 联网搜索是否失败（已降级普通模式）
  @Trace isStreaming: boolean = false; // 是否正在流式输出（UI 据此保持渲染，Markdown 组件由 content 增量自动重绘）
  @Trace isPaused: boolean = false; // 是否已暂停生成（暂停态时气泡操作栏右上角显示「继续生成」；仅内存状态，不持久化）
  @Trace thinkingStartTime: number = 0; // 思考开始时间戳
  @Trace thinkingDuration: number = 0; // 思考耗时（秒），思考完成时赋值
  @Trace createdAt: number = 0; // 发送时间戳（毫秒）

  // ===== 对话分支字段（v2.0 新增）=====
  // 分支链模型：
  //   每条消息记录 parentId = 被回复的消息 id（根用户消息为空串）
  //   branchGroupId = parentId，即"该位置的分支组锚点"（同组消息互为变体兄弟）
  //   variantIndex = 变体序号（0 起；同一分支组内递增）
  //   isActive = 是否位于当前激活分支链上（列表仅渲染激活链）
  // 例如：U1(root) → A1(v0)/A1'(v1) 为变体；U2(parentId=A1) → U2'(parentId=A1) 亦为变体
  @Trace parentId: string = ""; // 父消息 ID（被回复的消息，根消息为 ""）
  @Trace branchGroupId: string = ""; // 分支组 ID（= parentId，同组消息互为变体）
  @Trace variantIndex: number = 0; // 变体序号（0 起，驱动 "< 当前 / 总数 >"）
  @Trace isActive: boolean = true; // 是否当前激活分支（仅激活链显示在列表中）

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
