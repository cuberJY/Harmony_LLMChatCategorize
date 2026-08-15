/**
 * 应用配置管理（供应商预设化）
 * providerId 非敏感项 → Preferences 明文；apiKey 敏感项 → SecureKeyStore 加密落盘（AES256-GCM，密钥存 TEE，SyncType.NEVER 不参与云同步/备份）
 * 迁移策略：旧版明文 Key 自动迁入 Asset Store 并删除明文；baseUrl / model / 博查搜索配置已废弃，启动时清理残留
 * 调用方（SettingsPage / Provider）API 签名不变，零改动接入
 */

import { preferences } from "@kit.ArkData";
import { common } from "@kit.AbilityKit";
import { SecureKeyStore } from "./SecureKeyStore";
import { Logger } from "../common/Logger";
import { ModelPreset, getModelPreset, DEFAULT_PROVIDER_ID } from "./ModelPresets";

export interface ApiConfig {
  providerId: string; // 供应商标识（决定 API 地址与能力开关）
  model: string; // 当前供应商下选中的模型名（空串 = 使用供应商默认模型）
  apiKey: string; // API 密钥（Bearer Token）
}

/* Asset Store 中保存 API Key 的固定别名（全局唯一） */
const ASSET_LLM_KEY = "llm_api_key";

/* Preferences 存储的 Key 常量 */
const KEY_PROVIDER_ID = "api_provider_id";
const KEY_MODEL_SELECTED = "api_selected_model"; // 设置页选择的模型名（非敏感项）
/* 以下 Key 仅用于「旧版本数据迁移」，迁移成功后即删除，不再写入 */
const KEY_API_KEY = "api_api_key"; // 旧版明文大模型 Key
const KEY_BASE_URL = "api_base_url"; // 旧版 API 地址（已废弃）
const KEY_MODEL = "api_model"; // 旧版模型名（已废弃）
const KEY_SEARCH_BASE_URL = "api_search_base_url"; // 旧版搜索地址（博查，已废弃）
const KEY_SEARCH_API_KEY = "api_search_api_key"; // 旧版搜索 Key（博查，已废弃）
const ASSET_SEARCH_KEY = "search_api_key"; // 旧版搜索 Key 密文别名（博查，已废弃）

export class AppConfig {
  private static instance: AppConfig;
  private prefs?: preferences.Preferences; // Preferences 实例（init 成功后赋值）
  private loaded: boolean = false; // 是否已从存储加载过配置

  /* 默认配置：供应商默认 DeepSeek，模型取该供应商默认，Key 为空 */
  private config: ApiConfig = {
    providerId: DEFAULT_PROVIDER_ID,
    model: "",
    apiKey: "",
  };

