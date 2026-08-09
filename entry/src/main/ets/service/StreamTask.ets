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

export class StreamTask {
  conversationId: string; // 归属对话 id（也是 map 的 key）
  aiMsg: Message; // AI 占位消息（流式填充目标，也是持久化对象）
  targetConv: Conversation; // 发起流时捕获的对话对象（onComplete 刷新 updated_at 用）
  streamBuffer: string = ""; // 正文增量缓冲区（未合并到 aiMsg 的待写文本）
  reasoningBuffer: string = ""; // 思考增量缓冲区
  flushTimerId: number = -1; // 节流定时器 id（-1 = 无等待中的定时器）
  isStreaming: boolean = true; // 流式进行中标记（onComplete/onError 置 false）

  constructor(conversationId: string, aiMsg: Message, targetConv: Conversation) {
    this.conversationId = conversationId;
    this.aiMsg = aiMsg;
    this.targetConv = targetConv;
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
