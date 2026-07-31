/**
 * AI 对话服务
 * 封装 OpenAI 兼容 API 的调用，支持 SSE 流式输出
 *
 * 核心流程：
 *   1. 将 Message[] 转换为 API 请求格式
 *   2. 发起 HTTP POST 请求（stream: true）
 *   3. 监听 dataReceive 事件，逐 chunk 解析 SSE 数据
 *   4. 通过回调实时通知调用方更新 UI
 */

import buffer from "@ohos.buffer";
import { http } from "@kit.NetworkKit";
import { Message } from "../model/Message";
import { AppConfig } from "../config/AppConfig";

/**
 * 流式回调接口
 * 调用方（ChatPage）实现这三个回调来驱动 UI 更新
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

// API 请求中的消息格式
interface ApiMessage {
  role: string;
  content: string;
}

// SSE 单行解析结果
interface SSEResult {
  delta: string;
  reasoningDelta: string;
  done: boolean;
}

// SSE 响应中的 delta 结构
interface SSEDelta {
  content: string;
  reasoning_content: string;
}

// SSE 响应中的 choices 元素
interface SSEChoice {
  delta: SSEDelta;
}

// SSE 完整响应结构
interface SSEResponse {
  choices: SSEChoice[];
}

export class AIService {
  // 单例实例
  private static instance: AIService;

  // SSE 解析缓冲区（处理不完整的 chunk）
  private sseBuffer: string = "";

  // 私有构造函数
  private constructor() {}

  // 获取单例实例
  static getInstance(): AIService {
    if (!AIService.instance) {
      AIService.instance = new AIService();
    }
    return AIService.instance;
  }

  /**
   * 发送流式对话请求
   *
   * @param messages 历史消息列表（包含用户和 AI 的完整对话）
   * @param callbacks 流式回调
   *
   * 调用示例：
   *   AIService.getInstance().sendMessage(messages, {
   *     onChunk: (delta) => { // 追加到最后一条 AI 消息 },
   *     onComplete: (full) => { // 标记完成 },
   *     onError: (err) => { // 显示错误 },
   *   });
   */
  sendMessage(messages: Message[], callbacks: StreamCallbacks): void {
    const config = AppConfig.getInstance().getConfig();
    this.sseBuffer = "";

    const httpRequest: http.HttpRequest = http.createHttp();

    let fullText = "";
    let fullReasoning = "";
    let isFinished = false; // 防止 onComplete/onError 重复调用

    // 安全调用回调的辅助函数
    const safeComplete = (text: string): void => {
      if (!isFinished) {
        isFinished = true;
        callbacks.onComplete(text);
      }
    };
    const safeError = (msg: string): void => {
      if (!isFinished) {
        isFinished = true;
        callbacks.onError(msg);
      }
    };
    const cleanup = (): void => {
      httpRequest.off("dataReceive");
      httpRequest.off("dataEnd");
      httpRequest.destroy();
    };

    // 1. 流式数据接收
    httpRequest.on("dataReceive", (data: ArrayBuffer) => {
      const chunk = this.arrayBufferToString(data);
      this.sseBuffer += chunk;

      const lines = this.sseBuffer.split("\n");
      this.sseBuffer = lines.pop() || "";

      for (const line of lines) {
        const result = this.parseSSELine(line);
        if (result.done) {
          safeComplete(fullText);
          return;
        }
        // 思考内容增量
        if (result.reasoningDelta.length > 0) {
          fullReasoning += result.reasoningDelta;
          callbacks.onReasoningChunk(result.reasoningDelta);
        }
        // 正文增量
        if (result.delta.length > 0) {
          fullText += result.delta;
          callbacks.onChunk(result.delta);
        }
      }
    });

    // 2. 数据接收完毕 → 在这里清理资源
    httpRequest.on("dataEnd", () => {
      if (fullText.length === 0) {
        safeError("未收到有效响应数据");
      } else {
        safeComplete(fullText);
      }
      cleanup();
    });

    // 3. 构造请求体
    const apiMessages: ApiMessage[] = messages.map((msg: Message): ApiMessage => {
      return { role: msg.role, content: msg.content };
    });
    const requestBody = JSON.stringify({
      model: config.model,
      messages: apiMessages,
      stream: true,
    });

    // 4. 发起请求
    httpRequest
      .requestInStream(config.baseUrl, {
        method: http.RequestMethod.POST,
        header: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${config.apiKey}`,
          Accept: "text/event-stream",
        },
        extraData: requestBody,
        usingProtocol: http.HttpProtocol.HTTP1_1,
        connectTimeout: 15000,
        readTimeout: 60000,
      })
      .then((responseCode: number) => {
        // 只处理 HTTP 错误码，不调用 destroy（关键修改！）
        if (responseCode >= 400) {
          safeError(`API 错误 (${responseCode})`);
          cleanup();
          return;
        }
        // 正常情况（200）：不做任何事，等待 dataReceive 和 dataEnd
      })
      .catch((error: Error) => {
        safeError(`网络请求失败: ${error.message}`);
        cleanup();
      });
  }

  /**
   * 解析单行 SSE 数据
   *
   * SSE 格式示例：
   *   data: {"choices":[{"delta":{"content":"你好"}}]}     → 提取 "你好"
   *   data: {"choices":[{"delta":{"content":""}}]}          → 空增量，跳过
   *   data: [DONE]                                          → 标记结束
   *   : comment                                             → 注释行，跳过
   *
   * @param line 单行 SSE 数据（已去除换行符）
   * @returns SSEResult 包含 delta（增量文本）和 done（是否结束）
   */
  private parseSSELine(line: string): SSEResult {
    // ArkTS 要求对象字面量必须对应已声明的 interface
    const result: SSEResult = { delta: "", reasoningDelta: "", done: false };
    const trimmed = line.trim();

    // 空行或注释行，跳过
    if (trimmed === "" || trimmed.startsWith(":")) {
      return result;
    }

    // 结束标记
    if (trimmed === "data: [DONE]") {
      result.done = true;
      return result;
    }

    // 提取 data: 后面的 JSON 内容
    if (trimmed.startsWith("data: ")) {
      const jsonStr = trimmed.substring(6); // 去掉 "data: " 前缀
      try {
        // ArkTS 不允许 any 类型，必须用 as 断言到具体 interface
        const parsed: SSEResponse = JSON.parse(jsonStr) as SSEResponse;
        // OpenAI 兼容格式：choices[0].delta.content
        const reasoning: string = parsed.choices?.[0]?.delta?.reasoning_content || "";
        const content: string = parsed.choices?.[0]?.delta?.content || "";
        if (reasoning.length > 0) {
          result.reasoningDelta = reasoning;
        }
        if (content.length > 0) {
          result.delta = content;
        }
      } catch (e) {
        // JSON 解析失败，跳过这一行（可能是心跳包或不完整数据）
      }
    }

    return result;
  }

  /**
   * ArrayBuffer 转字符串
   * SSE 数据以 UTF-8 编码传输，需要手动解码
   * 使用 buffer API（util.TextDecoder.decode 在 API 26 已废弃）
   *
   * @param bufferData HTTP 接收到的二进制数据块
   * @returns 解码后的字符串
   */
  private arrayBufferToString(bufferData: ArrayBuffer): string {
    // buffer.from() 接受 ArrayBuffer，toString("utf-8") 解码为字符串
    try {
      return buffer.from(bufferData).toString("utf-8");
    } catch (e) {
      // 解码失败时返回空串，跳过该 chunk，不影响后续流式接收
      return "";
    }
  }
}
