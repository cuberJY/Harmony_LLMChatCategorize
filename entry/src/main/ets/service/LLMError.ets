/**
 * 统一错误模型（服务层错误归一化）
 *
 * 设计意图：
 *  - 各 LLM 供应商（DeepSeek / Qwen / Moonshot / Ollama …）的错误格式各不相同
 *    （HTTP 状态码 + 各自的 error 结构），但业务层（ChatViewModel）与 UI 只依赖
 *    统一的 LLMError：code（稳定错误码）+ category（分类，驱动 UI 行为）+ 原始信息。
 *  - 错误码与文案分离：LLMError 只存 code；用户文案统一由 errorMessageResource()
 *    按 code 从 string.json 解析，组件内不出现任何硬编码文案。
 *  - 新增供应商时，只需在 Provider 内做「供应商错误 → 统一错误码」映射，
 *    LLMError / UI / 存储层零改动。
 */

// 错误分类（驱动 UI 行为：标题措辞、是否保留「继续生成」按钮等）
export type ErrorCategory =
  | "config"      // 配置问题（未填/失效 Key）
  | "auth"        // 鉴权失败（401）
  | "rate_limit"  // 限流（429）
  | "context"     // 上下文超限（400）
  | "output"      // 输出被截断（response.incomplete）
  | "server"      // 服务端错误（5xx / response.failed）
  | "network"     // 网络错误（超时/断连/请求失败）
  | "unknown";    // 未知（兜底）

/**
 * 统一错误对象（可 JSON 序列化 → 持久化到消息表 error_text 列）
 *  - code：稳定错误码（枚举 ErrorCode），UI 展示与排查报错用
 *  - category：分类（按码推导，驱动 UI 行为）
 *  - httpStatus：原始 HTTP 状态码（有则带，详情展开区展示）
 *  - rawMessage：供应商原始错误信息（HTTP body 的 error.message / 底层错误描述），
 *    仅详情展开区展示，不直接面向普通用户
 *  - retryable：是否可继续生成/重试（output/network 类可「继续生成」）
 *  - provider：来源供应商标识（日志/排查定位）
 */
export interface LLMError {
  code: string;
  category: ErrorCategory;
  httpStatus?: number;
  rawMessage: string;
  retryable: boolean;
  provider: string;
}

// 统一错误码枚举（新增错误码时同步维护 categoryOf / retryableOf / errorMessageResource 三张映射表）
export enum ErrorCode {
  CFG_NOT_CONFIGURED = "CFG_NOT_CONFIGURED", // 未配置 API Key
  AUTH_INVALID_KEY = "AUTH_INVALID_KEY",     // 鉴权失败（401）
  RATE_LIMITED = "RATE_LIMITED",             // 限流（429）
  CTX_OVERFLOW = "CTX_OVERFLOW",             // 上下文超限（400）
  SRV_ERROR = "SRV_ERROR",                   // 服务端错误（5xx / response.failed）
  OUT_TRUNCATED = "OUT_TRUNCATED",           // 输出截断（response.incomplete）
  NET_TIMEOUT = "NET_TIMEOUT",               // 连接/读超时
  NET_DISCONNECTED = "NET_DISCONNECTED",     // 连接中断（dataEnd 无终止事件 / 收到部分后断连）
  NET_REQUEST_FAILED = "NET_REQUEST_FAILED", // 未收到任何内容时的请求失败
  EMPTY_RESPONSE = "EMPTY_RESPONSE",         // 流正常结束但无有效数据
  EMPTY_ANSWER = "EMPTY_ANSWER",             // completed 但无正文（联网搜索后模型空回复，可继续生成）
  UNKNOWN = "UNKNOWN",                       // 兜底
}

// 错误码 → 分类（switch 穷举，新增错误码时编译器不强制，但应同步维护）
function categoryOf(code: ErrorCode): ErrorCategory {
  switch (code) {
    case ErrorCode.CFG_NOT_CONFIGURED:
      return "config";
    case ErrorCode.AUTH_INVALID_KEY:
      return "auth";
    case ErrorCode.RATE_LIMITED:
      return "rate_limit";
    case ErrorCode.CTX_OVERFLOW:
      return "context";
    case ErrorCode.OUT_TRUNCATED:
    case ErrorCode.EMPTY_ANSWER:
      return "output";
    case ErrorCode.SRV_ERROR:
      return "server";
    case ErrorCode.NET_TIMEOUT:
    case ErrorCode.NET_DISCONNECTED:
    case ErrorCode.NET_REQUEST_FAILED:
      return "network";
    default:
      return "unknown";
  }
}

