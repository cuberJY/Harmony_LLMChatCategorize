/**
 * 云数据库同步服务（CloudSyncService）
 *
 * 方案 A（本地 RDB 为主 + 云端副本）核心实现：
 *   - 本地 RDB 为唯一数据源，本服务负责与 AGC 云数据库（Cloud DB）全量双向同步
 *   - 冲突策略：按时间戳 last-write-wins（conversation 用 updated_at，message/category 用 created_at）
 *   - 删除暂不同步（避免复杂墓碑机制，后续增强）
 *
 * 认证：Cloud DB 写入需 Authenticated 身份，通过 AGC Auth 匿名登录获取凭据并注入 cloudCommon。
 * 前提：AGC 已开通认证服务与云数据库；agconnect-services.json 与 schema.json 均已就位。
 */

import { cloudCommon, cloudDatabase } from '@kit.CloudFoundationKit';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import auth from '@hw-agconnect/auth';
import { DatabaseHelper } from '../../../database/DatabaseHelper';
import { Logger } from '../../../common/Logger';
import { CloudConversation, CloudMessage, CloudCategory } from './CloudObjects';

/* 云数据库存储区名（与 CloudProgram/clouddb/db-config.json 的 defaultCloudDBZoneName 一致） */
const CLOUD_ZONE_NAME: string = 'default';
/* 华为云区域：中国区 */
const CLOUD_REGION: cloudCommon.CloudRegion = cloudCommon.CloudRegion.CHINA;
/* Cloud DB 单次批量写入上限为 1000 条/2 MB；按 100 条切片，兼顾长文本消息的序列化开销 */
const CLOUD_WRITE_BATCH_SIZE: number = 100;
/* 云侧查询分页大小：避免消息增多后单次查询结果过大 */
const CLOUD_QUERY_PAGE_SIZE: number = 100;
/* Cloud Foundation Kit 标准错误码 */
const CLOUD_NETWORK_ERROR_CODE: number = 1008230001;
const CLOUD_SERVER_ERROR_CODE: number = 1008231001;

/* 最近一次同步失败类型（供 SyncManager 映射为准确的 UI 状态） */
export enum CloudSyncFailureType {
  NONE = 0,
  NOT_READY = 1,
  NETWORK = 2,
  DATA_TOO_LARGE = 3,
  CLOUD = 4,
}

export class CloudSyncService {
  private static instance: CloudSyncService;

  /* 云数据库存储区实例（init 成功后赋值） */
  private zone: cloudDatabase.DatabaseZone | undefined = undefined;
  /* 是否已完成初始化（认证 + zone 获取） */
  private initialized: boolean = false;
  /* 初始化中的 Promise（防并发重复初始化） */
  private initPromise: Promise<boolean> | undefined = undefined;
  /* 是否正在同步（防重入：避免启动同步与手动同步并发） */
  private syncing: boolean = false;
  /* 最近一次同步失败类型；每次 syncNow 开始时重置 */
  private lastFailureType: CloudSyncFailureType = CloudSyncFailureType.NONE;

  private constructor() {}

  static getInstance(): CloudSyncService {
    if (!CloudSyncService.instance) {
      CloudSyncService.instance = new CloudSyncService();
    }
    return CloudSyncService.instance;
  }

  /* 是否已完成初始化（供 UI 展示登录/就绪状态） */
  isInitialized(): boolean {
    return this.initialized;
  }

  /* 获取最近一次同步失败类型（仅用于 UI 状态映射） */
  getLastFailureType(): CloudSyncFailureType {
    return this.lastFailureType;
  }

  /**
   * 初始化：AGC Auth 认证 + cloudCommon 初始化 + 获取存储区
   * 幂等；未放入 agconnect-services.json 时会失败并记录日志（不影响本地功能）
   * @param context UIAbilityContext
   * @returns 是否初始化成功
   */
  async init(context: common.UIAbilityContext): Promise<boolean> {
    if (this.initialized) {
      return true;
    }
    if (this.initPromise) {
      return this.initPromise;
    }
    this.initPromise = this.doInit(context);
    return this.initPromise;
  }

