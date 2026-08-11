/**
 * 搜索 Provider 工厂（服务层接口抽象）
 *
 * 背景：联网搜索已迁移至 LLM 服务端（DeepSeek Responses API 的 web_search 工具），
 * 当前业务层（ChatViewModel）不再调用本工厂；SearchProvider 接口仅作为
 * 「后续接入自定义网页搜索 API」的扩展点保留。
 *
 * 扩展方式（未来接入自定义搜索 API）：
 *   1. 新增一个实现 SearchProvider 的 Provider 类（替代 NotImplementedSearchProvider）
 *   2. 在本工厂 create() 中根据配置返回对应实例
 *   业务代码无需改动。
 */

import { SearchProvider } from "./provider/SearchProvider";
import { NotImplementedSearchProvider } from "./provider/NotImplementedSearchProvider";

export class SearchProviderFactory {
  // 当前返回占位实现（未接入自定义搜索 API 前的兜底，恒不可用）
  static create(): SearchProvider {
    return NotImplementedSearchProvider.getInstance();
  }
}
