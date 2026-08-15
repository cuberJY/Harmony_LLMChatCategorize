/**
 * 对话 + 消息 聚合仓库（Repository）
 * 1. 页面访问对话/消息数据的唯一入口（页面不直接触碰 DAO）
 * 2. 跨表操作以事务保证原子性（deleteConversations / move）
 * 3. 查询方法统一吞掉 DAO 异常并返回默认值
 */

import { relationalStore } from "@kit.ArkData";
import { Conversation } from "../model/Conversation";
import { Message } from "../model/Message";
import { DatabaseHelper } from "./DatabaseHelper";
import { ConversationDao } from "./ConversationDao";
import { MessageDao } from "./MessageDao";
import { Logger } from "../common/Logger";

export class ConversationRepository {
  private static instance: ConversationRepository;

  private constructor() {}

  static getInstance(): ConversationRepository {
    if (!ConversationRepository.instance) {
      ConversationRepository.instance = new ConversationRepository();
    }
    return ConversationRepository.instance;
  }

  /* 共享 RdbStore（init 完成前为 undefined） */
  private get store(): relationalStore.RdbStore | undefined {
    return DatabaseHelper.getInstance().getStore();
  }

  /* 对话表 */

  /* 全部对话按最后更新时间倒序 */
  async getAll(): Promise<Conversation[]> {
    try {
      return await ConversationDao.getInstance().getAll();
    } catch (e) {
      Logger.error(`ConversationRepository.getAll failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  /* 单个对话；不存在时返回 undefined */
  async getById(id: string): Promise<Conversation | undefined> {
    try {
      return await ConversationDao.getInstance().getById(id);
    } catch (e) {
      Logger.error(`ConversationRepository.getById failed: ${JSON.stringify(e)}`);
      return undefined;
    }
  }

  /* 按文件夹查询（仅已收藏）；categoryId 空串 = 未分类 */
  async getByCategory(categoryId: string): Promise<Conversation[]> {
    try {
      return await ConversationDao.getInstance().getByCategory(categoryId);
    } catch (e) {
      Logger.error(`ConversationRepository.getByCategory failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  /* 全部已收藏对话，按更新时间倒序 */
  async getFavorites(): Promise<Conversation[]> {
    try {
      return await ConversationDao.getInstance().getFavorites();
    } catch (e) {
      Logger.error(`ConversationRepository.getFavorites failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  async insert(conv: Conversation): Promise<boolean> {
    try {
      await ConversationDao.getInstance().insert(conv);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.insert failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /* 取消收藏时自动清空分类 */
  async setFavorite(conv: Conversation, isFavorite: boolean): Promise<boolean> {
    try {
      await ConversationDao.getInstance().setFavorite(conv, isFavorite);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.setFavorite failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  async setPinned(conv: Conversation, pinned: boolean): Promise<boolean> {
    try {
      await ConversationDao.getInstance().setPinned(conv, pinned);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.setPinned failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  async update(conv: Conversation): Promise<boolean> {
    try {
      await ConversationDao.getInstance().update(conv);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.update failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /* 仅更新 updated_at（流式结束后刷新排序，避免整体 update 覆盖其他字段） */
  async updateTimestampOnly(id: string, updatedAt: number): Promise<boolean> {
    try {
      await ConversationDao.getInstance().updateTimestampOnly(id, updatedAt);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.updateTimestampOnly failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /**
   * 移动对话：更新分类并持久化（由 common/FolderOps.moveConversationTo 下沉）
   * @param conv 被移动的对话（@Observed，直接改字段即可驱动 UI）
   * @param folderId 目标文件夹 id，空串 = 移出不分类
   */
  async moveTo(conv: Conversation, folderId: string): Promise<boolean> {
    conv.categoryId = folderId;
    /* 防御：移入文件夹时同步置收藏，维持"文件夹内对话必然已收藏"的不变量 */
    if (folderId.length > 0) {
      conv.isFavorite = true;
    }
    return this.update(conv);
  }

  /**
   * 批量移动对话到文件夹（事务保证原子性）
   * @param folderId 目标文件夹 ID，空串 = 移出文件夹
   */
  async move(ids: string[], folderId: string): Promise<boolean> {
    const store = this.store;
    if (!store || ids.length === 0) return true;
    try {
      store.beginTransaction(); // 移入 try：begin 失败不再裸抛
      await ConversationDao.getInstance().move(ids, folderId);
      store.commit();
      return true;
    } catch (e) {
      try {
        store.rollBack(); // rollBack 自身异常单独兜住，避免二次抛错
      } catch (rollbackError) {
        Logger.error(`ConversationRepository.move rollback failed: ${JSON.stringify(rollbackError)}`);
      }
      Logger.error(`ConversationRepository.move failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /* 删除对话及其全部消息（跨表事务，中断自动回滚，无孤儿数据） */
  async deleteConversations(ids: string[]): Promise<boolean> {
    const store = this.store;
    if (!store || ids.length === 0) return true;
    try {
      store.beginTransaction(); // 移入 try：begin 失败不再裸抛
      /* 先删消息、再删对话，避免孤儿数据 */
      await MessageDao.getInstance().deleteByConversationIds(ids);
      await ConversationDao.getInstance().deleteByIds(ids);
      store.commit();
      return true;
    } catch (e) {
      try {
        store.rollBack(); // rollBack 自身异常单独兜住，避免二次抛错
      } catch (rollbackError) {
        Logger.error(`ConversationRepository.deleteConversations rollback failed: ${JSON.stringify(rollbackError)}`);
      }
      Logger.error(`ConversationRepository.deleteConversations failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /* 消息表 */

  /* 某对话全部消息按发送时间升序 */
  async getMessages(conversationId: string): Promise<Message[]> {
    try {
      return await MessageDao.getInstance().getByConversation(conversationId);
    } catch (e) {
      Logger.error(`ConversationRepository.getMessages failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  async insertMessage(msg: Message): Promise<boolean> {
    try {
      await MessageDao.getInstance().insert(msg);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.insertMessage failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /* 流式结束后回写完整内容 / 错误信息 */
  async updateMessage(msg: Message): Promise<boolean> {
    try {
      await MessageDao.getInstance().update(msg);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.updateMessage failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  async updateMessageActive(id: string, active: boolean): Promise<boolean> {
    try {
      await MessageDao.getInstance().updateActive(id, active);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.updateMessageActive failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /* 删除单条消息及其后续子树时使用 */
  async deleteMessages(ids: string[]): Promise<boolean> {
    try {
      await MessageDao.getInstance().deleteByIds(ids);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.deleteMessages failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /* 重建激活链：先将对话下全部消息置为非激活 */
  async setAllMessagesInactive(conversationId: string): Promise<boolean> {
    try {
      await MessageDao.getInstance().setAllInactive(conversationId);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.setAllMessagesInactive failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  async updateMessageActiveBatch(ids: string[], active: boolean): Promise<boolean> {
    try {
      await MessageDao.getInstance().updateActiveBatch(ids, active);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.updateMessageActiveBatch failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /* 删除消息子树；若该对话已无消息，连同对话一起删除（单事务原子） */
  async deleteMessagesAndConversationIfEmpty(convId: string, messageIds: string[]): Promise<boolean> {
    const store = this.store;
    if (!store || messageIds.length === 0) return true;
    try {
      store.beginTransaction();
      await MessageDao.getInstance().deleteByIds(messageIds);
      const remaining = await MessageDao.getInstance().countByConversation(convId);
      if (remaining === 0) {
        await ConversationDao.getInstance().deleteByIds([convId]);
      }
      store.commit();
      return true;
    } catch (e) {
      try {
        store.rollBack();
      } catch (rollbackError) {
        Logger.error(`ConversationRepository.deleteMessagesAndConversationIfEmpty rollback failed: ${JSON.stringify(rollbackError)}`);
      }
      Logger.error(`ConversationRepository.deleteMessagesAndConversationIfEmpty failed: ${JSON.stringify(e)}`);
      return false;
    }
  }
}