  private async doInit(context: common.UIAbilityContext): Promise<boolean> {
    try {
      /* 1. 读取 AGC 配置文件（agconnect-services.json，位于 AppScope/resources/rawfile/） */
      const raw: Uint8Array = await context.resourceManager.getRawFileContent('agconnect-services.json');
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const configStr: string = decoder.decodeWithStream(raw);

      /* 2. 初始化 AGC Auth SDK（init 为同步方法，入参为 agconnect-services.json 内容字符串） */
      auth.init(context, configStr);

      /* 3. 未登录则匿名登录：获得 Authenticated 身份（Cloud DB 写入权限要求） */
      const current = await auth.getCurrentUser();
      if (current === null) {
        await auth.signInAnonymously();
      }

      /* 4. 初始化 Cloud Foundation Kit 统一配置（注入认证凭据） */
      cloudCommon.init({
        region: CLOUD_REGION,
        authProvider: auth.getAuthProvider(),
      });

      /* 5. 获取云数据库存储区（zoneName = db-config.json 的 defaultCloudDBZoneName） */
      this.zone = cloudDatabase.zone(CLOUD_ZONE_NAME);
      this.initialized = true;
      Logger.info('CloudSyncService init OK');
      return true;
    } catch (e) {
      Logger.error(`CloudSyncService init failed: ${JSON.stringify(e)}`);
      this.initialized = false;
      return false;
    }
  }

  /**
   * 全量双向同步：先 push（本地→云端）再 pull（云端→本地）
   * @returns 是否同步成功（含"无数据可同步"的成功）
   */
  async syncNow(): Promise<boolean> {
    this.lastFailureType = CloudSyncFailureType.NONE;
    const store: relationalStore.RdbStore | undefined = DatabaseHelper.getInstance().getStore();
    if (!this.zone || !store) {
      Logger.warn('CloudSyncService syncNow skipped: not initialized or db not ready');
      this.lastFailureType = CloudSyncFailureType.NOT_READY;
      return false;
    }
    if (this.syncing) {
      return false; // 防重入：已有同步进行中
    }
    this.syncing = true;
    try {
      /* 推：本地 → 云端 */
      await this.pushConversations(store);
      await this.pushMessages(store);
      await this.pushCategories(store);
      /* 拉：云端 → 本地（last-write-wins 合并） */
      await this.pullConversations(store);
      await this.pullMessages(store);
      await this.pullCategories(store);
      Logger.info('CloudSyncService syncNow OK');
      return true;
    } catch (e) {
      const error: BusinessError = e as BusinessError;
      if (this.lastFailureType === CloudSyncFailureType.NONE) {
        this.lastFailureType = error.code === CLOUD_NETWORK_ERROR_CODE
          ? CloudSyncFailureType.NETWORK
          : CloudSyncFailureType.CLOUD;
      }
      Logger.error(`CloudSyncService syncNow failed: ${JSON.stringify(e)}`);
      return false;
    } finally {
      this.syncing = false;
    }
  }

  /* ============ push：本地 RDB → 云端 ============ */

  /**
   * 按固定条数分批写入；若服务端仍返回批次过大类错误，则递归二分当前批次。
   * Cloud DB 的 2 MB 限制针对 SDK 序列化后的请求体，无法由本地 RDB 文件大小直接推算。
   */
  private async upsertInBatches<T extends cloudDatabase.DatabaseObject>(
    list: T[], recordIds: string[], dataType: string
  ): Promise<void> {
    if (!this.zone || list.length === 0) {
      return;
    }
    for (let start: number = 0; start < list.length; start += CLOUD_WRITE_BATCH_SIZE) {
      const end: number = Math.min(start + CLOUD_WRITE_BATCH_SIZE, list.length);
      await this.upsertBatchWithSplit(list.slice(start, end), recordIds.slice(start, end), dataType);
    }
    Logger.info(`CloudSyncService push ${dataType}: ${list.length}`);
  }

