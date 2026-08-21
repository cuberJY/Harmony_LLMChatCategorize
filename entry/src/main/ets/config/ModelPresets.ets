/**
 * 模型供应商预设注册表
 * 将「供应商 → API 地址 / 模型名 / 能力开关」收敛为一份注册表：
 * 设置页按 id 展示供应商下拉，Provider 工厂按 id 返回实现，业务层不感知供应商细节
 * 扩展新供应商：数组追加一条 ModelPreset；新协议（apiStyle 非 responses）在 LLMProviderFactory 按 providerId 分支
 *
 * 思考强度（ThinkingEffort）：面向 Responses API 的 reasoning.effort，
 * 档位「关闭/轻量/深度/极限」由供应商能力统一收敛，业务层（VM / UI / Provider）共同引用
 */

/**
 * 思考强度档位（对应 Responses API reasoning.effort）
 * DeepSeek 官方取值 none/low/high/max（medium/xhigh 会映射为 high，故不单独列出）：
 * - none：关闭思考模式（不输出思维链，响应最快）
 * - low ：轻量思考（快速推理）
 * - high：深度思考（模型默认 effort，适合多数任务）
 * - max ：极限思考（最强推理，耗时与 token 消耗更高）
 */
export type ThinkingEffort = "none" | "low" | "high" | "max";

/**
 * 思考强度档位条目
 * @param value 传给 API 的 effort 值
 * @param label 按钮 / 下拉菜单展示文案
 */
export interface ThinkingLevel {
  value: ThinkingEffort;
  label: string;
}

/* 全部可选的思考强度档位（下拉菜单按此顺序展示） */
export const THINKING_LEVELS: ThinkingLevel[] = [
  { value: "none", label: "关闭" },
  { value: "low", label: "Low" },
  { value: "high", label: "High" },
  { value: "max", label: "Max" },
];

/* 默认思考强度（保持旧版 deepThinking=true 的行为：深度思考） */
export const DEFAULT_THINKING_EFFORT: ThinkingEffort = "high";

/**
 * 按 effort 值查找档位条目（用于按钮展示与弹窗选中态）
 * 非法 / 未知值时回退默认档位（深度思考），保证永远返回有效条目
 */
export function getThinkingLevel(effort: string): ThinkingLevel {
  const found = THINKING_LEVELS.find((l: ThinkingLevel) => l.value === effort);
  return found !== undefined ? found : THINKING_LEVELS[2];
}

/* 取档位展示文案（按钮显示用） */
export function thinkingLevelLabel(effort: string): string {
  return getThinkingLevel(effort).label;
}

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
 * @param supportsVision 是否提供视觉模型（图片理解；visionModels 为空则视为不支持）
 * @param visionModels 该供应商支持视觉（图片理解）的模型名列表（判断发图能力用）
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
  supportsVision: boolean;
  visionModels: string[];
}

/* 当前支持的供应商列表（未来多模型在此追加） */
export const MODEL_PRESETS: ModelPreset[] = [
  {
    id: "deepseek",
    providerName: "DeepSeek",
    defaultModel: "deepseek-v4-flash",
    models: ["deepseek-v4-flash", "deepseek-v4-pro", "deepseek-v4-flash-vision-exp"],
    endpoint: "https://api.deepseek.com/responses",
    apiStyle: "responses",
    supportsWebSearch: true,
    supportsReasoning: true,
    supportsVision: true,
    visionModels: ["deepseek-v4-flash-vision-exp"],
  },
];

/* 默认供应商（未配置 / 配置缺失时回退到第一个，保证永远有可用配置） */
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

/**
 * 判断指定模型名是否支持视觉（图片理解）
 * 匹配全部预设的 visionModels 列表（模型名全局唯一，无需区分供应商）
 * @param modelName 模型名（AppConfig.getModel() 返回值）
 * @returns true = 支持视觉，可发送图片
 */
export function isVisionModel(modelName: string): boolean {
  for (const preset of MODEL_PRESETS) {
    if (preset.visionModels.indexOf(modelName) >= 0) {
      return true;
    }
  }
  return false;
}
