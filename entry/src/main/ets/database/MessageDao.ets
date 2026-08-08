/**
 * Message 表数据访问对象（DAO）
 * 单表 CRUD；异常记录日志后向上抛，由 Repository 统一捕获（事务回滚 / 页面安全）
 */

import { relationalStore } from "@kit.ArkData";
import { Message } from "../model/Message";
import { DatabaseHelper } from "./DatabaseHelper";
import { Logger } from "../common/Logger";

export class MessageDao {
  private static instance: MessageDao;

  private constructor() {}

  static getInstance(): MessageDao {
    if (!MessageDao.instance) {
      MessageDao.instance = new MessageDao();
    }
    return MessageDao.instance;
  }

  // 共享 RdbStore（init 完成前为 undefined）
  private get store(): relationalStore.RdbStore | undefined {
    return DatabaseHelper.getInstance().getStore();
  }

  // 新增一条消息
  async insert(msg: Message): Promise<void> {
    const store = this.store;
    if (!store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        id: msg.id,
        conversation_id: msg.conversationId,
        role: msg.role,
        content: msg.content,
        reasoning: msg.reasoning,
        created_at: msg.createdAt,
      };
      await store.insert("message", values);
    } catch (e) {
      Logger.error(`MessageDao.insert failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`MessageDao error: ${JSON.stringify(e)}`);
    }
  }

  // 更新一条消息（流式回复结束后，内容可能与流式过程不同），按 id 更新 content / reasoning
  async update(msg: Message): Promise<void> {
    const store = this.store;
    if (!store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        content: msg.content,
        reasoning: msg.reasoning,
      };
      const predicates = new relationalStore.RdbPredicates("message");
      predicates.equalTo("id", msg.id);
      await store.update(values, predicates);
    } catch (e) {
      Logger.error(`MessageDao.update failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`MessageDao error: ${JSON.stringify(e)}`);
    }
  }

  // 查询某对话下的全部消息，按发送时间升序（时间正序）
  async getByConversation(conversationId: string): Promise<Message[]> {
    const store = this.store;
    if (!store) return [];
    const list: Message[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("message");
      predicates.equalTo("conversation_id", conversationId);
      predicates.orderByAsc("created_at"); // 旧消息在前
      resultSet = await store.query(predicates);
      while (resultSet.goToNextRow()) {
        list.push(this.messageFromResultSet(resultSet));
      }
    } catch (e) {
      Logger.error(`MessageDao.getByConversation failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`MessageDao error: ${JSON.stringify(e)}`);
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

  // 按所属对话批量删除消息（供删除对话时级联使用）
  async deleteByConversationIds(conversationIds: string[]): Promise<void> {
    const store = this.store;
    if (!store || conversationIds.length === 0) return;
    try {
      const predicates = new relationalStore.RdbPredicates("message");
      predicates.in("conversation_id", conversationIds);
      await store.delete(predicates);
    } catch (e) {
      Logger.error(`MessageDao.deleteByConversationIds failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`MessageDao error: ${JSON.stringify(e)}`);
    }
  }

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
}