  /* 服务端错误码不暴露 HTTP 413；二分批次后重试，直至定位到单条异常记录 */
  private async upsertBatchWithSplit<T extends cloudDatabase.DatabaseObject>(
    batch: T[], recordIds: string[], dataType: string
  ): Promise<void> {
    if (!this.zone || batch.length === 0) {
      return;
    }
    try {
      await this.zone.upsert(batch);
    } catch (e) {
      const error: BusinessError = e as BusinessError;
      if (error.code === CLOUD_SERVER_ERROR_CODE && batch.length > 1) {
        const middle: number = Math.floor(batch.length / 2);
        Logger.warn(`CloudSyncService split ${dataType} batch: ${batch.length}`);
        await this.upsertBatchWithSplit(batch.slice(0, middle), recordIds.slice(0, middle), dataType);
        await this.upsertBatchWithSplit(batch.slice(middle), recordIds.slice(middle), dataType);
        return;
      }
      if (error.code === CLOUD_SERVER_ERROR_CODE && batch.length === 1) {
        this.lastFailureType = CloudSyncFailureType.DATA_TOO_LARGE;
        Logger.error(`CloudSyncService ${dataType} record too large: ${recordIds[0] ?? ''}`);
      } else if (error.code === CLOUD_NETWORK_ERROR_CODE) {
        this.lastFailureType = CloudSyncFailureType.NETWORK;
      } else {
        this.lastFailureType = CloudSyncFailureType.CLOUD;
      }
      throw new Error(`Cloud DB upsert failed: ${error.code}`);
    }
  }

  private async pushConversations(store: relationalStore.RdbStore): Promise<void> {
    const list: CloudConversation[] = [];
    const recordIds: string[] = [];
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversation');
    let rs: relationalStore.ResultSet | undefined = undefined;
    try {
      rs = await store.query(predicates);
      while (rs.goToNextRow()) {
        const obj: CloudConversation = new CloudConversation();
        obj.id = rs.getString(rs.getColumnIndex('id'));
        obj.title = rs.getString(rs.getColumnIndex('title'));
        obj.category_id = rs.getString(rs.getColumnIndex('category_id'));
        obj.is_favorite = rs.getLong(rs.getColumnIndex('is_favorite'));
        obj.is_pinned = rs.getLong(rs.getColumnIndex('is_pinned'));
        obj.is_user_named = rs.getLong(rs.getColumnIndex('is_user_named'));
        /* 时间戳：本地毫秒 → 云侧秒（规避 Cloud DB Integer 32 位溢出，Date.now()≈1.7e12 超限） */
        obj.created_at = Math.floor(rs.getLong(rs.getColumnIndex('created_at')) / 1000);
        obj.updated_at = Math.floor(rs.getLong(rs.getColumnIndex('updated_at')) / 1000);
        list.push(obj);
        recordIds.push(obj.id ?? '');
      }
    } finally {
      if (rs) {
        rs.close();
      }
    }
    await this.upsertInBatches(list, recordIds, 'conversation');
  }

  private async pushMessages(store: relationalStore.RdbStore): Promise<void> {
    const list: CloudMessage[] = [];
    const recordIds: string[] = [];
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('message');
    let rs: relationalStore.ResultSet | undefined = undefined;
    try {
      rs = await store.query(predicates);
      while (rs.goToNextRow()) {
        const obj: CloudMessage = new CloudMessage();
        obj.id = rs.getString(rs.getColumnIndex('id'));
        obj.conversation_id = rs.getString(rs.getColumnIndex('conversation_id'));
        obj.role = rs.getString(rs.getColumnIndex('role'));
        obj.content = rs.getString(rs.getColumnIndex('content'));
        obj.images = rs.getString(rs.getColumnIndex('images'));
        obj.files = rs.getString(rs.getColumnIndex('files'));
        obj.reasoning = rs.getString(rs.getColumnIndex('reasoning'));
        obj.searched_webs = rs.getString(rs.getColumnIndex('searched_webs'));
        obj.generation_status = rs.getString(rs.getColumnIndex('generation_status'));
        obj.error_text = rs.getString(rs.getColumnIndex('error_text'));
        obj.thinking_duration = rs.getDouble(rs.getColumnIndex('thinking_duration'));
        /* 时间戳：本地毫秒 → 云侧秒（规避 Cloud DB Integer 32 位溢出） */
        obj.created_at = Math.floor(rs.getLong(rs.getColumnIndex('created_at')) / 1000);
        obj.parent_id = rs.getString(rs.getColumnIndex('parent_id'));
        obj.branch_group_id = rs.getString(rs.getColumnIndex('branch_group_id'));
        obj.variant_index = rs.getLong(rs.getColumnIndex('variant_index'));
        obj.is_active = rs.getLong(rs.getColumnIndex('is_active'));
        list.push(obj);
        recordIds.push(obj.id ?? '');
      }
    } finally {
      if (rs) {
        rs.close();
      }
    }
    await this.upsertInBatches(list, recordIds, 'message');
  }

