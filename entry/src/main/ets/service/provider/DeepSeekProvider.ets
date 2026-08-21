/**
 * DeepSeek（Responses API）LLM Provider（由 OpenAI 兼容 Chat Completions 迁移而来）
 * 与旧版核心差异：请求地址 /responses；请求体 input + reasoning.effort；
 * 联网搜索由服务端 web_search 工具执行；流式事件为语义化事件（response.output_text.delta 等），
 * 无 data: [DONE]，以 response.completed / incomplete / failed 收尾。
 */

import buffer from "@ohos.buffer";
import { http } from "@kit.NetworkKit";
import { Message } from "../../model/Message";
import { AppConfig } from "../../config/AppConfig";
import { ThinkingEffort, isVisionModel } from "../../config/ModelPresets";
import { AbortHandle, LLMProvider, StreamCallbacks } from "./LLMProvider";
import { LLMError, ErrorCode, buildError } from "../LLMError";

/* 供应商标识（错误对象 provider 字段 / 日志定位） */
const PROVIDER_NAME = "deepseek";

/**
 * 流不活跃看门狗阈值（ms）：距上次收到数据超过该阈值视为连接假死，
 * 按网络中断收尾进入暂停态；取值小于 readTimeout(180s)，保证看门狗先触发
 */
const STREAM_IDLE_TIMEOUT_MS: number = 90 * 1000;

/* 消息正文内容块（Responses API：图片仅支持 input_image 块，且只能出现在 user 消息） */
interface ApiInputTextBlock {
  type: "input_text"; // 文本块
  text: string;
}
interface ApiInputImageBlock {
  type: "input_image"; // 图片块（Base64 data URL 或外部 http(s) URL）
  image_url: string;
  detail?: string; // low / high / original / auto（不传默认 auto ≈ original）
}
type ApiContentBlock = ApiInputTextBlock | ApiInputImageBlock;

/* API 请求中的消息格式（Responses API 的 input item：message 类型） */
interface ApiMessage {
  role: string;
  content: string | ApiContentBlock[];
}

/* 工具（服务端 web_search） */
interface ResponsesTool {
  type: string; // "web_search" | "web_search_2025_08_26"（两者等效，服务端执行）
}

/**
 * tool_choice 配置（预留，暂不启用）
 * DeepSeek 支持 "none" / "auto"（当前默认）/ "required" / {"type": "web_search"} 四种形态，
 * 本接口对应对象形态；字符串形态启用时按需扩展为 string | ToolChoiceConfig
 */
interface ToolChoiceConfig {
  type: string; // "web_search" | "web_search_2025_08_26" | "function"
}

/* 思考模式配置（Responses API 通过 reasoning.effort 控制强度：none 关闭 / low 轻量 / high 深度 / max 极限） */
interface ReasoningConfig {
  effort: ThinkingEffort;
}

/* Responses API 请求体结构 */
interface ResponsesRequestBody {
  model: string;
  input: ApiMessage[];
  stream: boolean;
  reasoning?: ReasoningConfig;
  tools?: ResponsesTool[];
  /* —— 预留字段（当前不启用，启用说明见请求体构造处）—— */
  instructions?: string; // 作为第一条 system 消息注入（input 与 instructions 至少传一个）
  tool_choice?: ToolChoiceConfig; // 显式指定工具选择策略（默认 auto，不传）
}

/* SSE data 行 JSON（包含事件类型与增量字段） */
interface ResponsesEventData {
  type?: string; // 事件类型（data JSON 自带时使用）
  event?: string; // 事件类型（部分实现用 event 字段）
  delta?: string; // 正文/思考增量
  item?: SearchCallItem; // output_item.done 时的完整 item（web_search_call 的 action 在此）
  error?: ErrorDetail; // response.failed 时的错误详情
}

/* output_item.done 的 item（仅关注 web_search_call；message/function_call 等忽略） */
interface SearchCallItem {
  type?: string; // "web_search_call"
  status?: string; // "completed"
  action?: SearchCallAction; // 搜索/浏览动作详情
}

/* web_search_call 的 action（实测：searching/completed 事件 action=null，只有 output_item.done 才带） */
interface SearchCallAction {
  type?: string; // "search"（仅搜索词） | "open_page"（含浏览 URL）
  queries?: string[]; // 形态1：搜索词列表（混入 "ws_call_id=xxx" 追踪尾巴，需过滤）
  url?: string; // 形态2：模型主动打开的页面 URL（可能带 #ws_call_id= 尾巴）
}

/* 错误详情（DeepSeek Responses API：error.code 可能是字符串或数字） */
interface ErrorDetail {
  code?: string | number;
  message?: string;
}

