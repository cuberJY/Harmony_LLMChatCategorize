/**
 * 联网搜索服务接口抽象（服务层接口抽象）
 *
 * 设计意图：业务层（ChatViewModel）只依赖本接口与工厂，不直接依赖具体实现。
 * 未来接入其他搜索服务商（如 Serper / Tavily 等）时，
 * 只需新增一个实现 SearchProvider 的 Provider 类，并在 SearchProviderFactory 中注册。
 */

/**
 * 搜索服务统一接口
 */
export interface SearchProvider {
  // 搜索渠道是否已配置（URL 和 Key 都非空）
  isAvailable(): boolean;
  /**
   * 执行联网搜索
   * @param query 搜索关键词（通常取用户最新一条消息）
   * @returns 搜索结果的 Markdown 摘要；失败返回空串
   */
  search(query: string): Promise<string>;
}
