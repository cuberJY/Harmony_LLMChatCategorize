/**
 * 安全凭据存储（基于 Asset Store Kit）
 * 解决 API Key 明文存储问题，类比 iOS Keychain / Android Keystore：
 *   - 密钥存入硬件级安全区域（TrustZone），以密文落盘
 *   - 应用数据即使被读取/备份，也无法还原明文
 *   - 默认 SyncType.NEVER：不参与云同步、不随云备份带走
 *
 * 限制：secret 长度 1~1024 字节、alias 长度 1~256 字节（API Key 远小于上限）
 * 依赖：@kit.AssetStoreKit（API 11+，HarmonyOS NEXT 内置）
 */

import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { Logger } from '../common/Logger';

export class SecureKeyStore {
  // 字符串 -> UTF-8 字节数组（Asset 的 secret/alias 要求 Uint8Array）
  private static encode(str: string): Uint8Array {
    return new util.TextEncoder().encode(str);
  }

  // 字节数组 -> 字符串
  private static decode(bytes: Uint8Array): string {
    return new util.TextDecoder().decodeToString(bytes);
  }

  /**
   * 保存或覆盖一条密钥
   * @param alias 唯一别名（建议固定常量，如 "llm_api_key"）
   * @param secret 待保护的明文密钥
   * @returns 是否保存成功（失败时已记录日志，不影响内存配置）
   */
  static async save(alias: string, secret: string): Promise<boolean> {
    if (secret.length === 0) {
      // 空串视为「清除」：删除该别名下已存在的旧密钥，
      // 避免设置页清空 Key 后，下次启动又从 Asset 读回旧值
      await SecureKeyStore.remove(alias);
      return true;
    }
    try {
      const attr: asset.AssetMap = new Map();
      attr.set(asset.Tag.ALIAS, SecureKeyStore.encode(alias));
      attr.set(asset.Tag.SECRET, SecureKeyStore.encode(secret));
      // 首次解锁后可访问（默认锁屏策略）
      attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      // 不参与设备间同步/云备份，避免密钥随迁移外泄
      attr.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
      // 别名已存在时覆盖旧值
      attr.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
      await asset.add(attr);
      return true;
    } catch (e) {
      Logger.error(`SecureKeyStore.save failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /**
   * 读取密钥；不存在或读取失败时返回空串
   * @param alias 保存时使用的别名
   */
  static async get(alias: string): Promise<string> {
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, SecureKeyStore.encode(alias));
      // 返回全部字段（包含 SECRET 明文）
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const result: asset.AssetMap[] = await asset.query(query);
      if (result.length > 0) {
        return SecureKeyStore.decode(result[0].get(asset.Tag.SECRET) as Uint8Array);
      }
      return "";
    } catch (e) {
      Logger.error(`SecureKeyStore.get failed: ${JSON.stringify(e)}`);
      return "";
    }
  }

  // 删除密钥（用于清除/重置场景）
  static async remove(alias: string): Promise<void> {
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, SecureKeyStore.encode(alias));
      await asset.remove(query);
    } catch (e) {
      Logger.error(`SecureKeyStore.remove failed: ${JSON.stringify(e)}`);
    }
  }
}
