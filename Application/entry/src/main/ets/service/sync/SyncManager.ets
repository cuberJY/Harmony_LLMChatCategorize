/**
 * 云空间同步管理器（SyncManager）
 *
 * 方案 A 下的同步门面：对上层（AccountSyncPage）隐藏 CloudSyncService 实现细节，
 * 保持原有接口不变（getStatusCode / registerListener / unregisterListener / statusText / syncNow / init / release）。
 *
 * 实现说明：
 *   - 实际同步逻辑在 service/sync/cloud/CloudSyncService（Cloud Foundation Kit cloudDatabase）
 *   - 本类仅做初始化编排、状态码管理与 UI 广播
 *
 * 状态码（与原有枚举值保持一致，语义按方案 A 调整）：
 *   - 0  已同步 / 同步成功
 *   - 1  同步已暂停
 *   - 2  网络错误 / 同步失败
 *   - 3  未登录 / 未初始化（需先在账号登录页完成初始化）
 *   - 4  同步进行中
 */

import { common } from "@kit.AbilityKit";
import { Logger } from "../../common/Logger";
import { CloudSyncService } from "./cloud/CloudSyncService";

/* 同步状态码 */
export enum SyncStatusCode {
  UNKNOWN = -1, // 未知 / 未初始化
  SYNCED = 0, // 已与云端同步
  PAUSED = 1, // 同步已暂停
  NETWORK_ERROR = 2, // 网络错误，同步失败
  NOT_ENABLED = 3, // 未登录 / 未初始化
  SYNCING = 4, // 同步进行中
}

/* 状态变更回调（UI 订阅用，入参为当前状态码） */
export type SyncStatusListener = (code: SyncStatusCode) => void;

export class SyncManager {
  private static instance: SyncManager;

  /* 当前同步状态码（初始未知） */
  private statusCode: SyncStatusCode = SyncStatusCode.UNKNOWN;
  /* 状态回调列表 */
  private listeners: SyncStatusListener[] = [];

  private constructor() {}

  static getInstance(): SyncManager {
    if (!SyncManager.instance) {
      SyncManager.instance = new SyncManager();
    }
    return SyncManager.instance;
  }

  /**
   * 初始化：委托 CloudSyncService 完成 AGC Auth 认证 + zone 获取
   * @param context UIAbilityContext
   */
  async init(context: common.UIAbilityContext): Promise<void> {
    const ok: boolean = await CloudSyncService.getInstance().init(context);
    this.updateStatus(ok ? SyncStatusCode.SYNCED : SyncStatusCode.NOT_ENABLED);
  }

  /* 获取当前同步状态码 */
  getStatusCode(): SyncStatusCode {
    return this.statusCode;
  }

  /* 注册状态监听（返回后立即回调一次当前状态） */
  registerListener(listener: SyncStatusListener): void {
    if (this.listeners.indexOf(listener) >= 0) {
      return;
    }
    this.listeners.push(listener);
    listener(this.statusCode); // 立即同步一次当前状态
  }

  /* 注销状态监听 */
  unregisterListener(listener: SyncStatusListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  /* 状态码 → 用户提示文案（供「账号登录」页展示与引导） */
  static statusText(code: SyncStatusCode): string {
    switch (code) {
      case SyncStatusCode.SYNCED:
        return "已与云端同步";
      case SyncStatusCode.PAUSED:
        return "同步已暂停";
      case SyncStatusCode.NETWORK_ERROR:
        return "网络错误，同步失败，请稍后重试";
      case SyncStatusCode.NOT_ENABLED:
        return "未登录或未初始化（请点击立即同步初始化）";
      case SyncStatusCode.SYNCING:
        return "正在同步…";
      default:
        return "同步状态未知";
    }
  }

  /**
   * 手动立即同步（全量双向：本地→云端 + 云端→本地）
   * @returns 是否成功发起（同步过程中状态回调会推送 SYNCING / 结果）
   */
  async syncNow(): Promise<boolean> {
    if (!CloudSyncService.getInstance().isInitialized()) {
      this.updateStatus(SyncStatusCode.NOT_ENABLED);
      return false;
    }
    this.updateStatus(SyncStatusCode.SYNCING);
    const ok: boolean = await CloudSyncService.getInstance().syncNow();
    this.updateStatus(ok ? SyncStatusCode.SYNCED : SyncStatusCode.NETWORK_ERROR);
    return ok;
  }

  /* 注销（应用退出时调用，清理监听） */
  release(): void {
    this.listeners = [];
    this.statusCode = SyncStatusCode.UNKNOWN;
  }

  /* 更新状态码并广播给所有监听器 */
  private updateStatus(code: SyncStatusCode): void {
    this.statusCode = code;
    for (const listener of this.listeners) {
      listener(code);
    }
  }
}
