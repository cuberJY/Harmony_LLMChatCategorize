/**
 * DeepSeek（Responses API）LLM Provider
 * 由 OpenAI 兼容 Chat Completions 迁移至 Responses API
 *
 * 与旧版（Chat Completions）的核心差异：
 *   1. 请求地址：https://api.deepseek.com/responses（由 ModelPresets 预设推导）
 *   2. 请求体：messages → input + instructions；thinking/reasoning_effort → reasoning.effort
 *   3. 联网搜索：tools: [{ type: "web_search" }] 由服务端执行，本地不再调用搜索 API
 *   4. 流式事件：choices[0].delta → 语义化事件（response.output_text.delta 等），
 *      无 data: [DONE]，以 response.completed / response.incomplete / response.failed 收尾
 *
 * 核心流程：
 *   1. 将 Message[] 转换为 Responses API 的 input item 列表
 *   2. 发起 HTTP POST 请求（stream: true）
 *   3. 监听 dataReceive 事件，逐 chunk 解析 SSE 事件（event: 行 + data: 行）
 *   4. 通过回调实时通知调用方更新 UI（正文/思考/搜索状态）
 */

import buffer from "@ohos.buffer";
import { http } from "@kit.NetworkKit";
import { Message } from "../../model/Message";
import { AppConfig } from "../../config/AppConfig";
import { LLMProvider, StreamCallbacks } from "./LLMProvider";

// API 请求中的消息格式（Responses API 的 input item：message 类型）
interface ApiMessage {
  role: string;
  content: string;
}

// 工具（服务端 web_search）
interface ResponsesTool {
  type: string; // "web_search"
}

// 思考模式配置（Responses API 通过 reasoning.effort 控制强度）
interface ReasoningConfig {
  effort: string; // "high"（深度思考）| "low"（轻量思考）
}

// Responses API 请求体结构
interface ResponsesRequestBody {
  model: string;
  input: ApiMessage[];
  stream: boolean;
  reasoning?: ReasoningConfig;
  tools?: ResponsesTool[];
}

// SSE data 行 JSON（包含事件类型与增量字段）
interface ResponsesEventData {
  type?: string; // 事件类型（data JSON 自带时使用）
  event?: string; // 事件类型（部分实现用 event 字段）
  delta?: string; // 正文/思考增量
  error?: ErrorDetail; // response.failed 时的错误详情
}

// 错误详情
interface ErrorDetail {
  message?: string;
}

// SSE 单行解析结果
interface SSEResult {
  kind: "none" | "chunk" | "reasoning" | "searchStart" | "searchEnd" | "done" | "failed";
  text: string; // 增量文本（chunk / reasoning 时有效）
  done: boolean; // 是否流结束（response.completed / incomplete）
  failed: boolean; // 是否失败（response.failed）
  errorMsg: string; // 失败原因
}

export class DeepSeekProvider implements LLMProvider {
  // 单例实例
  private static instance: DeepSeekProvider;

  // 私有构造函数
  private constructor() {}

  // 获取单例实例
  static getInstance(): DeepSeekProvider {
    if (!DeepSeekProvider.instance) {
      DeepSeekProvider.instance = new DeepSeekProvider();
    }
    return DeepSeekProvider.instance;
  }

  // 渠道是否已配置（未配置时 sendMessage 会通过 onError 提示用户）
  isConfigured(): boolean {
    return AppConfig.getInstance().isConfigured();
  }

