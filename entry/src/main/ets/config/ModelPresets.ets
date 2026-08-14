/**
 * 模型供应商预设注册表
 *
 * 设计意图：将「供应商 → API 地址 / 模型名 / 能力开关」收敛为一份可配置的注册表。
 * 设置页只展示供应商下拉（选择 id），Provider 工厂按 id 返回对应实现，
 * 业务层（ChatViewModel）不感知任何供应商细节。
 *
 * 扩展方式（后续接入多模型适配）：
 *   1. 在本数组追加一条 ModelPreset（如 Moonshot / Qwen / 本地 Ollama）
 *   2. 若为新协议（apiStyle 非 responses），在 LLMProviderFactory 按 providerId 分支返回对应 Provider
 *   3. 设置页下拉自动带出新供应商，业务代码零改动
 */

/**
 * 供应商预设
 * @param id              唯一标识（持久化到 AppConfig.providerId）
 * @param providerName    供应商显示名（设置页下拉展示）
 * @param defaultModel    默认模型（未选择记录时兜底；传入 API 的 model 字段）
 * @param models          该供应商可选的模型列表（设置页"模型名称"下拉展示）
 * @param endpoint        完整请求地址（Responses API 为 base_url + /responses）
 * @param apiStyle        API 风格："responses"（Responses API）| "chat"（Chat Completions，预留）
 * @param supportsWebSearch 是否支持服务端联网搜索（web_search 工具）
 * @param supportsReasoning 是否支持思考模式（reasoning.effort）
 */
export interface ModelPreset {
  id: string;
  providerName: string;
  defaultModel: string;
  models: string[];
  endpoint: string;
  apiStyle: string;
  supportsWebSearch: boolean;
  supportsReasoning: boolean;
}

// 当前支持的供应商列表（未来多模型在此追加）
export const MODEL_PRESETS: ModelPreset[] = [
  {
    id: "deepseek",
    providerName: "DeepSeek",
    defaultModel: "deepseek-v4-flash",
    models: ["deepseek-v4-flash", "deepseek-v4-pro"],
    endpoint: "https://api.deepseek.com/responses",
    apiStyle: "responses",
    supportsWebSearch: true,
    supportsReasoning: true,
  },
];

// 默认供应商（未配置 / 配置缺失时回退到第一个，保证永远有可用配置）
export const DEFAULT_PROVIDER_ID: string = "deepseek";

/**
 * 按 id 查找供应商预设；找不到时回退到第一个预设
 * @param providerId 供应商标识
 * @returns ModelPreset 预设（必然存在，不会返回 undefined）
 */
export function getModelPreset(providerId: string): ModelPreset {
  const preset = MODEL_PRESETS.find((p: ModelPreset) => p.id === providerId);
  return preset !== undefined ? preset : MODEL_PRESETS[0];
}
