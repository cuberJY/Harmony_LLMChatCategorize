/**
 * 搜索 Provider 工厂（服务层接口抽象）
 * 联网搜索已迁移至 LLM 服务端（Responses API web_search 工具），业务层不再调用本工厂；
 * SearchProvider 接口仅作为「后续接入自定义网页搜索 API」的扩展点保留。
 * 接入方式：新增实现类 + 在本工厂 create() 按配置返回对应实例。
 */

import { SearchProvider } from "./provider/SearchProvider";
import { NotImplementedSearchProvider } from "./provider/NotImplementedSearchProvider";

export class SearchProviderFactory {
  /* 当前返回占位实现（未接入自定义搜索 API 前的兜底，恒不可用） */
  static create(): SearchProvider {
    return NotImplementedSearchProvider.getInstance();
  }
}
