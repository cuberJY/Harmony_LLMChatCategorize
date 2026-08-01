/**
 * 应用配置管理
 * 管理 API Key、API 地址、模型名称等配置项
 *
 * 第六步：基于 @ohos.data.preferences 持久化存储
 *  - 默认配置为空字符串，用户需在设置页自行填写
 *  - 首次启动 / 未配置时，各字段为空，AIService 会提示用户前往设置
 */

import { preferences } from "@kit.ArkData";
import { common } from "@kit.AbilityKit";
import { Conversation } from "../model/Conversation";

// AI API 配置接口
export interface ApiConfig {
  baseUrl: string; // API 基础地址（OpenAI 兼容格式）
  apiKey: string; // API 密钥（Bearer Token）
  model: string; // 模型名称
  searchBaseUrl: string; // 搜索 API 地址（可切换渠道）
  searchApiKey: string; // 搜索 API 密钥
}

// Preferences 存储的 Key 常量
const KEY_BASE_URL = "api_base_url";
const KEY_API_KEY = "api_api_key";
const KEY_MODEL = "api_model";
const KEY_SEARCH_BASE_URL = "api_search_base_url";
const KEY_SEARCH_API_KEY = "api_search_api_key";

export class AppConfig {
  selectedConversation?: Conversation = undefined; // 当前选中的对话（跨页面传值）
  private static instance: AppConfig; // 单例实例
  private prefs?: preferences.Preferences; // Preferences 实例（init 成功后赋值）
  private loaded: boolean = false; // 是否已从存储加载过配置

  // 默认配置：全部为空，用户必须自行填写
  private config: ApiConfig = {
    baseUrl: "",
    apiKey: "",
    model: "",
    searchBaseUrl: "",
    searchApiKey: "",
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

  /**
   * 初始化：获取 Preferences 实例并加载已保存的配置
   * 由 EntryAbility.onCreate 调用一次；重复调用幂等
   * @param context UIAbilityContext
   */
  async init(context: common.UIAbilityContext): Promise<void> {
    // 已初始化过则跳过
    if (this.loaded) {
      return;
    }
    try {
      // 1. 获取 Preferences 实例（文件名为 chatcategorize_config）
      this.prefs = await preferences.getPreferences(context, "chatcategorize_config");
      // 2. 加载已保存的配置（无记录时保持默认空值）
      this.config.baseUrl = (await this.prefs.get(KEY_BASE_URL, "")) as string;
      this.config.apiKey = (await this.prefs.get(KEY_API_KEY, "")) as string;
      this.config.model = (await this.prefs.get(KEY_MODEL, "")) as string;
      this.config.searchBaseUrl = (await this.prefs.get(KEY_SEARCH_BASE_URL, "")) as string;
      this.config.searchApiKey = (await this.prefs.get(KEY_SEARCH_API_KEY, "")) as string;
      this.loaded = true;
    } catch (e) {
      // 初始化失败：保持默认空配置，后续保存时重试
      console.error(`AppConfig init failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 判断是否已完整配置（大模型三项必须齐全）
   * 用于聊天前校验，未配置时提示用户前往设置页
   */
  isConfigured(): boolean {
    return (
      this.config.baseUrl.length > 0 &&
      this.config.apiKey.length > 0 &&
      this.config.model.length > 0
    );
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
   * 更新配置并持久化到 Preferences
   * 设置页点击"保存"时调用
   */
  async updateConfig(
    baseUrl: string,
    apiKey: string,
    model: string,
    searchBaseUrl: string,
    searchApiKey: string,
  ): Promise<void> {
    this.config.baseUrl = baseUrl;
    this.config.apiKey = apiKey;
    this.config.model = model;
    this.config.searchBaseUrl = searchBaseUrl;
    this.config.searchApiKey = searchApiKey;

    // 持久化（prefs 未初始化时静默失败，不影响内存配置）
    if (this.prefs) {
      try {
        await this.prefs.put(KEY_BASE_URL, baseUrl);
        await this.prefs.put(KEY_API_KEY, apiKey);
        await this.prefs.put(KEY_MODEL, model);
        await this.prefs.put(KEY_SEARCH_BASE_URL, searchBaseUrl);
        await this.prefs.put(KEY_SEARCH_API_KEY, searchApiKey);
        await this.prefs.flush(); // 立即落盘
      } catch (e) {
        console.error(`AppConfig save failed: ${JSON.stringify(e)}`);
      }
    }
  }
}
