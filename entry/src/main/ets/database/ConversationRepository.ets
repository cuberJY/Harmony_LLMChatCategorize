/**
 * 对话 + 消息 聚合仓库（Repository）
 *
 * 职责：
 *   1. 作为页面访问对话/消息数据的唯一入口（页面不直接触碰 DAO）
 *   2. 承载跨表操作并用事务保证原子性：
 *      - deleteConversations：先删消息、再删对话（事务，中断自动回滚）
 *      - move：批量移动对话（事务）
 *   3. 查询方法统一吞掉 DAO 异常并返回默认值（页面无需感知，与原 DatabaseHelper 行为一致）
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

  // 共享 RdbStore（init 完成前为 undefined）
  private get store(): relationalStore.RdbStore | undefined {
    return DatabaseHelper.getInstance().getStore();
  }

  // 对话表

  // 查询全部对话，按最后更新时间倒序
  async getAll(): Promise<Conversation[]> {
    try {
      return await ConversationDao.getInstance().getAll();
    } catch (e) {
      Logger.error(`ConversationRepository.getAll failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  // 按 id 查询单个对话；不存在时返回 undefined
  async getById(id: string): Promise<Conversation | undefined> {
    try {
      return await ConversationDao.getInstance().getById(id);
    } catch (e) {
      Logger.error(`ConversationRepository.getById failed: ${JSON.stringify(e)}`);
      return undefined;
    }
  }

  // 按文件夹查询对话（仅已收藏）；categoryId 传空串 = 未分类
  async getByCategory(categoryId: string): Promise<Conversation[]> {
    try {
      return await ConversationDao.getInstance().getByCategory(categoryId);
    } catch (e) {
      Logger.error(`ConversationRepository.getByCategory failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  // 查询全部已收藏对话，按更新时间倒序
  async getFavorites(): Promise<Conversation[]> {
    try {
      return await ConversationDao.getInstance().getFavorites();
    } catch (e) {
      Logger.error(`ConversationRepository.getFavorites failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  // 新增对话（返回是否成功，失败由调用方提示用户）
  async insert(conv: Conversation): Promise<boolean> {
    try {
      await ConversationDao.getInstance().insert(conv);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.insert failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  // 设置对话收藏状态（取消收藏自动清空分类）（返回是否成功）
  async setFavorite(conv: Conversation, isFavorite: boolean): Promise<boolean> {
    try {
      await ConversationDao.getInstance().setFavorite(conv, isFavorite);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.setFavorite failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  // 设置对话置顶状态（返回是否成功，失败由调用方提示）
  async setPinned(conv: Conversation, pinned: boolean): Promise<boolean> {
    try {
      await ConversationDao.getInstance().setPinned(conv, pinned);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.setPinned failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  // 更新对话（标题、分类、更新时间）（返回是否成功）
  async update(conv: Conversation): Promise<boolean> {
    try {
      await ConversationDao.getInstance().update(conv);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.update failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  // 仅更新对话的 updated_at（流式结束后刷新排序，避免整体 update 覆盖流式期间的其他字段）
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
   * 移动对话：更新分类并持久化（阶段七：由 common/FolderOps.moveConversationTo 下沉）
   * @param conv 被移动的对话（@Observed，直接改字段即可驱动 UI）
   * @param folderId 目标文件夹 id，空串 = 移出不分类
   */
  async moveTo(conv: Conversation, folderId: string): Promise<boolean> {
    conv.categoryId = folderId;
    return this.update(conv);
  }

  /**
   * 批量移动对话到文件夹（事务保证原子性）
   * @param folderId 目标文件夹 ID，空串 = 移出文件夹
   */
  async move(ids: string[], folderId: string): Promise<boolean> {
    const store = this.store;
    if (!store || ids.length === 0) return true; // 无可操作项视为成功
    store.beginTransaction(); // 开启事务
    try {
      await ConversationDao.getInstance().move(ids, folderId);
      store.commit(); // 全部成功才提交
      return true;
    } catch (e) {
      store.rollBack(); // 任一失败回滚，避免半完成状态
      Logger.error(`ConversationRepository.move failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  // 删除对话及其全部消息（跨表事务：消息先行，中断自动回滚，无孤儿数据）
  async deleteConversations(ids: string[]): Promise<boolean> {
    const store = this.store;
    if (!store || ids.length === 0) return true; // 无可删除项视为成功
    store.beginTransaction(); // 开启事务
    try {
      // 先删消息、再删对话，避免孤儿数据
      await MessageDao.getInstance().deleteByConversationIds(ids);
      await ConversationDao.getInstance().deleteByIds(ids);
      store.commit(); // 全部成功才提交
      return true;
    } catch (e) {
      store.rollBack(); // 任一失败回滚，避免半删状态
      Logger.error(`ConversationRepository.deleteConversations failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  // 消息表

  // 查询某对话下的全部消息，按发送时间升序
  async getMessages(conversationId: string): Promise<Message[]> {
    try {
      return await MessageDao.getInstance().getByConversation(conversationId);
    } catch (e) {
      Logger.error(`ConversationRepository.getMessages failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  // 新增一条消息（返回是否成功）
  async insertMessage(msg: Message): Promise<boolean> {
    try {
      await MessageDao.getInstance().insert(msg);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.insertMessage failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  // 更新一条消息（流式结束后回写完整内容 / 错误信息）（返回是否成功）
  async updateMessage(msg: Message): Promise<boolean> {
    try {
      await MessageDao.getInstance().update(msg);
      return true;
    } catch (e) {
      Logger.error(`ConversationRepository.updateMessage failed: ${JSON.stringify(e)}`);
      return false;
    }
  }
}
