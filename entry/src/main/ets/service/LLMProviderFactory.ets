/**
 * LLM Provider 工厂（阶段五：服务层接口抽象）
 *
 * 职责：根据运行配置返回具体的 LLMProvider 实现。
 * 业务层只依赖 LLMProvider 接口，不感知具体供应商。
 *
 * 扩展方式（未来接入新供应商）：
 *   1. 新增一个实现 LLMProvider 的 Provider 类
 *   2. 在本工厂 create() 中根据配置（如模型名 / 地址关键字）返回对应实例
 *   业务代码无需改动。
 */

import { LLMProvider } from "./provider/LLMProvider";
import { DeepSeekProvider } from "./provider/DeepSeekProvider";
import { AppConfig } from "../config/AppConfig";

export class LLMProviderFactory {
  // 根据当前配置返回对应的 LLM Provider（当前仅支持 DeepSeek/OpenAI 兼容）
  static create(): LLMProvider {
    // 预留：根据 AppConfig 的模型名或 baseUrl 关键字选择供应商
    // const baseUrl = AppConfig.getInstance().getConfig().baseUrl;
    // if (baseUrl.includes("moonshot")) { return MoonshotProvider.getInstance(); }
    return DeepSeekProvider.getInstance();
  }
}