// 错误码 → 是否可继续生成/重试
function retryableOf(code: ErrorCode): boolean {
  switch (code) {
    case ErrorCode.OUT_TRUNCATED:
    case ErrorCode.NET_TIMEOUT:
    case ErrorCode.NET_DISCONNECTED:
    case ErrorCode.NET_REQUEST_FAILED:
    case ErrorCode.SRV_ERROR:
    case ErrorCode.EMPTY_RESPONSE:
    case ErrorCode.EMPTY_ANSWER:
    case ErrorCode.UNKNOWN:
      return true;
    default:
      return false;
  }
}

/**
 * 统一错误构造器（各 Provider 内部调用，避免重复组装）
 * @param code       统一错误码
 * @param rawMessage 供应商原始错误信息（可为空串）
 * @param httpStatus 原始 HTTP 状态码（可选）
 * @param provider   来源供应商标识
 */
export function buildError(
  code: ErrorCode,
  rawMessage: string,
  httpStatus?: number,
  provider: string = "unknown",
): LLMError {
  return {
    code: code,
    category: categoryOf(code),
    rawMessage: rawMessage,
    httpStatus: httpStatus,
    retryable: retryableOf(code),
    provider: provider,
  };
}

// 错误码 → 用户文案资源（string.json）

/** 
 * ArkTS 中 $r("app.string.xxx") 是编译期校验的字面量，不能运行时拼接 key，
 * 故用 switch 穷举返回 $r 字面量，保证所有资源引用可被编译器校验。
 * Toast 与气泡错误卡片共用这套文案（Toast 只显示文案；气泡叠加错误码与详情）。
 */
export function errorMessageResource(code: string): Resource {
  switch (code) {
    case ErrorCode.CFG_NOT_CONFIGURED:
      return $r("app.string.error_cfg_not_configured");
    case ErrorCode.AUTH_INVALID_KEY:
      return $r("app.string.error_auth_invalid_key");
    case ErrorCode.RATE_LIMITED:
      return $r("app.string.error_rate_limited");
    case ErrorCode.CTX_OVERFLOW:
      return $r("app.string.error_ctx_overflow");
    case ErrorCode.SRV_ERROR:
      return $r("app.string.error_srv_error");
    case ErrorCode.OUT_TRUNCATED:
      return $r("app.string.error_out_truncated");
    case ErrorCode.NET_TIMEOUT:
      return $r("app.string.error_net_timeout");
    case ErrorCode.NET_DISCONNECTED:
      return $r("app.string.error_net_disconnected");
    case ErrorCode.NET_REQUEST_FAILED:
      return $r("app.string.error_net_request_failed");
    case ErrorCode.EMPTY_RESPONSE:
      return $r("app.string.error_empty_response");
    case ErrorCode.EMPTY_ANSWER:
      return $r("app.string.error_empty_answer");
    default:
      return $r("app.string.error_unknown");
  }
}

// 分类 → 错误卡片标题（措辞暗示严重度：中断=可继续 / 失败=需处理 / 异常=可重试）
export function errorTitleResource(category: ErrorCategory): Resource {
  switch (category) {
    case "output":
    case "network":
      return $r("app.string.error_title_interrupted");
    case "config":
    case "auth":
    case "rate_limit":
    case "context":
      return $r("app.string.error_title_failed");
    default:
      return $r("app.string.error_title_abnormal");
  }
}

// 序列化（持久化到消息表 error_text 列）

// 存储 code / category / httpStatus / rawMessage / provider，读取时完整还原
export function errorToJson(err: LLMError | undefined): string {
  if (err === undefined) {
    return "";
  }
  return JSON.stringify(err);
}

export function jsonToError(json: string): LLMError | undefined {
  if (json.length === 0) {
    return undefined;
  }
  try {
    const obj = JSON.parse(json) as LLMError;
    // 缺少关键字段视为无效（旧数据或写入异常）
    if (obj.code === undefined || obj.category === undefined || obj.rawMessage === undefined) {
      return undefined;
    }
    return obj;
  } catch (e) {
    // 解析失败：降级为无错误，不影响消息展示
    return undefined;
  }
}
