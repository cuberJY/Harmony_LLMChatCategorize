/**
 * 应用配置管理
 * 管理 API Key、API 地址、模型名称等配置项
 *
 * 当前阶段（第三步）：使用硬编码默认值，快速跑通 AI 对话闭环
 * 后续阶段（第六步）：替换为 @ohos.data.preferences 持久化存储
 */

// AI API 配置接口
export interface ApiConfig {
  baseUrl: string; // API 基础地址（OpenAI 兼容格式，含 /v1/chat/completions 路径）
  apiKey: string; // API 密钥（Bearer Token）
  model: string; // 模型名称
  searchBaseUrl: string;  // 搜索 API 地址（可切换渠道）
  searchApiKey: string;  // 搜索 API 密钥（Jina；留空则用免 key 模式）
} 

export class AppConfig {
  // 单例实例
  private static instance: AppConfig;

  /**
   * 当前配置
   * 第三步：硬编码，手动替换 apiKey
   * 第六步：改为从 Preferences 读取
   */
  private config: ApiConfig = {
    baseUrl: "https://api.deepseek.com/chat/completions", // ← 替换为你的大模型 API 地址
    apiKey: "xxxxxx", // ← 替换为你的大模型 API Key
    model: "deepseek-v4-flash", // ← 替换为你的大模型名称
    searchBaseUrl: "https://api.bochaai.com/v1/web-search", // ← 替换为你的搜索渠道地址
    searchApiKey: "xxxxxx", // ← 替换为你的搜索 API Key
  };

  // 私有构造函数，禁止外部直接 new
  private constructor() {}

  // 获取单例实例
  static getInstance(): AppConfig {
    if (!AppConfig.instance) {
      AppConfig.instance = new AppConfig();
    }
    return AppConfig.instance;
  }

  // 获取完整配置对象
  getConfig(): ApiConfig {
    return this.config;
  }

  // 获取 API 地址
  getBaseUrl(): string {
    return this.config.baseUrl;
  }

  // 获取大模型 API Key
  getApiKey(): string {
    return this.config.apiKey;
  }

  // 获取模型名称
  getModel(): string {
    return this.config.model;
  }

  // 获取搜索 API 地址
  getSearchBaseUrl(): string {
    return this.config.searchBaseUrl;
  }

  // 获取搜索 API Key
  getSearchApiKey(): string {
    return this.config.searchApiKey;
  }

  /**
   * 更新配置（第六步设置页调用）
   * @param baseUrl API 地址
   * @param apiKey API 密钥
   * @param model 模型名称
   * @param searchBaseUrl 搜索 API 地址
   * @param searchApiKey 搜索 API 密钥
   */
  updateConfig(baseUrl: string, apiKey: string, model: string, searchBaseUrl: string, searchApiKey: string): void {
    this.config.baseUrl = baseUrl;
    this.config.apiKey = apiKey;
    this.config.model = model;
    this.config.searchBaseUrl = searchBaseUrl;
    this.config.searchApiKey = searchApiKey;
  }
}