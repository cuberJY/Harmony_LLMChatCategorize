/**
 * 单个进行中的流式任务（一个对话一个实例）
 *
 * 背景：并发场景下，同一时刻可能存在多个对话的流式回复（用户切到 B 对话后，
 * A 对话的流仍在后台推进）。因此不能再用 ChatViewModel 的全局缓冲/定时器，
 * 必须把"一个流"的全部状态收敛到独立对象中，互不串写。
 *
 * 归属：streamTasks: Map<conversationId, StreamTask>（ChatViewModel 持有）
 * 生命周期：handleUserSend 创建并登记 → 跨对话切换存活 → onComplete/onError 注销
 */
import { Message } from "../model/Message";
import { Conversation } from "../model/Conversation";
import { AbortHandle } from "./provider/LLMProvider";

export class StreamTask {
  conversationId: string; // 归属对话 id（也是 map 的 key）
  aiMsg: Message; // AI 占位消息（流式填充目标，也是持久化对象）
  targetConv: Conversation; // 发起流时捕获的对话对象（onComplete 刷新 updated_at 用）
  streamBuffer: string = ""; // 正文增量缓冲区（未合并到 aiMsg 的待写文本）
  reasoningBuffer: string = ""; // 思考增量缓冲区
  flushTimerId: number = -1; // 节流定时器 id（-1 = 无等待中的定时器）
  isStreaming: boolean = true; // 流式进行中标记（onComplete/onError/暂停时置 false）
  isPaused: boolean = false; // 是否已暂停（用户点暂停键或网络异常中断；暂停后可「继续生成」）
  webSearchEnabled: boolean = false; // 本次流是否请求了服务端联网搜索（onComplete 判断搜索是否发生过用）
  searchEventSeen: boolean = false; // 是否收到过服务端搜索事件（web_search_call.*）
  deepThinkingEnabled: boolean = false; // 本次流使用的深度思考开关（「继续生成」时复用，保持风格一致）
  abortHandler: AbortHandle | null = null; // 底层 HTTP 请求的中止句柄（「暂停生成」时调用 abort()）
  thinkingMs: number = 0; // 多阶段思考累计耗时（毫秒）：
  // Agent 式模型会"思考→输出部分正文→再思考/搜索→再输出"，本字段跨阶段累加，
  // 保证「已思考（用时 X 秒）」统计的是总思考时长，而非仅第一次正文前的时长

  constructor(conversationId: string, aiMsg: Message, targetConv: Conversation) {
    this.conversationId = conversationId;
    this.aiMsg = aiMsg;
    this.targetConv = targetConv;
  }

  /**
   * 进入/恢复思考阶段（收到 reasoning 增量时调用）
   * 多阶段思考下 isThinking 会反复切换：每次从"非思考"进入"思考"都重新计起始时间戳
   */
  beginThinking(): void {
    if (!this.aiMsg.isThinking) {
      this.aiMsg.isThinking = true;
      this.aiMsg.thinkingStartTime = Date.now();
    }
  }

  /**
   * 结束当前思考阶段（收到正文 / 完成 / 错误 / 中断时调用）
   * 将本阶段耗时累加到 thinkingMs 并刷新 thinkingDuration（跨阶段累计）
   */
  endThinking(): void {
    if (this.aiMsg.isThinking) {
      this.thinkingMs += Date.now() - this.aiMsg.thinkingStartTime;
      this.aiMsg.isThinking = false;
      this.aiMsg.thinkingDuration = Math.round(this.thinkingMs / 100) / 10;
    }
  }

  /**
   * 节流写入：将缓冲区的增量合并进 aiMsg
   * aiMsg 是 @ObservedV2 对象，属性变化（@Trace content/reasoning）自动驱动气泡重绘
   */
  flush(): void {
    if (this.reasoningBuffer.length > 0) {
      this.aiMsg.reasoning += this.reasoningBuffer;
      this.reasoningBuffer = "";
    }
    if (this.streamBuffer.length > 0) {
      this.aiMsg.content += this.streamBuffer;
      this.streamBuffer = "";
    }
    this.flushTimerId = -1; // 本次写入完成，允许下一次调度
  }

  /**
   * 清除节流定时器并清空缓冲区
   * 用于 onComplete / onError / 页面销毁，避免残留定时器触发过期写入
   */
  clearTimer(): void {
    if (this.flushTimerId !== -1) {
      clearTimeout(this.flushTimerId);
      this.flushTimerId = -1;
    }
    this.streamBuffer = "";
    this.reasoningBuffer = "";
  }
}
