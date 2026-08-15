/**
 * LLM Provider 工厂（服务层接口抽象）
 * 根据运行配置返回具体的 LLMProvider 实现，业务层只依赖接口，不感知具体供应商。
 * 分发依据 AppConfig.providerId；baseUrl / model 由 ModelPresets 预设推导。
 * 接入新供应商：ModelPresets 追加预设 + 新增实现类 + 本工厂按 providerId 分支返回。
 */

import { LLMProvider } from "./provider/LLMProvider";
import { DeepSeekProvider } from "./provider/DeepSeekProvider";
import { AppConfig } from "../config/AppConfig";

export class LLMProviderFactory {
  /* 根据当前配置返回对应的 LLM Provider（当前仅支持 DeepSeek / Responses API） */
  static create(): LLMProvider {
    const providerId = AppConfig.getInstance().getProviderId();
    /* 预留：多供应商分发（moonshot / qwen / 本地 Ollama 等） */
    return DeepSeekProvider.getInstance();
  }
}