  /**
   * 发送流式对话请求（Responses API）
   *
   * @param messages 历史消息列表（包含用户和 AI 的完整对话）
   * @param callbacks 流式回调（含服务端搜索状态回调）
   * @param deepThinking 是否开启深度思考（reasoning.effort: high / low）
   * @param webSearch 是否开启联网搜索（服务端 web_search 工具）
   *
   * 调用示例：
   *   DeepSeekProvider.getInstance().sendMessage(messages, {
   *     onChunk: (delta) => { // 追加到最后一条 AI 消息 },
   *     onWebSearchStart: () => { // 显示"正在搜索…" },
   *     onWebSearchEnd: () => { // 恢复思考状态 },
   *     onComplete: (full) => { // 标记完成 },
   *     onError: (err) => { // 显示错误 },
   *   }, true, true);
   */
  sendMessage(
    messages: Message[],
    callbacks: StreamCallbacks,
    deepThinking: boolean,
    webSearch: boolean,
  ): void {
    // 未配置时提前拦截，提示用户前往设置
    if (!this.isConfigured()) {
      callbacks.onError("尚未配置 API，请先前往「设置」填写 API Key");
      return;
    }
    const preset = AppConfig.getInstance().getPreset();
    // 关键：SSE 缓冲改为本次调用私有的局部变量（此前是单例共享实例字段）
    // 并发场景下多个对话同时流式，若共享缓冲会被互相污染，导致解析错乱
    let sseBuffer: string = "";
    // 当前 pending 的 SSE event: 行事件名（与 data: 行成对出现）
    let pendingEventName: string = "";

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
      sseBuffer += chunk;

      const lines = sseBuffer.split("\n");
      sseBuffer = lines.pop() || "";

      for (const line of lines) {
        const trimmed = line.trim();
        // SSE 事件头：event: response.output_text.delta（记录类型，供紧邻的 data: 行使用）
        if (trimmed.startsWith("event:")) {
          pendingEventName = trimmed.substring(6).trim();
          continue;
        }
        // 空行 / 注释行，跳过
        if (trimmed === "" || trimmed.startsWith(":")) {
          continue;
        }
        // 结束标记（Responses API 无 [DONE]，此处仅作兼容兜底）
        if (trimmed === "data: [DONE]") {
          safeComplete(fullText);
          return;
        }
        // 数据行：data: {json}（兼容 data: 后有无空格两种写法）
        let jsonStr: string = "";
        if (trimmed.startsWith("data: ")) {
          jsonStr = trimmed.substring(6);
        } else if (trimmed.startsWith("data:")) {
          jsonStr = trimmed.substring(5).trim();
        }
        if (jsonStr.length > 0) {
          const result = this.parseEventData(pendingEventName, jsonStr);
          pendingEventName = ""; // 该事件已消费，复位（后续 data 行需自带 event: 或 JSON type）

          // 服务端搜索状态（不中断流程）
          if (result.kind === "searchStart") {
            callbacks.onWebSearchStart();
            continue;
          }
          if (result.kind === "searchEnd") {
            callbacks.onWebSearchEnd();
            continue;
          }
          // 流结束 / 失败
          if (result.done) {
            safeComplete(fullText);
            return;
          }
          if (result.failed) {
            safeError(result.errorMsg.length > 0 ? `API 错误: ${result.errorMsg}` : "API 请求失败");
            return;
          }
          // 思考内容增量
          if (result.kind === "reasoning" && result.text.length > 0) {
            fullReasoning += result.text;
            callbacks.onReasoningChunk(result.text);
          }
          // 正文增量
          if (result.kind === "chunk" && result.text.length > 0) {
            fullText += result.text;
            callbacks.onChunk(result.text);
          }
        }
      }
    });

    // 2. 数据接收完毕 → 在这里清理资源
    httpRequest.on("dataEnd", () => {
      if (fullText.length === 0 && fullReasoning.length === 0) {
        safeError("未收到有效响应数据");
      } else {
        safeComplete(fullText);
      }
      cleanup();
    });

    // 3. 构造请求体（Responses API 格式）
    const apiMessages: ApiMessage[] = messages.map((msg: Message): ApiMessage => {
      return { role: msg.role, content: msg.content };
    });

    const requestBodyObj: ResponsesRequestBody = {
      model: AppConfig.getInstance().getModel(), // 设置页选择的模型（未选择时回退供应商默认）
      input: apiMessages,
      stream: true,
    };

    // 思考模式（Responses API：reasoning.effort 控制强度）
    // - 开启深度思考：high（深度推理）
    // - 关闭深度思考：low（Responses API 无"完全关闭"开关，low 最接近轻量思考）
    if (preset.supportsReasoning) {
      requestBodyObj.reasoning = { effort: deepThinking ? "high" : "low" };
    }

    // 服务端联网搜索：开启且供应商支持时携带 web_search 工具，
    // 搜索结果由服务端自动注入供模型回答（本地不再调用搜索 API）
    if (webSearch && preset.supportsWebSearch) {
      requestBodyObj.tools = [{ type: "web_search" }];
    }

    const requestBody = JSON.stringify(requestBodyObj);

    // 4. 发起请求
    httpRequest
      .requestInStream(preset.endpoint, {
        method: http.RequestMethod.POST,
        header: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${AppConfig.getInstance().getApiKey()}`,
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
   * 解析单个 SSE 事件（event: 行事件名 + data: 行 JSON）
   *
   * Responses API 流式事件示例（兼容两种形态）：
   *   形态一（event: + data: 成对）：
   *     event: response.output_text.delta
   *     data: {"type":"response.output_text.delta","sequence_number":1,"delta":"你好"}
   *   形态二（data JSON 自带 type 字段，无 event: 行）：
   *     data: {"type":"response.output_text.delta","delta":"你好"}
   *
   * 事件类型优先级：SSE event: 行 > data JSON 的 type 字段 > event 字段
   *
   * @param eventName SSE event: 行携带的事件名（可能为空串）
   * @param jsonStr data: 行携带的 JSON 字符串
   * @returns SSEResult 解析结果
   */
  private parseEventData(eventName: string, jsonStr: string): SSEResult {
    // ArkTS 要求对象字面量必须对应已声明的 interface
    const result: SSEResult = { kind: "none", text: "", done: false, failed: false, errorMsg: "" };
    let parsed: ResponsesEventData;
    try {
      parsed = JSON.parse(jsonStr) as ResponsesEventData;
    } catch (e) {
      // JSON 解析失败，跳过这一行（可能是心跳包或不完整数据）
      return result;
    }
    // 事件类型解析（优先级：event: 行 > JSON type > JSON event）
    const jsonType: string =
      parsed.type !== undefined ? parsed.type : (parsed.event !== undefined ? parsed.event : "");
    const type: string = eventName.length > 0 ? eventName : jsonType;

    if (type === "response.output_text.delta") {
      // 正文增量
      result.kind = "chunk";
      result.text = parsed.delta || "";
    } else if (type === "response.reasoning_text.delta") {
      // 思维链增量
      result.kind = "reasoning";
      result.text = parsed.delta || "";
    } else if (
      type === "response.web_search_call.in_progress" ||
      type === "response.web_search_call.searching"
    ) {
      // 服务端搜索开始
      result.kind = "searchStart";
    } else if (type === "response.web_search_call.completed") {
      // 服务端搜索完成
      result.kind = "searchEnd";
    } else if (type === "response.completed" || type === "response.incomplete") {
      // 正常完成 / 截断完成 → 均视为流结束
      result.kind = "done";
      result.done = true;
    } else if (type === "response.failed") {
      // 失败
      result.kind = "failed";
      result.failed = true;
      result.errorMsg = parsed.error !== undefined && parsed.error.message !== undefined
        ? parsed.error.message
        : "";
    }
    // 其余事件（response.created / in_progress / output_item.* / content_part.* 等）忽略
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