  private async pushCategories(store: relationalStore.RdbStore): Promise<void> {
    const list: CloudCategory[] = [];
    const recordIds: string[] = [];
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('category');
    let rs: relationalStore.ResultSet | undefined = undefined;
    try {
      rs = await store.query(predicates);
      while (rs.goToNextRow()) {
        const obj: CloudCategory = new CloudCategory();
        obj.id = rs.getString(rs.getColumnIndex('id'));
        obj.name = rs.getString(rs.getColumnIndex('name'));
        obj.parent_id = rs.getString(rs.getColumnIndex('parent_id'));
        obj.color = rs.getString(rs.getColumnIndex('color'));
        obj.sort_order = rs.getLong(rs.getColumnIndex('sort_order'));
        obj.is_pinned = rs.getLong(rs.getColumnIndex('is_pinned'));
        /* 时间戳：本地毫秒 → 云侧秒（规避 Cloud DB Integer 32 位溢出） */
        obj.created_at = Math.floor(rs.getLong(rs.getColumnIndex('created_at')) / 1000);
        list.push(obj);
        recordIds.push(obj.id ?? '');
      }
    } finally {
      if (rs) {
        rs.close();
      }
    }
    await this.upsertInBatches(list, recordIds, 'category');
  }

  /* ============ pull：云端 → 本地 RDB（last-write-wins） ============ */

  private async pullConversations(store: relationalStore.RdbStore): Promise<void> {
    if (!this.zone) {
      return;
    }
    let offset: number = 0;
    let total: number = 0;
    while (true) {
      const condition: cloudDatabase.DatabaseQuery<CloudConversation> =
        new cloudDatabase.DatabaseQuery(CloudConversation);
      condition.orderByAsc('id').limit(CLOUD_QUERY_PAGE_SIZE, offset);
      const cloudList: CloudConversation[] = await this.zone.query(condition);
      for (const cloud of cloudList) {
        if (cloud.id === undefined) {
          continue;
        }
        const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversation');
        pred.equalTo('id', cloud.id);
        let rs: relationalStore.ResultSet | undefined = undefined;
        let exists: boolean = false;
        let localUpdated: number = 0;
        try {
          rs = await store.query(pred, ['id', 'updated_at']);
          exists = rs.rowCount > 0;
          if (exists && rs.goToFirstRow()) {
            localUpdated = rs.getLong(rs.getColumnIndex('updated_at'));
          }
        } finally {
          if (rs) {
            rs.close();
          }
        }
        /* 云侧时间戳为秒，×1000 转毫秒后与本地（毫秒）比较，保证 last-write-wins 精度一致 */
        const cloudUpdated: number = (cloud.updated_at ?? 0) * 1000;
        if (!exists) {
          await store.insert('conversation', this.cloudToConversationValues(cloud));
        } else if (cloudUpdated > localUpdated) {
          await store.update(this.cloudToConversationValues(cloud), pred);
        }
        /* 否则本地较新，保留本地 */
      }
      total += cloudList.length;
      if (cloudList.length < CLOUD_QUERY_PAGE_SIZE) {
        break;
      }
      offset += cloudList.length;
    }
    Logger.info(`CloudSyncService pull conversation: ${total}`);
  }

  private async pullMessages(store: relationalStore.RdbStore): Promise<void> {
    if (!this.zone) {
      return;
    }
    let offset: number = 0;
    let total: number = 0;
    while (true) {
      const condition: cloudDatabase.DatabaseQuery<CloudMessage> =
        new cloudDatabase.DatabaseQuery(CloudMessage);
      condition.orderByAsc('id').limit(CLOUD_QUERY_PAGE_SIZE, offset);
      const cloudList: CloudMessage[] = await this.zone.query(condition);
      for (const cloud of cloudList) {
        if (cloud.id === undefined) {
          continue;
        }
        const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('message');
        pred.equalTo('id', cloud.id);
        let rs: relationalStore.ResultSet | undefined = undefined;
        let exists: boolean = false;
        let localTime: number = 0;
        try {
          rs = await store.query(pred, ['id', 'created_at']);
          exists = rs.rowCount > 0;
          if (exists && rs.goToFirstRow()) {
            localTime = rs.getLong(rs.getColumnIndex('created_at'));
          }
        } finally {
          if (rs) {
            rs.close();
          }
        }
        const cloudTime: number = (cloud.created_at ?? 0) * 1000;
        if (!exists) {
          await store.insert('message', this.cloudToMessageValues(cloud));
        } else if (cloudTime > localTime) {
          await store.update(this.cloudToMessageValues(cloud), pred);
        }
      }
      total += cloudList.length;
      if (cloudList.length < CLOUD_QUERY_PAGE_SIZE) {
        break;
      }
      offset += cloudList.length;
    }
    Logger.info(`CloudSyncService pull message: ${total}`);
  }

