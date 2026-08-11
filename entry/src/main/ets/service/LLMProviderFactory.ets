/**
 * LLM Provider 工厂（服务层接口抽象）
 *
 * 职责：根据运行配置返回具体的 LLMProvider 实现。
 * 业务层只依赖 LLMProvider 接口，不感知具体供应商。
 *
 * 按 AppConfig.providerId（设置页下拉选择）分发供应商，
 * baseUrl / model 由 ModelPresets 预设推导，不再手动填写。
 *
 * 扩展方式（未来接入新供应商）：
 *   1. 在 ModelPresets 追加一条预设
 *   2. 若为新协议，新增一个实现 LLMProvider 的 Provider 类，并在本工厂按 providerId 分支返回
 *   3. 若为 responses 协议，可复用 DeepSeekProvider（或按其 endpoint 规则新增实现）
 * 业务代码无需改动。
 */

import { LLMProvider } from "./provider/LLMProvider";
import { DeepSeekProvider } from "./provider/DeepSeekProvider";
import { AppConfig } from "../config/AppConfig";

export class LLMProviderFactory {
  // 根据当前配置返回对应的 LLM Provider（当前仅支持 DeepSeek / Responses API）
  static create(): LLMProvider {
    const providerId = AppConfig.getInstance().getProviderId();
    // 预留：多供应商分发（如 moonshot / qwen / 本地 Ollama 等）
    // switch (providerId) {
    //   case "moonshot": return MoonshotProvider.getInstance();
    //   ...
    // }
    return DeepSeekProvider.getInstance();
  }
}