/* 非流式标题生成响应：output 数组中的 message item 含 content[].text（output_text） */
interface TitleResponseContent {
  type?: string; // "output_text"
  text?: string;
}
interface TitleResponseItem {
  type?: string; // "message"
  content?: TitleResponseContent[];
}
interface TitleResponse {
  output?: TitleResponseItem[];
  /* 请求错误（余额不足/鉴权失败等）带 error 对象；成功时显式为 null，判断时必须排除 null */
  error?: ErrorDetail | null;
}

/**
 * 标题生成指令（system 级，注入标题生成请求）
 * 约束：极短、概括、无符号，直接输出标题本身（避免模型输出解释文字污染标题）
 */
const TITLE_INSTRUCTION: string =
  "你是对话标题生成助手。请根据用户提供的对话内容，为这段对话生成一个短标题。" +
  "要求：不要出现markdown格式，不超过15个字符，尽量控制在4-10字，简短精炼。" +
  "直接输出标题本身，不要任何解释或前缀。";

/**
 * 联网搜索输出约束指令（system 级，仅在开启联网搜索时注入）
 * 约束：DeepSeek 联网搜索时容易把"搜索过程描述"（如"我来搜索一下""根据搜索结果显示"）
 * 直接输出为正文，导致用户看到"只有过程、没有答案"就 response.completed。
 * 本指令要求模型只输出最终答案，过程文字不进正文。
 */
const WEB_SEARCH_INSTRUCTION: string =
  "直接输出最终答案，不要在回答中描述搜索过程" +
  "（例如：'我来搜索一下'、'根据搜索结果显示'、'搜索到以下信息'等过程性文字）。";

/* SSE 单行解析结果 */
interface SSEResult {
  kind: "none" | "chunk" | "reasoning" | "searchStart" | "searchEnd" | "searchQuery" | "searchBrowse"
    | "done" | "incomplete" | "failed";
  text: string; // 增量文本（chunk / reasoning 时有效）
  searchQueries: string[]; // 搜索词列表（kind=searchQuery 时有效，已过滤 ws_call_id 尾巴）
  searchUrl: string; // 被浏览页面的 URL（kind=searchBrowse 时有效）
  done: boolean; // 是否流结束（response.completed / incomplete）
  failed: boolean; // 是否失败（response.failed）
  errorCode: string; // 供应商错误码（response.failed 的 error.code）
  errorMsg: string; // 供应商错误信息（response.failed 的 error.message）
}

/**
 * 中止句柄实现
 * ArkTS 不允许匿名对象字面量（arkts-no-untyped-obj-literals），
 * 故 sendMessage 返回的 AbortHandle 必须用显式声明的类构造
 */
class StreamAbortHandle implements AbortHandle {
  private aborted: boolean = false;
  private action: () => void; // 真正的中止动作（销毁 HTTP 请求等）

  constructor(action: () => void) {
    this.action = action;
  }

  abort(): void {
    if (this.aborted) {
      return;
    }
    this.aborted = true;
    this.action();
  }
}

export class DeepSeekProvider implements LLMProvider {
  private static instance: DeepSeekProvider;

  private constructor() {}

  static getInstance(): DeepSeekProvider {
    if (!DeepSeekProvider.instance) {
      DeepSeekProvider.instance = new DeepSeekProvider();
    }
    return DeepSeekProvider.instance;
  }

  /* 渠道是否已配置（未配置时 sendMessage 会通过 onError 提示用户） */
  isConfigured(): boolean {
    return AppConfig.getInstance().isConfigured();
  }

