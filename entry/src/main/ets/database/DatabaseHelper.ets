/**
 * 数据库初始化与 RdbStore 持有者（阶段2瘦身版）
 *
 * 职责收敛为两点：
 *   1. 初始化 RdbStore 并建表（幂等，IF NOT EXISTS）
 *   2. 向各 DAO 提供共享的 RdbStore 实例（getStore）
 *
 * 具体表的 CRUD 已拆分到 database 目录下的三个 DAO：
 *   - ConversationDao / MessageDao / CategoryDao（平铺，单表数据访问，异常上抛）
 * 跨表聚合与事务操作由两个 Repository 承载：
 *   - ConversationRepository（对话 + 消息）
 *   - CategoryRepository（文件夹树 + 级联删除）
 *
 * 开发阶段说明（用户决策）：不需要数据库版本迁移，结构直接按最新建表语句创建。
 * 若设备残留旧结构 db，卸载 App 或清除数据后重新创建即可。
 */

import { relationalStore } from "@kit.ArkData";
import { common } from "@kit.AbilityKit";
import { Logger } from "../common/Logger";

export class DatabaseHelper {
  // 当前数据库结构版本号（开发阶段固定 1，暂不启用 onUpgrade 迁移）
  private static readonly DB_VERSION: number = 1;

  // 单例实例
  private static instance: DatabaseHelper;

  // 数据库操作对象（init 成功后赋值）
  private store?: relationalStore.RdbStore;

  // 私有构造函数，禁止外部直接 new
  private constructor() {}

  // 获取单例实例
  static getInstance(): DatabaseHelper {
    if (!DatabaseHelper.instance) {
      DatabaseHelper.instance = new DatabaseHelper();
    }
    return DatabaseHelper.instance;
  }

  /**
   * 初始化数据库并建表
   * 幂等：重复调用不会重复建表（IF NOT EXISTS）
   * @param context UIAbilityContext，用于获取数据库文件路径
   */
  async init(context: common.UIAbilityContext): Promise<void> {
    // 已初始化则跳过
    if (this.store) {
      return;
    }

    try {
      // 1. 获取 RdbStore 实例
      const store = await relationalStore.getRdbStore(context, {
        name: "chatcategorize.db", // 数据库文件名
        securityLevel: relationalStore.SecurityLevel.S1, // 一般数据安全级别
      });

      // 2. 建表 + 建索引（IF NOT EXISTS，重复执行安全）
      await store.executeSql(
        `CREATE TABLE IF NOT EXISTS conversation (
      id TEXT PRIMARY KEY,              -- 对话 ID（UUID）
      title TEXT NOT NULL DEFAULT '',    -- 对话标题（首条用户消息截断）
      category_id TEXT NOT NULL DEFAULT '', -- 收藏位置（文件夹）ID，空串 = 未放入文件夹
      is_favorite INTEGER NOT NULL DEFAULT 0, -- 是否收藏：0 未收藏 / 1 已收藏
      is_pinned INTEGER NOT NULL DEFAULT 0, -- 是否置顶
      created_at INTEGER NOT NULL,       -- 创建时间戳（毫秒）
      updated_at INTEGER NOT NULL        -- 最后更新时间戳（毫秒）
    )`,
      );

      await store.executeSql(
        `CREATE TABLE IF NOT EXISTS message (
      id TEXT PRIMARY KEY,               -- 消息 ID（UUID）
      conversation_id TEXT NOT NULL,     -- 所属对话 ID（外键逻辑关联）
      role TEXT NOT NULL,                -- 消息角色：user / assistant / system
      content TEXT NOT NULL DEFAULT '',  -- 消息正文
      reasoning TEXT NOT NULL DEFAULT '',-- AI 思考内容（仅 assistant 有值）
      created_at INTEGER NOT NULL,       -- 发送时间戳（毫秒）
      parent_id TEXT NOT NULL DEFAULT '',-- 父消息 ID（分支链：被回复的消息，根消息为空串）
      branch_group_id TEXT NOT NULL DEFAULT '', -- 分支组 ID（= parent_id，同组消息互为变体）
      variant_index INTEGER NOT NULL DEFAULT 0, -- 变体序号（0 起，驱动 "< 当前 / 总数 >"）
      is_active INTEGER NOT NULL DEFAULT 1 -- 是否当前激活分支（列表仅渲染激活链）
    )`,
      );
      await store.executeSql(
        `CREATE TABLE IF NOT EXISTS category (
      id TEXT PRIMARY KEY,               -- 文件夹 ID（UUID）
      name TEXT NOT NULL,                -- 文件夹名称
      parent_id TEXT NOT NULL DEFAULT '',-- 父文件夹 ID，空串 = 顶级
      color TEXT NOT NULL, -- 文件夹图标颜色（默认值由模型层 AppConstants.DEFAULT_FOLDER_COLOR 保证）
      sort_order INTEGER NOT NULL DEFAULT 0, -- 排序序号（0 为置顶）
      is_pinned INTEGER NOT NULL DEFAULT 0, -- 是否置顶
      created_at INTEGER NOT NULL        -- 创建时间戳（毫秒）
    )`,
      );

      // 3. 高频查询索引
      await store.executeSql(
        `CREATE INDEX IF NOT EXISTS idx_message_conversation ON message(conversation_id)`,
      );
      await store.executeSql(
        `CREATE INDEX IF NOT EXISTS idx_conversation_updated ON conversation(updated_at DESC)`,
      );

      // 4. 兼容旧库：message 表缺少分支字段时补列（开发阶段直接 ALTER，不引入版本迁移）
      await this.ensureMessageColumns(store);

      // 5. 记录当前结构版本号（开发阶段固定 1，不启用迁移）
      store.version = DatabaseHelper.DB_VERSION;

      this.store = store;
    } catch (e) {
      // 初始化失败：记录日志，store 保持空，后续调用自动降级
      Logger.error(`Database init failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 获取共享 RdbStore（供各 DAO 使用）
   * init 完成前返回 undefined，调用方需判空
   */
  getStore(): relationalStore.RdbStore | undefined {
    return this.store;
  }

  /**
   * 兼容旧库：检测 message 表是否缺少分支字段，缺失则 ALTER TABLE 补列
   * 新装库建表语句已含全字段，此方法仅对历史版本数据库生效（幂等）
   */
  private async ensureMessageColumns(store: relationalStore.RdbStore): Promise<void> {
    try {
      // 读取表结构：LIMIT 0 不返回数据行，但 ResultSet 携带全部列名
      const rs = await store.querySql('SELECT * FROM message LIMIT 0');
      const existingCols: string[] = [];
      for (let i = 0; i < rs.columnCount; i++) {
        existingCols.push(rs.getColumnName(i));
      }
      rs.close();
      // 需要补齐的分支字段定义（名称 + SQL 片段）
      const newCols: string[] = [
        "parent_id TEXT NOT NULL DEFAULT ''",
        "branch_group_id TEXT NOT NULL DEFAULT ''",
        "variant_index INTEGER NOT NULL DEFAULT 0",
        "is_active INTEGER NOT NULL DEFAULT 1",
      ];
      for (const def of newCols) {
        const colName = def.split(' ')[0]; // 取列名（定义首词）
        if (existingCols.indexOf(colName) < 0) {
          await store.executeSql(`ALTER TABLE message ADD COLUMN ${def}`);
        }
      }
    } catch (e) {
      // 迁移失败：不影响主流程（新库已含全字段），仅记录日志
      Logger.error(`ensureMessageColumns failed: ${JSON.stringify(e)}`);
    }
  }
}
