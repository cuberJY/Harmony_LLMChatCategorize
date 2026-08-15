/**
 * 自定义网页搜索 Provider（占位实现）
 * 联网搜索已迁移至 DeepSeek Responses API 服务端 web_search 工具，本地不再调用第三方搜索 API；
 * 本类作为 SearchProvider 接口的占位实现，保留「后续接入自定义网页搜索 API」的扩展点。
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

  /* 未实现前恒为不可用 */
  isAvailable(): boolean {
    return false;
  }

  /* 未实现前恒返回空串（调用方据此降级为普通对话） */
  async search(query: string): Promise<string> {
    return "";
  }
}
