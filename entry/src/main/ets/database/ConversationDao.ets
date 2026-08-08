/**
 * Conversation 表数据访问对象（DAO）
 * 单表 CRUD；异常记录日志后向上抛，由 Repository 统一捕获（事务回滚 / 页面安全）
 */

import { relationalStore } from "@kit.ArkData";
import { Conversation } from "../model/Conversation";
import { DatabaseHelper } from "./DatabaseHelper";
import { Logger } from "../common/Logger";

export class ConversationDao {
  private static instance: ConversationDao;

  private constructor() {}

  static getInstance(): ConversationDao {
    if (!ConversationDao.instance) {
      ConversationDao.instance = new ConversationDao();
    }
    return ConversationDao.instance;
  }

  // 共享 RdbStore（init 完成前为 undefined）
  private get store(): relationalStore.RdbStore | undefined {
    return DatabaseHelper.getInstance().getStore();
  }

  // 新增对话
  async insert(conv: Conversation): Promise<void> {
    const store = this.store;
    if (!store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        id: conv.id,
        title: conv.title,
        category_id: conv.categoryId,
        is_favorite: conv.isFavorite ? 1 : 0,
        is_pinned: conv.isPinned ? 1 : 0,
        created_at: conv.createdAt,
        updated_at: conv.updatedAt,
      };
      await store.insert("conversation", values);
    } catch (e) {
      Logger.error(`ConversationDao.insert failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`ConversationDao error: ${JSON.stringify(e)}`);
    }
  }

  // 设置对话置顶状态（失败上抛，由 Repository 捕获）
  async setPinned(conv: Conversation, pinned: boolean): Promise<void> {
    const store = this.store;
    if (!store) return;
    try {
      const values: relationalStore.ValuesBucket = { is_pinned: pinned ? 1 : 0 };
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.equalTo("id", conv.id);
      await store.update(values, predicates);
      conv.isPinned = pinned; // 同步内存对象
    } catch (e) {
      Logger.error(`ConversationDao.setPinned failed: ${JSON.stringify(e)}`);
      throw new Error(`ConversationDao error: ${JSON.stringify(e)}`);
    }
  }

  // 更新对话（标题、分类、更新时间），按 id 更新
  async update(conv: Conversation): Promise<void> {
    const store = this.store;
    if (!store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        title: conv.title,
        category_id: conv.categoryId,
        is_favorite: conv.isFavorite ? 1 : 0,
        is_pinned: conv.isPinned ? 1 : 0,
        updated_at: conv.updatedAt,
      };
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.equalTo("id", conv.id);
      await store.update(values, predicates);
    } catch (e) {
      Logger.error(`ConversationDao.update failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`ConversationDao error: ${JSON.stringify(e)}`);
    }
  }

  // 按 id 批量删除对话（不含消息，消息由 Repository 事务内一并删除）
  async deleteByIds(ids: string[]): Promise<void> {
    const store = this.store;
    if (!store || ids.length === 0) return;
    try {
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.in("id", ids);
      await store.delete(predicates);
    } catch (e) {
      Logger.error(`ConversationDao.deleteByIds failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`ConversationDao error: ${JSON.stringify(e)}`);
    }
  }
  

  // 查询全部对话，按最后更新时间倒序（最新在前）
  async getAll(): Promise<Conversation[]> {
    const store = this.store;
    if (!store) return [];
    const list: Conversation[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.orderByDesc("updated_at"); // 最近更新的排最前
      resultSet = await store.query(predicates);
      while (resultSet.goToNextRow()) {
        list.push(this.conversationFromResultSet(resultSet));
      }
    } catch (e) {
      Logger.error(`ConversationDao.getAll failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`ConversationDao error: ${JSON.stringify(e)}`);
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

  // 按 id 查询单个对话；不存在时返回 undefined
  async getById(id: string): Promise<Conversation | undefined> {
    const store = this.store;
    if (!store) return undefined;
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.equalTo("id", id);
      resultSet = await store.query(predicates);
      if (resultSet.goToFirstRow()) {
        return this.conversationFromResultSet(resultSet);
      }
    } catch (e) {
      Logger.error(`ConversationDao.getById failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`ConversationDao error: ${JSON.stringify(e)}`);
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
   * 按文件夹查询对话（仅已收藏、按更新时间倒序）
   * categoryId 传空串 = 查询未分类的已收藏对话
   */
  async getByCategory(categoryId: string): Promise<Conversation[]> {
    const store = this.store;
    if (!store) return [];
    const list: Conversation[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.equalTo("category_id", categoryId);
      predicates.equalTo("is_favorite", 1); // 只返回已收藏对话
      predicates.orderByDesc("is_pinned"); // 置顶优先
      predicates.orderByDesc("updated_at"); // 排序序号升序，最近更新的排最前
      resultSet = await store.query(predicates);
      while (resultSet.goToNextRow()) {
        list.push(this.conversationFromResultSet(resultSet));
      }
    } catch (e) {
      Logger.error(`ConversationDao.getByCategory failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`ConversationDao error: ${JSON.stringify(e)}`);
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

  // 查询全部已收藏对话，按更新时间倒序
  async getFavorites(): Promise<Conversation[]> {
    const store = this.store;
    if (!store) return [];
    const list: Conversation[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.equalTo("is_favorite", 1);
      predicates.orderByDesc("is_pinned"); // 置顶优先
      predicates.orderByDesc("updated_at"); // 排序序号升序，最近更新的排最前
      resultSet = await store.query(predicates);
      while (resultSet.goToNextRow()) {
        list.push(this.conversationFromResultSet(resultSet));
      }
    } catch (e) {
      Logger.error(`ConversationDao.getFavorites failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`ConversationDao error: ${JSON.stringify(e)}`);
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
   * 批量移动对话到文件夹（仅更新 category_id，保持 is_favorite 不变）
   * @param folderId 目标文件夹 ID，空串 = 移出文件夹
   */
  async move(ids: string[], folderId: string): Promise<void> {
    const store = this.store;
    if (!store || ids.length === 0) return;
    try {
      const values: relationalStore.ValuesBucket = {
        category_id: folderId,
      };
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.in("id", ids);
      await store.update(values, predicates);
    } catch (e) {
      Logger.error(`ConversationDao.move failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`ConversationDao error: ${JSON.stringify(e)}`);
    }
  }

  // 设置对话收藏状态；取消收藏时自动清空 categoryId（未收藏不参与文件夹分类）
  async setFavorite(conv: Conversation, isFavorite: boolean): Promise<void> {
    const store = this.store;
    if (!store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        is_favorite: isFavorite ? 1 : 0,
        category_id: isFavorite ? conv.categoryId : "",
      };
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.equalTo("id", conv.id);
      await store.update(values, predicates);
      conv.isFavorite = isFavorite; // 同步内存对象
    } catch (e) {
      Logger.error(`ConversationDao.setFavorite failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`ConversationDao error: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 清空一批文件夹下对话的分类（category_id 置空，不删对话）
   * 供 CategoryRepository 级联删除文件夹时调用
   */
  async clearCategory(categoryIds: string[]): Promise<void> {
    const store = this.store;
    if (!store || categoryIds.length === 0) return;
    try {
      const values: relationalStore.ValuesBucket = { category_id: "" };
      const predicates = new relationalStore.RdbPredicates("conversation");
      predicates.in("category_id", categoryIds);
      await store.update(values, predicates);
    } catch (e) {
      Logger.error(`ConversationDao.clearCategory failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`ConversationDao error: ${JSON.stringify(e)}`);
    }
  }

  // 游标行 → Conversation 对象
  private conversationFromResultSet(rs: relationalStore.ResultSet): Conversation {
    const conv = new Conversation();
    try {
      conv.id = rs.getString(rs.getColumnIndex("id"));
      conv.title = rs.getString(rs.getColumnIndex("title"));
      conv.categoryId = rs.getString(rs.getColumnIndex("category_id"));
      conv.isFavorite = rs.getLong(rs.getColumnIndex("is_favorite")) === 1;
      conv.isPinned = rs.getLong(rs.getColumnIndex("is_pinned")) === 1;
      conv.createdAt = rs.getLong(rs.getColumnIndex("created_at"));
      conv.updatedAt = rs.getLong(rs.getColumnIndex("updated_at"));
    } catch (e) {
      // 单行读取异常：保留默认值
    }
    return conv;
  }
}
