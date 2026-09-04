/**
 * 联网搜索服务接口抽象
 * 业务层只依赖本接口与工厂；接入新搜索服务商只需新增实现类并在 SearchProviderFactory 注册。
 */

/**
 * 搜索服务统一接口
 */
export interface SearchProvider {
  /* 搜索渠道是否已配置（URL 和 Key 都非空） */
  isAvailable(): boolean;
  /**
   * 执行联网搜索
   * @param query 搜索关键词（通常取用户最新一条消息）
   * @returns 搜索结果的 Markdown 摘要；失败返回空串
   */
  search(query: string): Promise<string>;
}
