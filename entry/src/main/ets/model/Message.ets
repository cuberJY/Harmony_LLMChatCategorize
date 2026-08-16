import { generateId } from "../common/Utils";
import { LLMError } from "../service/LLMError";

/* 消息角色类型 */
export type MessageRole = "user" | "assistant" | "system";

/* 思考过程中浏览过的网页（服务端 web_search 的 open_page 动作；结构化记录供「xx个网页」面板展示） */
export interface WebPage {
  url: string; // 网页完整 URL（点击可打开）
  domain: string; // 提取的域名（用于列表展示）
}

/* 内容搜索命中消息：某对话命中一条消息的摘要（供搜索结果分组内展示 + 跳转定位）
   一个对话可能命中多条消息，按时间升序逐条返回 */
export interface ContentSnippet {
  conversationId: string; // 所属对话 ID
  messageId: string; // 命中的消息 ID（用于打开对话后滚动定位到该消息）
  snippet: string; // 命中片段（关键字居中截取的纯文本摘要，单行展示）
  createdAt: number; // 消息发送时间戳（组内按此时间展示）
}

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
  @Trace searchedWebs: WebPage[] = []; // 思考过程中浏览过的网页（open_page 动作；@Trace 驱动「xx个网页」按钮数量实时刷新）
  @Trace generationStatus: "complete" | "partial" = "complete"; // 生成状态（持久化）：complete 完整 / partial 未完成
  /* （进程终止/网络中断/暂停/生成中均为 partial；重启加载对话时据此恢复「继续生成」按钮） */
  @Trace error: LLMError | undefined = undefined; // 生成终止时的统一错误信息（结构化存储，独立于正文；进程重启后从库恢复展示）
  @Trace isThinking: boolean = false; // 是否正在思考中（用于 UI 状态）
  @Trace isSearching: boolean = false; // 是否正在联网搜索（用于 UI 状态）
  @Trace searchFailed: boolean = false; // 联网搜索是否失败（已降级普通模式）
  @Trace isStreaming: boolean = false; // 是否正在流式输出（UI 据此保持渲染，Markdown 组件由 content 增量自动重绘）
  @Trace isPaused: boolean = false; // 是否已暂停生成（暂停态时气泡操作栏右上角显示「继续生成」；仅内存状态，不持久化）
  /**
   * 思考块自动折叠请求信号（仅内存状态，不持久化）：
   * 流式结束（正常完成 / 暂停 / 异常中断）时由 ViewModel 自增，驱动气泡延迟折叠思考过程。
   * 用"版本号自增"而非布尔值：同一消息可能多次请求折叠（生成→折叠→重新生成→再次折叠），
   * 布尔值第二次置 true 不会触发 @Monitor；自增保证每次请求都被气泡感知
   */
  @Trace foldVersion: number = 0;
  @Trace thinkingStartTime: number = 0; // 思考开始时间戳
  @Trace thinkingDuration: number = 0; // 思考耗时（秒），思考完成时赋值
  @Trace createdAt: number = 0; // 发送时间戳（毫秒）

  /**
   * ===== 对话分支字段（v2.0 新增）=====
   * 分支链模型：
   *   每条消息记录 parentId = 被回复的消息 id（根用户消息为空串）
   *   branchGroupId = parentId，即"该位置的分支组锚点"（同组消息互为变体兄弟）
   *   variantIndex = 变体序号（0 起；同一分支组内递增）
   *   isActive = 是否位于当前激活分支链上（列表仅渲染激活链）
   * 例如：U1(root) → A1(v0)/A1'(v1) 为变体；U2(parentId=A1) → U2'(parentId=A1) 亦为变体
   */
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

  isUser(): boolean {
    return this.role === "user";
  }
}