  private async pullCategories(store: relationalStore.RdbStore): Promise<void> {
    if (!this.zone) {
      return;
    }
    let offset: number = 0;
    let total: number = 0;
    while (true) {
      const condition: cloudDatabase.DatabaseQuery<CloudCategory> =
        new cloudDatabase.DatabaseQuery(CloudCategory);
      condition.orderByAsc('id').limit(CLOUD_QUERY_PAGE_SIZE, offset);
      const cloudList: CloudCategory[] = await this.zone.query(condition);
      for (const cloud of cloudList) {
        if (cloud.id === undefined) {
          continue;
        }
        const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('category');
        pred.equalTo('id', cloud.id);
        let rs: relationalStore.ResultSet | undefined = undefined;
        let exists: boolean = false;
        let localTime: number = 0;
        try {
          rs = await store.query(pred, ['id', 'created_at']);
          exists = rs.rowCount > 0;
          if (exists && rs.goToFirstRow()) {
            localTime = rs.getLong(rs.getColumnIndex('created_at'));
          }
        } finally {
          if (rs) {
            rs.close();
          }
        }
        const cloudTime: number = (cloud.created_at ?? 0) * 1000;
        if (!exists) {
          await store.insert('category', this.cloudToCategoryValues(cloud));
        } else if (cloudTime > localTime) {
          await store.update(this.cloudToCategoryValues(cloud), pred);
        }
      }
      total += cloudList.length;
      if (cloudList.length < CLOUD_QUERY_PAGE_SIZE) {
        break;
      }
      offset += cloudList.length;
    }
    Logger.info(`CloudSyncService pull category: ${total}`);
  }

  /* ============ 云对象 → 本地 RDB ValuesBucket ============ */

  private cloudToConversationValues(cloud: CloudConversation): relationalStore.ValuesBucket {
    return {
      id: cloud.id ?? '',
      title: cloud.title ?? '',
      category_id: cloud.category_id ?? '',
      is_favorite: cloud.is_favorite ?? 0,
      is_pinned: cloud.is_pinned ?? 0,
      is_user_named: cloud.is_user_named ?? 0,
      /* 云侧时间戳为秒，×1000 还原为本地毫秒 */
      created_at: (cloud.created_at ?? 0) * 1000,
      updated_at: (cloud.updated_at ?? 0) * 1000,
    };
  }

  private cloudToMessageValues(cloud: CloudMessage): relationalStore.ValuesBucket {
    return {
      id: cloud.id ?? '',
      conversation_id: cloud.conversation_id ?? '',
      role: cloud.role ?? '',
      content: cloud.content ?? '',
      images: cloud.images ?? '[]',
      files: cloud.files ?? '[]',
      reasoning: cloud.reasoning ?? '',
      searched_webs: cloud.searched_webs ?? '',
      generation_status: cloud.generation_status ?? 'complete',
      error_text: cloud.error_text ?? '',
      thinking_duration: cloud.thinking_duration ?? 0,
      /* 云侧时间戳为秒，×1000 还原为本地毫秒 */
      created_at: (cloud.created_at ?? 0) * 1000,
      parent_id: cloud.parent_id ?? '',
      branch_group_id: cloud.branch_group_id ?? '',
      variant_index: cloud.variant_index ?? 0,
      is_active: cloud.is_active ?? 1,
    };
  }

  private cloudToCategoryValues(cloud: CloudCategory): relationalStore.ValuesBucket {
    return {
      id: cloud.id ?? '',
      name: cloud.name ?? '',
      parent_id: cloud.parent_id ?? '',
      color: cloud.color ?? '',
      sort_order: cloud.sort_order ?? 0,
      is_pinned: cloud.is_pinned ?? 0,
      /* 云侧时间戳为秒，×1000 还原为本地毫秒 */
      created_at: (cloud.created_at ?? 0) * 1000,
    };
  }
}
