/**
 * LLM（大语言模型）服务接口抽象
 * 业务层只依赖本接口与工厂；接入新供应商只需新增实现类并在 LLMProviderFactory 注册。
 * Responses API 迁移要点：
 * - 联网搜索改为服务端 web_search 工具，sendMessage 新增 webSearch 参数
 * - StreamCallbacks 新增 onWebSearchStart / onWebSearchEnd，搜索状态由服务端流事件驱动
 */

import { Message } from "../../model/Message";
import { LLMError } from "../LLMError";
import { ThinkingEffort } from "../../config/ModelPresets";

/**
 * 流式回调接口
 * 调用方（ChatViewModel）实现这些回调来驱动 UI 更新
 */
export interface StreamCallbacks {
  /* 每收到一段思考内容增量时触发（逐字/逐词输出效果） */
  onReasoningChunk: (deltaReasoning: string) => void;
  /* 每收到一段增量文本时触发（逐字/逐词输出效果） */
  onChunk: (deltaText: string) => void;
  /* 全部文本接收完成时触发 */
  onComplete: (fullText: string) => void;
  /**
   * 达到输出上限被服务端截断时触发（response.incomplete）：
   * 内容完整保留，但生成未走完，调用方应进入"暂停"态允许用户「继续生成」
   */
  onIncomplete: (fullText: string, error: LLMError) => void;
  /* 发生错误时触发（error 为供应商归一化后的统一错误对象） */
  onError: (error: LLMError) => void;
  /**
   * 流被异常中断时触发（网络出问题、连接被掐断等，未收到正常结束事件）：
   * 调用方应进入"暂停"态，保留已接收内容并允许用户「继续生成」
   */
  onInterrupted: (reason: LLMError) => void;
  /* 服务端开始执行联网搜索（web_search 工具由服务端执行，UI 显示"正在搜索…"） */
  onWebSearchStart: () => void;
  /**
   * 服务端搜索词已确定（来自 web_search_call item 的 action.queries，已过滤 ws_call_id 追踪尾巴）
   * @param queries 搜索词列表（可能多个）
   */
  onSearchQuery: (queries: string[]) => void;
  /**
   * 模型正在浏览的网页地址已确定（来自 web_search_call item 的 action.url，open_page 动作）
   * @param url 被浏览页面的完整 URL
   */
  onSearchBrowse: (url: string) => void;
  /* 服务端联网搜索完成（模型开始基于搜索结果回答） */
  onWebSearchEnd: () => void;
}

/**
 * 流式请求中止句柄
 * sendMessage 发起请求后返回本句柄，调用方在需要「暂停生成」时调用 abort()
 * 中止后底层 HTTP 连接被销毁，且 Provider 不再触发任何回调（onComplete/onError/onInterrupted）
 */
export interface AbortHandle {
  /* 中止当前流式请求（幂等：重复调用无副作用） */
  abort(): void;
}

/**
 * LLM 服务统一接口
 * 各供应商 Provider 实现本接口，向 ChatViewModel 暴露一致的流式对话能力
 */
export interface LLMProvider {
  /* 渠道是否已配置（未配置时 sendMessage 内部会通过 onError 提示用户） */
  isConfigured(): boolean;
  /**
   * 发送流式对话请求
   * @param messages 历史消息列表（包含用户和 AI 的完整对话）
   * @param callbacks 流式回调
   * @param thinkingEffort 思考强度（reasoning.effort：none 关闭 / low / high / max）
   * @param webSearch 是否开启联网搜索（服务端 web_search 工具）
   * @returns 中止句柄：调用方可在生成过程中调用 abort() 暂停（保留已接收内容）
   */
  sendMessage(
    messages: Message[],
    callbacks: StreamCallbacks,
    thinkingEffort: ThinkingEffort,
    webSearch: boolean,
  ): AbortHandle;
}
