/**
 * 数据库管理
 * 基于 relationalStore（关系型数据库），负责建表与三张表的基础 CRUD
 *
 * 表结构：
 *   conversation  对话表（标题、所属分类、创建/更新时间）
 *   message       消息表（角色、正文、思考内容、所属对话）
 *   category      分类表（名称、排序）
 *
 * 使用方式：
 *   1. 页面 aboutToAppear 时调用 init() 初始化
 *   2. 之后可调用各 insert / query / delete 方法
 *
 * ArkTS 规范：relationalStore 所有 API 均可能抛异常，调用必须 try-catch
 */

import { relationalStore } from "@kit.ArkData";
import { common } from "@kit.AbilityKit";
import { Message } from "../model/Message";
import { Conversation } from "../model/Conversation";
import { Category } from "../model/Category";

export class DatabaseHelper {
  // 当前数据库结构版本号
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
      //    ⚠️ 必须先建表：全新安装时建出含 parent_id 的新表
      //       旧库升级时表已存在，IF NOT EXISTS 自动跳过
      await store.executeSql(
        `CREATE TABLE IF NOT EXISTS conversation (
      id TEXT PRIMARY KEY,              -- 对话 ID（UUID）
      title TEXT NOT NULL DEFAULT '',    -- 对话标题（首条用户消息截断）
      category_id TEXT NOT NULL DEFAULT '', -- 所属分类 ID，空串表示未分类
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
      created_at INTEGER NOT NULL        -- 发送时间戳（毫秒）
    )`,
      );
      await store.executeSql(
        `CREATE TABLE IF NOT EXISTS category (
      id TEXT PRIMARY KEY,               -- 文件夹 ID（UUID）
      name TEXT NOT NULL,                -- 文件夹名称
      parent_id TEXT NOT NULL DEFAULT '',-- 父文件夹 ID，空串 = 顶级
      color TEXT NOT NULL DEFAULT '#FF9F0A', -- 文件夹图标颜色（默认橙色）
      sort_order INTEGER NOT NULL DEFAULT 0, -- 排序序号
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

      // 4. 开发阶段：不再保留旧版本迁移逻辑，结构统一按上方最新建表语句创建
      //    若设备上残留旧结构 db（缺 parent_id / color 列），
      //    需卸载 App 或清除数据后首次启动才会按新结构重建
      //    记录当前结构版本号，供未来结构再次调整时对照
      store.version = DatabaseHelper.DB_VERSION;

      this.store = store;
    } catch (e) {
      // 初始化失败：记录日志，store 保持空，后续调用自动降级
      console.error(`Database init failed: ${JSON.stringify(e)}`);
    }
  }

  // Conversation表

  /**
   * 新增对话
   * @param conv 对话对象
   */
  async insertConversation(conv: Conversation): Promise<void> {
    if (!this.store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        id: conv.id,
        title: conv.title,
        category_id: conv.categoryId,
        created_at: conv.createdAt,
        updated_at: conv.updatedAt,
      };
      await this.store.insert("conversation", values);
    } catch (e) {
      // 主键重复等异常：记录日志，不影响聊天流程
      console.error(`insertConversation failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 更新对话（标题、分类、更新时间）
   * @param conv 对话对象（按 id 更新）
   */
  async updateConversation(conv: Conversation): Promise<void> {
    if (!this.store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        title: conv.title,
        category_id: conv.categoryId,
        updated_at: conv.updatedAt,
      };
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.equalTo("id", conv.id);
      await this.store.update(values, predicates);
    } catch (e) {
      console.error(`updateConversation failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 删除对话及其全部消息（级联删除）
   * @param conversationId 对话 ID
   */
  async deleteConversations(ids: string[]): Promise<void> {
    if (!this.store || ids.length === 0) return;
    try {
      // 先删消息（IN 条件）
      const msgPredicates = new relationalStore.RdbPredicates("message");
      msgPredicates.in("conversation_id", ids);
      await this.store.delete(msgPredicates);
      // 再删对话
      const convPredicates = new relationalStore.RdbPredicates("conversation");
      convPredicates.in("id", ids);
      await this.store.delete(convPredicates);
    } catch (e) {
      console.error(`deleteConversations failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 查询全部对话，按最后更新时间倒序（最新在前）
   * 失败时返回空数组，调用方无需感知异常
   */
  async getConversations(): Promise<Conversation[]> {
    if (!this.store) return [];
    const list: Conversation[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.orderByDesc("updated_at"); // 最近更新的排最前
      resultSet = await this.store.query(predicates);

      while (resultSet.goToNextRow()) {
        list.push(this.conversationFromResultSet(resultSet));
      }
    } catch (e) {
      console.error(`getConversations failed: ${JSON.stringify(e)}`);
    } finally {
      // 游标必须释放；close 本身也可能抛异常，再包一层
      if (resultSet) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭失败可忽略
        }
      }
    }
    return list;
  }

  /**
   * 按 id 查询单个对话；不存在时返回 undefined
   * 用于页面返回时同步最新标题（重命名等外部变更）
   */
  async getConversationById(id: string): Promise<Conversation | undefined> {
    if (!this.store) return undefined;
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.equalTo("id", id);
      resultSet = await this.store.query(predicates);
      if (resultSet.goToFirstRow()) {
        return this.conversationFromResultSet(resultSet);
      }
    } catch (e) {
      console.error(`getConversationById failed: ${JSON.stringify(e)}`);
    } finally {
      if (resultSet) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭失败可忽略
        }
      }
    }
    return undefined;
  }

  /**
   * 按文件夹查询对话（按更新时间倒序）
   * categoryId 传空串 = 查询未分类对话
   * 用于：收藏 Tab 未分类列表、FolderPage 文件夹内对话列表
   * 失败时返回空数组，调用方无需感知异常
   */
  async getConversationsByCategory(categoryId: string): Promise<Conversation[]> {
    if (!this.store) return [];
    const list: Conversation[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.equalTo("category_id", categoryId); // 按分类过滤
      predicates.orderByDesc("updated_at"); // 最近更新的排最前
      resultSet = await this.store.query(predicates);

      while (resultSet.goToNextRow()) {
        list.push(this.conversationFromResultSet(resultSet));
      }
    } catch (e) {
      console.error(`getConversationsByCategory failed: ${JSON.stringify(e)}`);
    } finally {
      // 游标必须释放；close 本身也可能抛异常，再包一层
      if (resultSet) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭失败可忽略
        }
      }
    }
    return list;
  }

  // Message表

  /**
   * 新增一条消息
   * @param msg 消息对象
   */
  async insertMessage(msg: Message): Promise<void> {
    if (!this.store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        id: msg.id,
        conversation_id: msg.conversationId,
        role: msg.role,
        content: msg.content,
        reasoning: msg.reasoning,
        created_at: msg.createdAt,
      };
      await this.store.insert("message", values);
    } catch (e) {
      console.error(`insertMessage failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 更新一条消息（流式回复结束后，内容可能与流式过程不同）
   * @param msg 消息对象（按 id 更新 content / reasoning）
   */
  async updateMessage(msg: Message): Promise<void> {
    if (!this.store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        content: msg.content,
        reasoning: msg.reasoning,
      };
      const predicates = new relationalStore.RdbPredicates("message");
      predicates.equalTo("id", msg.id);
      await this.store.update(values, predicates);
    } catch (e) {
      console.error(`updateMessage failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 查询某对话下的全部消息，按发送时间升序（时间正序）
   * @param conversationId 对话 ID
   */
  async getMessagesByConversation(conversationId: string): Promise<Message[]> {
    if (!this.store) return [];
    const list: Message[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("message");
      predicates.equalTo("conversation_id", conversationId);
      predicates.orderByAsc("created_at"); // 旧消息在前
      resultSet = await this.store.query(predicates);

      while (resultSet.goToNextRow()) {
        list.push(this.messageFromResultSet(resultSet));
      }
    } catch (e) {
      console.error(`getMessagesByConversation failed: ${JSON.stringify(e)}`);
    } finally {
      if (resultSet) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭失败可忽略
        }
      }
    }
    return list;
  }

  // Category表

  /**
   * 新增分类
   * @param cat 分类对象
   */
  async insertCategory(cat: Category): Promise<void> {
    if (!this.store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        id: cat.id,
        name: cat.name,
        parent_id: cat.parentId,
        color: cat.color,
        sort_order: cat.sortOrder,
        created_at: cat.createdAt,
      };
      await this.store.insert("category", values);
    } catch (e) {
      console.error(`insertCategory failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 查询全部分类，按排序序号升序
   */
  async getCategories(): Promise<Category[]> {
    if (!this.store) return [];
    const list: Category[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("category");
      predicates.orderByAsc("sort_order");
      resultSet = await this.store.query(predicates);

      while (resultSet.goToNextRow()) {
        list.push(this.categoryFromResultSet(resultSet));
      }
    } catch (e) {
      console.error(`getCategories failed: ${JSON.stringify(e)}`);
    } finally {
      if (resultSet) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭失败可忽略
        }
      }
    }
    return list;
  }

  /**
   * 更新文件夹（名称、颜色、父文件夹、排序）
   * @param cat 文件夹对象（按 id 更新）
   */
  async updateCategory(cat: Category): Promise<void> {
    if (!this.store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        name: cat.name,
        color: cat.color,
        parent_id: cat.parentId, // 支持移动到其他文件夹
        sort_order: cat.sortOrder,
      };
      const predicates = new relationalStore.RdbPredicates("category");
      predicates.equalTo("id", cat.id);
      await this.store.update(values, predicates);
    } catch (e) {
      console.error(`updateCategory failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 按父文件夹查询子文件夹
   * @param parentId 父文件夹 ID，传空串查顶级文件夹
   */
  async getCategoriesByParent(parentId: string): Promise<Category[]> {
    if (!this.store) return [];
    const list: Category[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("category");
      predicates.equalTo("parent_id", parentId);
      predicates.orderByAsc("sort_order");
      resultSet = await this.store.query(predicates);
      while (resultSet.goToNextRow()) {
        list.push(this.categoryFromResultSet(resultSet));
      }
    } catch (e) {
      console.error(`getCategoriesByParent failed: ${JSON.stringify(e)}`);
    } finally {
      if (resultSet) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭失败可忽略
        }
      }
    }
    return list;
  }

  /**
   * 级联删除文件夹：删除自身 + 所有子孙文件夹 + 清空相关对话的分类
   * @param id 要删除的文件夹 ID
   */
  async deleteCategoryCascade(id: string): Promise<void> {
    if (!this.store) return;
    try {
      // 1. 递归收集所有要删除的文件夹 id
      const toDelete: string[] = [];
      await this.collectCategoryIds(id, toDelete);

      // 2. 将这些文件夹下的对话设为未分类（category_id 清空，不删对话）
      if (toDelete.length > 0) {
        const convValues: relationalStore.ValuesBucket = { category_id: "" };
        const convPredicates = new relationalStore.RdbPredicates("conversation");
        convPredicates.in("category_id", toDelete);
        await this.store.update(convValues, convPredicates);
      }

      // 3. 删除文件夹记录（含子文件夹）
      if (toDelete.length > 0) {
        const catPredicates = new relationalStore.RdbPredicates("category");
        catPredicates.in("id", toDelete);
        await this.store.delete(catPredicates);
      }
    } catch (e) {
      console.error(`deleteCategoryCascade failed: ${JSON.stringify(e)}`);
    }
  }

  // 递归收集文件夹及其子孙文件夹 id（私有辅助）
  private async collectCategoryIds(id: string, result: string[]): Promise<void> {
    result.push(id);
    const children = await this.getCategoriesByParent(id);
    for (const child of children) {
      await this.collectCategoryIds(child.id, result);
    }
  }

  /**
   * 收集某文件夹及其全部子孙文件夹的 id（移动文件夹时用于排除循环目标）
   * @param id 文件夹 ID
   */
  async getCategorySubtreeIds(id: string): Promise<string[]> {
    const result: string[] = [];
    await this.collectCategoryIds(id, result);
    return result;
  }

  // 游标行 → Conversation 对象
  private conversationFromResultSet(rs: relationalStore.ResultSet): Conversation {
    const conv = new Conversation();
    try {
      conv.id = rs.getString(rs.getColumnIndex("id"));
      conv.title = rs.getString(rs.getColumnIndex("title"));
      conv.categoryId = rs.getString(rs.getColumnIndex("category_id"));
      conv.createdAt = rs.getLong(rs.getColumnIndex("created_at"));
      conv.updatedAt = rs.getLong(rs.getColumnIndex("updated_at"));
    } catch (e) {
      // 单行读取异常：保留默认值
    }
    return conv;
  }

  // 私有：ResultSet → 模型（ArkTS：字段读取可能抛异常，需 try-catch）
  // 游标行 → Message 对象
  private messageFromResultSet(rs: relationalStore.ResultSet): Message {
    const msg = new Message("", "assistant", "");
    try {
      msg.id = rs.getString(rs.getColumnIndex("id"));
      msg.conversationId = rs.getString(rs.getColumnIndex("conversation_id"));
      msg.role = rs.getString(rs.getColumnIndex("role")) as "user" | "assistant" | "system";
      msg.content = rs.getString(rs.getColumnIndex("content"));
      msg.reasoning = rs.getString(rs.getColumnIndex("reasoning"));
      msg.createdAt = rs.getLong(rs.getColumnIndex("created_at"));
    } catch (e) {
      // 单行读取异常：保留默认值
    }
    return msg;
  }

  // 游标行 → Category 对象
  private categoryFromResultSet(rs: relationalStore.ResultSet): Category {
    const cat = new Category();
    try {
      cat.id = rs.getString(rs.getColumnIndex("id"));
      cat.name = rs.getString(rs.getColumnIndex("name"));
      cat.parentId = rs.getString(rs.getColumnIndex("parent_id"));
      cat.color = rs.getString(rs.getColumnIndex("color"));
      cat.sortOrder = rs.getLong(rs.getColumnIndex("sort_order"));
      cat.createdAt = rs.getLong(rs.getColumnIndex("created_at"));
    } catch (e) {
      // 单行读取异常：保留默认值
    }
    return cat;
  }
}
