/**
 * 自定义网页搜索 Provider（占位实现）
 *
 * 背景：联网搜索已迁移至 DeepSeek Responses API 的服务端 web_search 工具，
 * 本地不再调用第三方搜索 API。本类作为 SearchProvider 接口的占位实现，
 * 保留「后续接入自定义网页搜索 API」的扩展点。
 *
 * 接入方式（未来）：
 *   1. 复制本文件，实现真实的搜索逻辑（如调用 Tavily / Serper / 自建服务）
 *   2. 在 SearchProviderFactory.create() 中按配置返回对应实现
 *   3. 若需要开关控制，可在 AppConfig 增加搜索配置项
 */

import { SearchProvider } from "./SearchProvider";

export class NotImplementedSearchProvider implements SearchProvider {
  private static instance: NotImplementedSearchProvider;

  private constructor() {}

  static getInstance(): NotImplementedSearchProvider {
    if (!NotImplementedSearchProvider.instance) {
      NotImplementedSearchProvider.instance = new NotImplementedSearchProvider();
    }
    return NotImplementedSearchProvider.instance;
  }

  // 未实现前恒为不可用
  isAvailable(): boolean {
    return false;
  }

  // 未实现前恒返回空串（调用方据此降级为普通对话）
  async search(query: string): Promise<string> {
    return "";
  }
}