  /**
   * 对话标题自动生成（非流式 Responses API 请求）
   * 区别于 sendMessage 的流式：这里用 http.request 一次性取回结果，token 开销极小。
   * 实现要点：
   *   - instructions 作为 system 级指令注入（限定长度/格式，只输出标题本身）
   *   - 解析 output[].content[].text（output_text）
   *   - 未配置 / 网络失败 / 解析失败一律返回空串，绝不抛异常（调用方回退截断占位标题）
   * @param messages 首轮问答上下文（用户提问 + AI 回复）
   * @returns 生成的标题；失败时为空串
   */
  async generateTitle(messages: Message[]): Promise<string> {
    /* 未配置时直接返回空串（调用方保留占位标题，不打扰用户） */
    if (!this.isConfigured()) {
      return "";
    }
    const preset = AppConfig.getInstance().getPreset();
    const apiMessages: ApiMessage[] = messages.map((msg: Message): ApiMessage => {
      return { role: msg.role, content: msg.content };
    });
    const requestBodyObj: ResponsesRequestBody = {
      model: AppConfig.getInstance().getModel(),
      input: apiMessages,
      stream: false,
      instructions: TITLE_INSTRUCTION, // 标题生成指令（输入与指令同时提供，模型据此输出标题）
      reasoning: { effort: "none" }, // 标题生成无需思考：关闭思考模式，加快返回、避免长推理导致超时
    };
    const requestBody = JSON.stringify(requestBodyObj);

    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(preset.endpoint, {
        method: http.RequestMethod.POST,
        header: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${AppConfig.getInstance().getApiKey()}`,
        },
        extraData: requestBody,
        connectTimeout: 10 * 1000, // 标题生成应轻快，超时短一些
        readTimeout: 30 * 1000,
      });
      if (response.responseCode >= 400) {
        return ""; // HTTP 错误（余额不足/鉴权失败等）→ 回退占位
      }
      return this.parseTitleResponse(response.result as string);
    } catch (e) {
      return ""; // 网络异常 → 回退占位
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 解析非流式 Responses API 响应，提取 output_text 标题
   * 响应结构：output[].type="message" → content[].type="output_text" → text
   * @param jsonStr 响应体 JSON 字符串
   * @returns 提取的标题文本；解析失败/为空时返回空串
   */
  private parseTitleResponse(jsonStr: string): string {
    if (jsonStr.length === 0) {
      return "";
    }
    try {
      const parsed = JSON.parse(jsonStr) as TitleResponse;
      /* 成功响应时 error 字段为 null（非 undefined），须排除 null 后再判为请求失败 */
      if (parsed.error !== undefined && parsed.error !== null) {
        return ""; // 响应级错误 → 回退占位
      }
      if (parsed.output === undefined) {
        return "";
      }
      for (const item of parsed.output) {
        if (item.type !== "message" || item.content === undefined) {
          continue;
        }
        for (const part of item.content) {
          if (part.type === "output_text" && part.text !== undefined && part.text.trim().length > 0) {
            return part.text.trim();
          }
        }
      }
    } catch (e) {
      /* JSON 解析失败 → 回退占位 */
    }
    return "";
  }

  /**
   * 构造单条消息的 Responses API content（字符串或内容块数组）
   * 带图 user 消息 → 内容块数组：[图片块...(按发送顺序) + 文本块]；
   * 无图消息（含全部 assistant / system 消息）→ 保持纯字符串（兼容旧行为）。
   * 注意：图片仅支持出现在 user 消息（system/assistant 带图返回 400），非 user 消息的图片被忽略
   * @param msg 消息对象
   * @returns content 字段值
   */
  private buildApiContent(msg: Message): string | ApiContentBlock[] {
    if (msg.images.length === 0) {
      return msg.content;
    }
    const blocks: ApiContentBlock[] = [];
    if (msg.role === "user") {
      for (const img of msg.images) {
        /* data URL 内联图片：格式由 data: 前缀中的 MIME 决定（服务端按内容判断，非文件名） */
        blocks.push({
          type: "input_image",
          image_url: `data:${img.mimeType};base64,${img.data}`,
          detail: "auto", // 自动选择细节级别（当前等价 original）
        });
      }
    }
    /* 文本块：正文非空才追加（纯发图无文字时不带空文本块，避免冗余）；
       若无任何图片块（非 user 消息）则必须补文本块，保证 content 非空 */
    if (msg.content.length > 0 || blocks.length === 0) {
      blocks.push({ type: "input_text", text: msg.content });
    }
    return blocks;
  }

  /**
   * 发送流式对话请求（Responses API）
   * @param messages 历史消息列表（包含用户和 AI 的完整对话）
   * @param callbacks 流式回调（含服务端搜索状态回调与网络中断回调）
   * @param thinkingEffort 思考强度（reasoning.effort：none 关闭 / low 轻量 / high 深度 / max 极限）
   * @param webSearch 是否开启联网搜索（服务端 web_search 工具）
   * @returns 中止句柄：调用方在「暂停生成」时调用 abort()，
   *   中止后销毁底层 HTTP 连接且不再触发任何回调（已接收内容由调用方自行保留）
   */
  sendMessage(
    messages: Message[],
    callbacks: StreamCallbacks,
    thinkingEffort: ThinkingEffort,
    webSearch: boolean,
  ): AbortHandle {
    /* 未配置时提前拦截，提示用户前往设置 */
    if (!this.isConfigured()) {
      callbacks.onError(buildError(
        ErrorCode.CFG_NOT_CONFIGURED, "API key not configured", undefined, PROVIDER_NAME));
      /* 请求从未真正发起，返回空操作的中止句柄（幂等安全） */
      return new StreamAbortHandle((): void => {});
    }
    /**
     * 视觉模型兜底：请求包含图片但当前模型不支持视觉（如 deepseek-v4-flash）时直接拦截。
     * 正常路径下 VM 已在发图前校验拦截，此处为防御性兜底（历史图片消息重新生成等场景）
     */
    const hasImages: boolean = messages.some((msg: Message) => msg.images.length > 0);
    if (hasImages && !isVisionModel(AppConfig.getInstance().getModel())) {
      callbacks.onError(buildError(
        ErrorCode.REQ_INVALID, "current model does not support image, please switch to vision model",
        undefined, PROVIDER_NAME));
      return new StreamAbortHandle((): void => {});
    }
    const preset = AppConfig.getInstance().getPreset();
    /**
     * 关键：SSE 缓冲为本次调用私有的局部变量（此前为单例共享字段），
     * 并发多对话流式时共享缓冲会互相污染，导致解析错乱
     */
    let sseBuffer: string = "";
    /**
     * UTF-8 跨 chunk 解码缓冲（本次调用私有）：多字节字符被 TCP 分块切断时，
     * 半截序列不能直接解码（会变 U+FFFD 乱码），需把不完整尾部字节留到下一 chunk 一起解码
     */
    let utf8Pending = buffer.alloc(0);
    /* 当前 pending 的 SSE event: 行事件名（与 data: 行成对出现） */
    let pendingEventName: string = "";

    const httpRequest: http.HttpRequest = http.createHttp();

    let fullText = "";
    let fullReasoning = "";
    let isFinished = false; // 防止 onComplete/onError/onInterrupted 重复调用
    let cleaned = false; // cleanup 幂等标记（abort / dataEnd / catch / 兜底定时器 多路径可能先后触发）
    let watchdogTimerId: number = -1; // 流不活跃看门狗定时器（-1 = 未挂起）
    let gotTerminalEvent = false; // 是否收到过正常结束事件（response.completed/incomplete/failed/[DONE]）
    /* HTTP 错误处理：错误响应体是 JSON（非 SSE），需等 dataEnd 收齐后解析 error.code/message 归一化上报 */
    let httpErrorStatus = 0; // 响应码 >= 400 时记录（>0 表示处于 HTTP 错误态）
    let errorBody = ""; // HTTP 错误响应体累积缓冲

    /* 安全调用回调的辅助函数（统一错误对象，幂等防重） */
    const safeComplete = (text: string): void => {
      if (!isFinished) {
        isFinished = true;
        callbacks.onComplete(text);
      }
    };
    /* 达到输出上限被服务端截断（response.incomplete）：内容完整保留，走"暂停"态供用户「继续生成」 */
    const safeIncomplete = (text: string): void => {
      if (!isFinished) {
        isFinished = true;
        callbacks.onIncomplete(
          text,
          buildError(ErrorCode.OUT_TRUNCATED, "output truncated by max_output_tokens", undefined, PROVIDER_NAME));
      }
    };
    const safeError = (err: LLMError): void => {
      if (!isFinished) {
        isFinished = true;
        callbacks.onError(err);
      }
    };
    /* 网络异常中断（未收到正常结束事件）→ 通知调用方进入"暂停"态，允许继续生成 */
    const safeInterrupted = (reason: LLMError): void => {
      if (!isFinished) {
        isFinished = true;
        callbacks.onInterrupted(reason);
      }
    };
    const cleanup = (): void => {
      if (cleaned) {
        return; // 幂等：避免对已销毁请求二次 destroy 抛异常
      }
      cleaned = true;
      if (watchdogTimerId !== -1) {
        clearTimeout(watchdogTimerId);
        watchdogTimerId = -1;
      }
      httpRequest.off("dataReceive");
      httpRequest.off("dataEnd");
      try {
        httpRequest.destroy();
      } catch (e) {
        /* destroy 失败可忽略：请求已结束 */
      }
    };

    /* 流不活跃看门狗：每次收到数据复位；超时视为连接假死，按网络中断收尾（进入暂停态） */
    const armWatchdog = (): void => {
      if (watchdogTimerId !== -1) {
        clearTimeout(watchdogTimerId);
      }
      watchdogTimerId = setTimeout(() => {
        watchdogTimerId = -1;
        if (!isFinished) {
          safeInterrupted(
            buildError(ErrorCode.NET_DISCONNECTED, "stream idle too long", undefined, PROVIDER_NAME));
          cleanup();
        }
      }, STREAM_IDLE_TIMEOUT_MS);
    };

    /* 1. 流式数据接收 */
    httpRequest.on("dataReceive", (data: ArrayBuffer) => {
      if (isFinished) {
        return; // 修复：终态/中止后不再处理迟到事件（闭合"abort 后零回调"契约）
      }
      /**
       * 追加式 UTF-8 解码：上一 chunk 遗留的不完整多字节尾部与新 chunk 拼接，
       * 只解码完整序列部分，剩余不完整尾部字节留待下一次（修复中文跨 chunk 乱码）
       */
      const rawChunk = buffer.from(data);
      const combined = utf8Pending.length > 0 ? buffer.concat([utf8Pending, rawChunk]) : rawChunk;
      let cut = combined.length;
      let back = 1;
      let i = cut - 1;
      while (i >= 0 && back <= 3) {
        const b: number = combined.readUInt8(i); // Buffer 无索引签名，用 readUInt8 读取单字节
        if (b < 0x80) {
          break; // ASCII 结尾：序列完整
        }
        if ((b & 0xC0) === 0xC0) {
          /* 找到多字节序列起始字节：按前缀判断所需长度 */
          const need = b < 0xE0 ? 2 : (b < 0xF0 ? 3 : 4);
          if (cut - i < need) {
            cut = i; // 不完整序列：整体留到下一 chunk
          }
          break;
        }
        i--;
        back++;
      }
      utf8Pending = combined.subarray(cut);
      const chunk = combined.subarray(0, cut).toString("utf-8");
      armWatchdog(); // 收到数据 → 复位不活跃看门狗
      /* HTTP 错误响应：原始 body 是 JSON（非 SSE），只累积不解析，留待 dataEnd 归一化上报 */
      if (httpErrorStatus > 0) {
        errorBody += chunk;
        return;
      }
      sseBuffer += chunk;

      const lines = sseBuffer.split("\n");
      sseBuffer = lines.pop() || "";

      for (const line of lines) {
        const trimmed = line.trim();
        /* SSE 事件头：event: response.output_text.delta（记录类型，供紧邻的 data: 行使用） */
        if (trimmed.startsWith("event:")) {
          pendingEventName = trimmed.substring(6).trim();
          continue;
        }
        /* 空行 / 注释行，跳过 */
        if (trimmed === "" || trimmed.startsWith(":")) {
          continue;
        }
        /* 结束标记（Responses API 无 [DONE]，此处仅作兼容兜底） */
        if (trimmed === "data: [DONE]") {
          gotTerminalEvent = true;
          safeComplete(fullText);
          cleanup(); // 修复：终态即清理，不依赖 dataEnd（服务端可能保持连接）
          return;
        }
        /* 数据行：data: {json}（兼容 data: 后有无空格两种写法） */
        let jsonStr: string = "";
        if (trimmed.startsWith("data: ")) {
          jsonStr = trimmed.substring(6);
        } else if (trimmed.startsWith("data:")) {
          jsonStr = trimmed.substring(5).trim();
        }
        if (jsonStr.length > 0) {
          const result = this.parseEventData(pendingEventName, jsonStr);
          pendingEventName = ""; // 该事件已消费，复位（后续 data 行需自带 event: 或 JSON type）

          /* 服务端搜索状态（不中断流程） */
          if (result.kind === "searchStart") {
            callbacks.onWebSearchStart();
            continue;
          }
          if (result.kind === "searchEnd") {
            callbacks.onWebSearchEnd();
            continue;
          }
          /* 搜索词已确定（output_item.done 的 search 动作）→ 供 UI 展示"正在搜索：xxx" */
          if (result.kind === "searchQuery") {
            callbacks.onSearchQuery(result.searchQueries);
            continue;
          }
          /* 模型正在浏览页面（output_item.done 的 open_page 动作）→ 供 UI 展示"正在浏览 xxx" */
          if (result.kind === "searchBrowse") {
            callbacks.onSearchBrowse(result.searchUrl);
            continue;
          }
          /* 流结束（正常完成 / 输出截断 / 空回复） */
          if (result.done) {
            gotTerminalEvent = true;
            if (result.kind === "incomplete") {
              safeIncomplete(fullText); // 截断：内容保留，由调用方进入"暂停"态可续写
            } else if (fullText.length === 0) {
              /**
               * completed 但无正文（常见于联网搜索后模型空回复）：
               * 语义上"未走完"→ 按可继续生成处理（进入暂停态，保留思考内容），不当作成功收尾
               */
              safeInterrupted(buildError(ErrorCode.EMPTY_ANSWER, "model completed with empty output", undefined, PROVIDER_NAME));
            } else {
              safeComplete(fullText);
            }
            cleanup(); // 修复：终态即清理，不依赖 dataEnd
            return;
          }
          if (result.failed) {
            gotTerminalEvent = true;
            safeError(this.mapResponseFailed(result.errorCode, result.errorMsg));
            cleanup(); // 修复：终态即清理，不依赖 dataEnd
            return;
          }
          /* 思考内容增量 */
          if (result.kind === "reasoning" && result.text.length > 0) {
            fullReasoning += result.text;
            callbacks.onReasoningChunk(result.text);
          }
          /* 正文增量 */
          if (result.kind === "chunk" && result.text.length > 0) {
            fullText += result.text;
            callbacks.onChunk(result.text);
          }
        }
      }
    });

    /* 2. 数据接收完毕 → 在这里清理资源 */
    httpRequest.on("dataEnd", () => {
      /* HTTP 错误响应：等 body 收齐后解析 error.code/message，按状态码归一化上报 */
      if (httpErrorStatus > 0) {
        safeError(this.mapHttpError(httpErrorStatus, this.extractErrorMessage(errorBody)));
        cleanup();
        return;
      }
      if (!gotTerminalEvent) {
        /**
         * 未收到正常结束事件（response.completed/incomplete/failed/[DONE]）就结束了
         * = 连接被掐断/网络异常中断（已收到的内容保留，由调用方进入"暂停"态供用户继续生成）
         */
        safeInterrupted(
          buildError(ErrorCode.NET_DISCONNECTED, "stream ended without terminal event", undefined, PROVIDER_NAME));
      } else if (fullText.length === 0 && fullReasoning.length === 0) {
        safeError(buildError(ErrorCode.EMPTY_RESPONSE, "no valid response data received", undefined, PROVIDER_NAME));
      } else {
        safeComplete(fullText);
      }
      cleanup();
    });

    /* 3. 构造请求体（Responses API 格式） */
    const apiMessages: ApiMessage[] = messages.map((msg: Message): ApiMessage => {
      return { role: msg.role, content: this.buildApiContent(msg) };
    });

    const requestBodyObj: ResponsesRequestBody = {
      model: AppConfig.getInstance().getModel(), // 设置页选择的模型（未选择时回退供应商默认）
      input: apiMessages,
      stream: true,
    };

    /**
     * 思考强度（Responses API：reasoning.effort 控制强度）
     * - none：关闭思考模式（不输出思维链）
     * - low：轻量思考
     * - high：深度思考（默认）
     * - max：极限思考
     * 供应商支持思考模式（supportsReasoning）时始终携带该字段；
     * 关闭思考（none）也显式传给服务端，等价于旧版「不开启深度思考」
     */
    if (preset.supportsReasoning) {
      requestBodyObj.reasoning = { effort: thinkingEffort };
    }

    /**
     * system 级指令注入（instructions，作为第一条 system 消息注入请求）：
     *  - 自定义系统指令：AppConfig.systemPrompt（用户可配置；空串跳过）
     *  - 联网搜索约束指令：WEB_SEARCH_INSTRUCTION（仅开启联网搜索时注入，
     *    约束模型不把"搜索过程描述"输出为正文，直接给出最终答案）
     * 两部分叠加、换行分隔；任一存在即注入（避免空 instructions 干扰模型）
     */
    const systemPrompt: string = AppConfig.getInstance().getSystemPrompt();
    const instructionParts: string[] = [];
    if (systemPrompt.trim().length > 0) {
      instructionParts.push(systemPrompt.trim());
    }
    if (webSearch && preset.supportsWebSearch) {
      instructionParts.push(WEB_SEARCH_INSTRUCTION);
    }
    if (instructionParts.length > 0) {
      requestBodyObj.instructions = instructionParts.join("\n");
    }

    /**
     * 服务端联网搜索：开启且供应商支持时携带 web_search 工具，
     * 搜索结果由服务端自动注入供模型回答（本地不再调用搜索 API）
     */
    if (webSearch && preset.supportsWebSearch) {
      requestBodyObj.tools = [{ type: "web_search" }];
    }

    /**
     * 预留字段启用说明（当前刻意不传，保持 auto 默认行为）
     *  tool_choice：需要强制模型使用搜索工具时启用（会强制搜索，可能多耗延迟与 token）
     *  requestBodyObj.tool_choice = { type: "web_search" }
     */

    const requestBody = JSON.stringify(requestBodyObj);

    /* 4. 发起请求 */
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
        connectTimeout: 20 * 1000, // 连接超时 20s
        readTimeout: 180 * 1000, // 多阶段思考/联网搜索超时 180s
      })
      .then((responseCode: number) => {
        /**
         * HTTP 错误码：不立即结束，标记错误态后等 dataEnd 收齐错误响应体，
         * 再解析 error.code/message 归一化上报（错误 body 是 JSON，非 SSE）
         */
        if (responseCode >= 400) {
          httpErrorStatus = responseCode;
          /* 兜底：若错误响应体迟迟未收完（dataEnd 未触发），8s 后按已收到内容上报，避免界面卡死 */
          setTimeout(() => {
            if (!isFinished && httpErrorStatus > 0) {
              safeError(this.mapHttpError(httpErrorStatus, this.extractErrorMessage(errorBody)));
              cleanup();
            }
          }, 8000);
          return;
        }
        /* 正常情况（200）：不做任何事，等待 dataReceive 和 dataEnd */
      })
      .catch((error: BusinessError) => {
        /**
         * 已收到部分内容后连接失败 → 视为网络异常中断（进入"暂停"态可继续生成）；
         * 尚未收到任何内容 → 请求级失败，按错误上报（区分超时 / 普通失败）
         */
        const rawMessage: string =
          error.message !== undefined && error.message.length > 0 ? error.message : JSON.stringify(error);
        if (fullText.length > 0 || fullReasoning.length > 0) {
          safeInterrupted(buildError(ErrorCode.NET_DISCONNECTED, rawMessage, undefined, PROVIDER_NAME));
        } else {
          const isTimeout: boolean = rawMessage.toLowerCase().includes("timeout");
          safeError(buildError(
            isTimeout ? ErrorCode.NET_TIMEOUT : ErrorCode.NET_REQUEST_FAILED,
            rawMessage, undefined, PROVIDER_NAME));
        }
        cleanup();
      });

    /**
     * 5. 返回中止句柄：暂停生成时调用 abort()
     * abort 置 isFinished → 后续 dataReceive/dataEnd/catch 不再触发任何回调，
     * 再销毁底层 HTTP 连接，保证"暂停"后不会收到残留事件
     */
    return new StreamAbortHandle((): void => {
      if (!isFinished) {
        isFinished = true;
        cleanup();
      }
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
    /* ArkTS 要求对象字面量必须对应已声明的 interface */
    const result: SSEResult = {
      kind: "none",
      text: "",
      searchQueries: [],
      searchUrl: "",
      done: false,
      failed: false,
      errorCode: "",
      errorMsg: "",
    };
    let parsed: ResponsesEventData;
    try {
      parsed = JSON.parse(jsonStr) as ResponsesEventData;
    } catch (e) {
      /* JSON 解析失败，跳过这一行（可能是心跳包或不完整数据） */
      return result;
    }
    /* 事件类型解析（优先级：event: 行 > JSON type > JSON event） */
    const jsonType: string =
      parsed.type !== undefined ? parsed.type : (parsed.event !== undefined ? parsed.event : "");
    const type: string = eventName.length > 0 ? eventName : jsonType;

    if (type === "response.output_text.delta") {
      /* 正文增量 */
      result.kind = "chunk";
      result.text = parsed.delta || "";
    } else if (type === "response.reasoning_text.delta") {
      /* 思维链增量 */
      result.kind = "reasoning";
      result.text = parsed.delta || "";
    } else if (
      type === "response.web_search_call.in_progress" ||
      type === "response.web_search_call.searching"
    ) {
      /* 服务端搜索开始 */
      result.kind = "searchStart";
    } else if (type === "response.web_search_call.completed") {
      /* 服务端搜索完成 */
      result.kind = "searchEnd";
    } else if (type === "response.output_item.done") {
      /* 搜索动作细节（queries / url）实测只在 output_item.done 携带，searching/completed 事件 action=null */
      if (parsed.item !== undefined && parsed.item.type === "web_search_call" && parsed.item.action !== undefined) {
        const action = parsed.item.action;
        if (action.type === "search" && action.queries !== undefined) {
          /* 形态1：search 动作 → 搜索词列表（过滤 "ws_call_id=xxx" 追踪尾巴与空白项） */
          const clean: string[] = [];
          for (const q of action.queries) {
            const t = q.trim();
            if (t.length > 0 && !t.startsWith("ws_call_id=")) {
              clean.push(t);
            }
          }
          if (clean.length > 0) {
            result.kind = "searchQuery";
            result.searchQueries = clean;
          }
        } else if (action.type === "open_page" && action.url !== undefined) {
          /* 形态2：open_page 动作 → 模型主动打开并浏览的页面 URL（去掉 #ws_call_id= 追踪尾巴） */
          const url = action.url.trim();
          if (url.length > 0) {
            result.kind = "searchBrowse";
            const tailIdx = url.indexOf("#ws_call_id=");
            result.searchUrl = tailIdx >= 0 ? url.substring(0, tailIdx) : url;
          }
        }
      }
    } else if (type === "response.completed") {
      /* 正常完成 → 流结束 */
      result.kind = "done";
      result.done = true;
    } else if (type === "response.incomplete") {
      /* 输出达到上限被服务端截断：同样终止流，但语义是"未走完"（供调用方进入暂停态续写） */
      result.kind = "incomplete";
      result.done = true;
    } else if (type === "response.failed") {
      /* 失败：提取供应商错误码与错误信息，由调用方按统一错误码归一化上报 */
      result.kind = "failed";
      result.failed = true;
      if (parsed.error !== undefined) {
        result.errorCode = parsed.error.code !== undefined ? `${parsed.error.code}` : "";
        result.errorMsg = parsed.error.message !== undefined ? parsed.error.message : "";
      }
    }
    /* 其余事件（response.created / in_progress / output_item.* / content_part.* 等）忽略 */
    return result;
  }

  /**
   * 从 HTTP 错误响应体提取用户可读的错误信息（JSON error.message）
   * 响应体格式（DeepSeek）：{"error": {"code": ..., "message": "..."}}
   * 解析失败时截断返回原始 body（避免详情区展示超长内容）
   */
  private extractErrorMessage(body: string): string {
    if (body.length === 0) {
      return "";
    }
    try {
      const parsed = JSON.parse(body) as ResponsesEventData;
      if (parsed.error !== undefined && parsed.error.message !== undefined && parsed.error.message.length > 0) {
        return parsed.error.message;
      }
    } catch (e) {
      /* 非 JSON（网关错误页等）：走下方截断兜底 */
    }
    const trimmed = body.trim();
    return trimmed.length > 300 ? `${trimmed.substring(0, 300)}…` : trimmed;
  }

  /**
   * HTTP 状态码 → 统一错误码映射（供应商归一化核心）
   * 按 DeepSeek 官方错误码文档适配：
   *   400 格式错误 / 401 认证失败 / 402 余额不足 / 422 参数错误 / 429 限流 / 500 故障 / 503 繁忙
   * 其中 402 与 400+Insufficient Balance 都映射为「余额不足」；422 同属参数非法不可重试。
   */
  private mapHttpError(status: number, rawMessage: string): LLMError {
    switch (status) {
      case 401:
        return buildError(ErrorCode.AUTH_INVALID_KEY, rawMessage, status, PROVIDER_NAME);
      case 402:
        /* 官方错误码：402 = 账户余额不足（应提示充值，且不可重试） */
        return buildError(ErrorCode.INSUFFICIENT_BALANCE, rawMessage, status, PROVIDER_NAME);
      case 429:
        return buildError(ErrorCode.RATE_LIMITED, rawMessage, status, PROVIDER_NAME);
      case 400: {
        /**
         * 400 需结合错误信息判断（三种情形，按优先级）：
         * 1) 余额不足：部分网关以 400 + "Insufficient Balance" 返回（官方文档主用 402，但实测存在 400 形态）；
         * 2) 上下文超限（含 context/token 字样）→ 可新建对话解决；
         * 3) 其余 400 = 请求本身非法 → 不可重试（否则「继续生成」会对同一非法请求无限重试）
         */
        const lower = rawMessage.toLowerCase();
        if (lower.includes("insufficient") || lower.includes("balance") || lower.includes("quota")) {
          return buildError(ErrorCode.INSUFFICIENT_BALANCE, rawMessage, status, PROVIDER_NAME);
        }
        if (lower.includes("context") || lower.includes("token")) {
          return buildError(ErrorCode.CTX_OVERFLOW, rawMessage, status, PROVIDER_NAME);
        }
        return buildError(ErrorCode.REQ_INVALID, rawMessage, status, PROVIDER_NAME);
      }
      case 403:
        /* 403 Forbidden（权限/区域限制等）：同属不可重试 */
        return buildError(ErrorCode.REQ_INVALID, rawMessage, status, PROVIDER_NAME);
      case 422:
        /* 官方错误码：422 = 请求参数错误（同属不可重试，修复后重试） */
        return buildError(ErrorCode.REQ_INVALID, rawMessage, status, PROVIDER_NAME);
      default:
        if (status >= 500) {
          /* 500 服务器故障 / 503 服务器繁忙：服务端问题，可稍后重试 */
          return buildError(ErrorCode.SRV_ERROR, rawMessage, status, PROVIDER_NAME);
        }
        return buildError(ErrorCode.UNKNOWN, rawMessage, status, PROVIDER_NAME);
    }
  }

  /**
   * response.failed 事件 → 统一错误码映射（无 HTTP 状态码，按供应商 error.code/message 特征判断）
   * DeepSeek error.code 常见值：rate_limit_exceeded / context_length_exceeded / invalid_api_key 等
   */
  private mapResponseFailed(errorCode: string, errorMsg: string): LLMError {
    const raw = errorMsg.length > 0 ? errorMsg : errorCode;
    const code = errorCode.toLowerCase();
    const msg = errorMsg.toLowerCase();
    /* 余额不足：error.code 常见 insufficient_balance / insufficient_quota；message 含 balance/insufficient/quota */
    if (code.includes("insufficient") || code.includes("balance") || code.includes("quota")
      || msg.includes("insufficient") || msg.includes("balance") || msg.includes("quota")) {
      return buildError(ErrorCode.INSUFFICIENT_BALANCE, raw, undefined, PROVIDER_NAME);
    }
    if (code.includes("rate") || code.includes("limit")) {
      return buildError(ErrorCode.RATE_LIMITED, raw, undefined, PROVIDER_NAME);
    }
    if (code.includes("context") || code.includes("token")) {
      return buildError(ErrorCode.CTX_OVERFLOW, raw, undefined, PROVIDER_NAME);
    }
    if (code.includes("auth") || code.includes("api_key") || code.includes("invalid")) {
      return buildError(ErrorCode.AUTH_INVALID_KEY, raw, undefined, PROVIDER_NAME);
    }
    return buildError(ErrorCode.SRV_ERROR, raw, undefined, PROVIDER_NAME);
  }
}
