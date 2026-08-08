/**
 * 应用配置管理
 * 管理 API Key、API 地址、模型名称等配置项
 *
 * 敏感凭据安全存储升级（解决 API Key 明文落盘问题）
 *  - apiKey / searchApiKey（敏感项）→ Asset Store Kit 加密存储（SecureKeyStore）
 *    · AES256-GCM 密文落盘，密钥存于 TEE 可信执行环境，即使应用数据被读取也无法还原
 *    · SyncType.NEVER：不参与云同步 / 云备份，避免密钥随备份外泄
 *  - baseUrl / model（非敏感项）→ 仍用 Preferences 明文存储，保持兼容
 *  - 旧版本迁移：首次启动检测 Preferences 中遗留的明文 Key，
 *    自动迁入 Asset Store 并删除明文残留，老用户平滑升级
 *  - 调用方（SettingsPage / Provider）API 签名不变，零改动接入
 */

import { preferences } from "@kit.ArkData";
import { common } from "@kit.AbilityKit";
import { SecureKeyStore } from "./SecureKeyStore";
import { Logger } from "../common/Logger";

// AI API 配置接口
export interface ApiConfig {
  baseUrl: string; // API 基础地址（OpenAI 兼容格式）
  apiKey: string; // API 密钥（Bearer Token）
  model: string; // 模型名称
  searchBaseUrl: string; // 搜索 API 地址（可切换渠道）
  searchApiKey: string; // 搜索 API 密钥
}

// Asset Store 中保存 API Key 的固定别名（全局唯一）
const ASSET_LLM_KEY = "llm_api_key"; // 大模型 API Key 的别名
const ASSET_SEARCH_KEY = "search_api_key"; // 搜索 API Key 的别名

// Preferences 存储的 Key 常量
const KEY_BASE_URL = "api_base_url";
// 以下两个 Key 仅用于「旧版本明文数据迁移」，迁移成功后即删除，不再写入
const KEY_API_KEY = "api_api_key";
const KEY_MODEL = "api_model";
const KEY_SEARCH_BASE_URL = "api_search_base_url";
const KEY_SEARCH_API_KEY = "api_search_api_key";

export class AppConfig {
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
   * 初始化：加载配置
   * 由 EntryAbility.onCreate 调用一次；重复调用幂等
   * 加载策略：
   *  - 非敏感项（baseUrl/model/searchBaseUrl）→ Preferences 明文读取
   *  - 敏感项（apiKey/searchApiKey）→ Asset Store 密文读取；
   *    若 Asset 无数据但 Preferences 有旧明文 → 自动迁入 Asset 并删除明文
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
      // 2. 加载非敏感项（明文 Preferences 即可）
      this.config.baseUrl = (await this.prefs.get(KEY_BASE_URL, "")) as string;
      this.config.model = (await this.prefs.get(KEY_MODEL, "")) as string;
      this.config.searchBaseUrl = (await this.prefs.get(KEY_SEARCH_BASE_URL, "")) as string;
      // 3. 加载敏感项：优先从 Asset Store（密文）读取
      let llmKey: string = await SecureKeyStore.get(ASSET_LLM_KEY);
      let searchKey: string = await SecureKeyStore.get(ASSET_SEARCH_KEY);

      // 4. 旧版本迁移：Asset 中无数据但 Preferences 遗留明文 → 迁入 Asset 并删除明文
      const legacyLlm: string = (await this.prefs.get(KEY_API_KEY, "")) as string;
      const legacySearch: string = (await this.prefs.get(KEY_SEARCH_API_KEY, "")) as string;
      let migrated: boolean = false; // 是否发生过迁移
      if (llmKey.length === 0 && legacyLlm.length > 0) {
        await SecureKeyStore.save(ASSET_LLM_KEY, legacyLlm);
        llmKey = legacyLlm;
        migrated = true;
      }
      if (searchKey.length === 0 && legacySearch.length > 0) {
        await SecureKeyStore.save(ASSET_SEARCH_KEY, legacySearch);
        searchKey = legacySearch;
        migrated = true;
      }
      // 迁移成功后立即删除明文残留，避免敏感数据继续以明文落盘
      if (migrated) {
        await this.prefs.delete(KEY_API_KEY);
        await this.prefs.delete(KEY_SEARCH_API_KEY);
        await this.prefs.flush();
      }
      // 5. 写入内存配置（后续 Provider 直接使用内存值）
      this.config.apiKey = llmKey;
      this.config.searchApiKey = searchKey;
      this.loaded = true;
    } catch (e) {
      // 初始化失败：保持默认空配置，后续保存时重试
      Logger.error(`AppConfig init failed: ${JSON.stringify(e)}`);
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
   * 更新配置并持久化
   * 设置页点击"保存"时调用
   * 持久化策略：
   *  - 非敏感项 → Preferences（明文即可，便于运维排查）
   *  - 敏感项（两个 API Key）→ Asset Store（密文落盘，明文不写盘）
   * @returns 是否全部持久化成功（内存配置始终立即生效）
   */
  async updateConfig(
    baseUrl: string,
    apiKey: string,
    model: string,
    searchBaseUrl: string,
    searchApiKey: string,
  ): Promise<boolean> {
    // 1. 内存配置立即生效（即使落盘失败也不影响本次会话）
    this.config.baseUrl = baseUrl;
    this.config.apiKey = apiKey;
    this.config.model = model;
    this.config.searchBaseUrl = searchBaseUrl;
    this.config.searchApiKey = searchApiKey;

    // 2. 非敏感项 → Preferences
    if (this.prefs) {
      try {
        await this.prefs.put(KEY_BASE_URL, baseUrl);
        await this.prefs.put(KEY_MODEL, model);
        await this.prefs.put(KEY_SEARCH_BASE_URL, searchBaseUrl);
        await this.prefs.flush(); // 立即落盘
      } catch (e) {
        Logger.error(`AppConfig save(prefs) failed: ${JSON.stringify(e)}`);
        return false;
      }
    }

    // 3. 敏感项 → Asset Store（空串时 SecureKeyStore 会删除旧密钥，避免残留）
    const llmOk: boolean = await SecureKeyStore.save(ASSET_LLM_KEY, apiKey);
    const searchOk: boolean = await SecureKeyStore.save(ASSET_SEARCH_KEY, searchApiKey);
    if (!llmOk || !searchOk) {
      Logger.warn(`AppConfig save(asset) failed: keys kept in memory only`);
      return false;
    }
    return true;
  }
}
