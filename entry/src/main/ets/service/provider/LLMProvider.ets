/**
 * LLM（大语言模型）服务接口抽象（阶段五：服务层接口抽象）
 *
 * 设计意图：业务层（ChatViewModel）只依赖本接口与工厂，不直接依赖具体实现。
 * 未来接入其他模型供应商（如 Qwen / Moonshot / 本地 Ollama 等）时，
 * 只需新增一个实现 LLMProvider 的 Provider 类，并在 LLMProviderFactory 中注册，
 * 业务代码无需任何改动。
 */

import { Message } from "../../model/Message";

/**
 * 流式回调接口
 * 调用方（ChatViewModel）实现这四个回调来驱动 UI 更新
 */
export interface StreamCallbacks {
  // 每收到一段思考内容增量时触发（逐字/逐词输出效果）
  onReasoningChunk: (deltaReasoning: string) => void;
  // 每收到一段增量文本时触发（逐字/逐词输出效果）
  onChunk: (deltaText: string) => void;
  // 全部文本接收完成时触发
  onComplete: (fullText: string) => void;
  // 发生错误时触发
  onError: (errorMessage: string) => void;
}

/**
 * LLM 服务统一接口
 * 各供应商 Provider 实现本接口，向 ChatViewModel 暴露一致的流式对话能力
 */
export interface LLMProvider {
  // 渠道是否已配置（未配置时 sendMessage 内部会通过 onError 提示用户）
  isConfigured(): boolean;
  /**
   * 发送流式对话请求
   * @param messages 历史消息列表（包含用户和 AI 的完整对话）
   * @param callbacks 流式回调
   * @param deepThinking 是否开启深度思考
   */
  sendMessage(messages: Message[], callbacks: StreamCallbacks, deepThinking?: boolean): void;
}
