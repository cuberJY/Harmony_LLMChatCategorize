/**
 * 搜索 Provider 工厂（阶段五：服务层接口抽象）
 *
 * 职责：根据运行配置返回具体的 SearchProvider 实现。
 * 业务层只依赖 SearchProvider 接口，不感知具体服务商。
 *
 * 扩展方式（未来接入新搜索服务商）：
 *   1. 新增一个实现 SearchProvider 的 Provider 类
 *   2. 在本工厂 create() 中根据配置返回对应实例
 *   业务代码无需改动。
 */

import { SearchProvider } from "./provider/SearchProvider";
import { BochaSearchProvider } from "./provider/BochaSearchProvider";

export class SearchProviderFactory {
  // 根据当前配置返回对应的搜索 Provider（当前仅支持博查）
  static create(): SearchProvider {
    return BochaSearchProvider.getInstance();
  }
}