  /* 私有构造函数，禁止外部直接 new */
  private constructor() {}

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
   *  - 非敏感项（providerId）→ Preferences 明文读取
   *  - 敏感项（apiKey）→ Asset Store 密文读取；
   *    若 Asset 无数据但 Preferences 有旧明文 → 自动迁入 Asset 并删除明文
   *  - 旧版 baseUrl / model / 搜索配置 → 全部废弃，清理残留
   * @param context UIAbilityContext
   */
  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    try {
      /* 1. 获取 Preferences 实例（文件名为 chatcategorize_config） */
      this.prefs = await preferences.getPreferences(context, "chatcategorize_config");
      /* 2. 加载供应商标识（旧版未存储时回退默认 DeepSeek） */
      const providerId: string = (await this.prefs.get(KEY_PROVIDER_ID, "")) as string;
      this.config.providerId = providerId.length > 0 ? providerId : DEFAULT_PROVIDER_ID;
      /* 3. 加载选中的模型名（空串 = 使用供应商默认模型；getModel 会兜底校验） */
      const savedModel: string = (await this.prefs.get(KEY_MODEL_SELECTED, "")) as string;
      this.config.model = savedModel;
      /* 4. 清理旧版配置残留（baseUrl / model / 博查搜索配置，已废弃） */
      await this.cleanupLegacyConfig();
      /* 5. 加载 API Key：优先从 Asset Store（密文）读取 */
      let llmKey: string = await SecureKeyStore.get(ASSET_LLM_KEY);

      /* 6. 旧版本迁移：Asset 中无数据但 Preferences 遗留明文 → 迁入 Asset 并删除明文 */
      const legacyLlm: string = (await this.prefs.get(KEY_API_KEY, "")) as string;
      if (llmKey.length === 0 && legacyLlm.length > 0) {
        /* 先校验加密保存结果：save 失败返回 false 不抛异常，此时删除明文会导致 API Key 永久丢失 */
        const saved: boolean = await SecureKeyStore.save(ASSET_LLM_KEY, legacyLlm);
        if (saved) {
          llmKey = legacyLlm;
          /* 迁移成功后立即删除明文残留，避免敏感数据继续以明文落盘 */
          await this.prefs.delete(KEY_API_KEY);
          await this.prefs.flush();
        } else {
          /* 加密保存失败：保留明文副本，本次会话沿用明文，下次启动重试迁移 */
          llmKey = legacyLlm;
          Logger.warn("AppConfig migrate key failed, keep legacy plaintext for retry");
        }
      }
      /* 7. 写入内存配置（后续 Provider 直接使用内存值） */
      this.config.apiKey = llmKey;
      this.loaded = true;
    } catch (e) {
      /* 初始化失败：保持默认空配置，后续保存时重试 */
      Logger.error(`AppConfig init failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 清理旧版本废弃配置（baseUrl / model / 博查搜索配置）
   * 启动时执行一次：删除 Preferences 残留 + 搜索 Key 密文，避免脏数据长期留存
   */
  private async cleanupLegacyConfig(): Promise<void> {
    if (!this.prefs) {
      return;
    }
    try {
      await this.prefs.delete(KEY_BASE_URL);
      await this.prefs.delete(KEY_MODEL);
      await this.prefs.delete(KEY_SEARCH_BASE_URL);
      await this.prefs.delete(KEY_SEARCH_API_KEY);
      await this.prefs.flush();
      /* 搜索 Key 密文（Asset Store） */
      await SecureKeyStore.remove(ASSET_SEARCH_KEY);
    } catch (e) {
      Logger.error(`AppConfig cleanupLegacyConfig failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 判断是否已完整配置（供应商有效 且 Key 非空）
   * 用于聊天前校验，未配置时提示用户前往设置页
   */
  isConfigured(): boolean {
    return this.config.providerId.length > 0 && this.config.apiKey.length > 0;
  }

  /* 获取完整配置对象（返回副本，避免外部改动内部配置与明文 Key 暴露面扩大） */
  getConfig(): ApiConfig {
    return {
      providerId: this.config.providerId,
      model: this.config.model,
      apiKey: this.config.apiKey,
    };
  }

  getProviderId(): string {
    return this.config.providerId;
  }

  getApiKey(): string {
    return this.config.apiKey;
  }

  /* 获取当前供应商预设（由 providerId 推导，必然存在） */
  getPreset(): ModelPreset {
    return getModelPreset(this.config.providerId);
  }

  /**
   * 获取当前实际使用的模型名（设置页选择的模型）
   * 兜底校验：所选模型不属于当前供应商时回退该供应商默认模型，保证永远返回可用值
   */
  getModel(): string {
    const preset = this.getPreset();
    if (this.config.model.length > 0 && preset.models.indexOf(this.config.model) >= 0) {
      return this.config.model;
    }
    return preset.defaultModel;
  }

  getBaseUrl(): string {
    return this.getPreset().endpoint;
  }

  /**
   * 更新配置并持久化
   * 设置页点击"保存"时调用
   * 持久化策略：
   *  - 非敏感项（providerId / model）→ Preferences（明文即可，便于运维排查）
   *  - 敏感项（apiKey）→ Asset Store（密文落盘，明文不写盘）
   * @param providerId 供应商标识（下拉选择）
   * @param apiKey API 密钥
   * @param model 当前供应商下选中的模型名（空串 = 默认模型）
   * @returns 是否全部持久化成功（内存配置始终立即生效）
   */
  async updateConfig(providerId: string, apiKey: string, model: string): Promise<boolean> {
    /* 1. 内存配置立即生效（即使落盘失败也不影响本次会话） */
    this.config.providerId = providerId;
    this.config.apiKey = apiKey;
    this.config.model = model;

    /**
     * 2. 敏感项 → Asset Store（空串时 SecureKeyStore 会删除旧密钥，避免残留）。
     *    先保存敏感项：Asset 失败时直接返回 false，不产生"新供应商 + 旧 Key"错配
     */
    const llmOk: boolean = await SecureKeyStore.save(ASSET_LLM_KEY, apiKey);
    if (!llmOk) {
      Logger.warn(`AppConfig save(asset) failed: keys kept in memory only`);
      return false;
    }

    /* 3. 非敏感项 → Preferences */
    if (this.prefs === undefined) {
      Logger.warn(`AppConfig save(prefs) failed: preferences not initialized`);
      return false;
    }
    try {
      await this.prefs.put(KEY_PROVIDER_ID, providerId);
      await this.prefs.put(KEY_MODEL_SELECTED, model);
      await this.prefs.flush();
    } catch (e) {
      Logger.error(`AppConfig save(prefs) failed: ${JSON.stringify(e)}`);
      return false;
    }
    return true;
  }
}
