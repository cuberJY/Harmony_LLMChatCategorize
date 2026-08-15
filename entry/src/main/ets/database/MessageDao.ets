/**
 * Message 表数据访问对象（DAO）
 * 单表 CRUD；异常记录日志后向上抛，由 Repository 统一捕获（事务回滚 / 页面安全）
 */

import { relationalStore } from "@kit.ArkData";
import { Message, WebPage } from "../model/Message";
import { DatabaseHelper } from "./DatabaseHelper";
import { Logger } from "../common/Logger";
import { errorToJson, jsonToError } from "../service/LLMError";

export class MessageDao {
  private static instance: MessageDao;

  private constructor() {}

  static getInstance(): MessageDao {
    if (!MessageDao.instance) {
      MessageDao.instance = new MessageDao();
    }
    return MessageDao.instance;
  }

  /* 共享 RdbStore（init 完成前为 undefined） */
  private get store(): relationalStore.RdbStore | undefined {
    return DatabaseHelper.getInstance().getStore();
  }

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
        searched_webs: JSON.stringify(msg.searchedWebs),
        generation_status: msg.generationStatus,
        error_text: errorToJson(msg.error),
        thinking_duration: msg.thinkingDuration,
        created_at: msg.createdAt,
        parent_id: msg.parentId,
        branch_group_id: msg.branchGroupId,
        variant_index: msg.variantIndex,
        is_active: msg.isActive ? 1 : 0,
      };
      await store.insert("message", values);
    } catch (e) {
      Logger.error(`MessageDao.insert failed: ${JSON.stringify(e)}`);
      throw new Error(`MessageDao error: ${JSON.stringify(e)}`);
    }
  }

  /* 更新消息内容（流式回复结束后，内容可能与流式过程不同） */
  async update(msg: Message): Promise<void> {
    const store = this.store;
    if (!store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        content: msg.content,
        reasoning: msg.reasoning,
        searched_webs: JSON.stringify(msg.searchedWebs),
        generation_status: msg.generationStatus,
        error_text: errorToJson(msg.error),
        thinking_duration: msg.thinkingDuration,
      };
      const predicates = new relationalStore.RdbPredicates("message");
      predicates.equalTo("id", msg.id);
      await store.update(values, predicates);
    } catch (e) {
      Logger.error(`MessageDao.update failed: ${JSON.stringify(e)}`);
      throw new Error(`MessageDao error: ${JSON.stringify(e)}`);
    }
  }

  /* 某对话全部消息按发送时间升序 */
  async getByConversation(conversationId: string): Promise<Message[]> {
    const store = this.store;
    if (!store) return [];
    const list: Message[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("message");
      predicates.equalTo("conversation_id", conversationId);
      predicates.orderByAsc("created_at");
      resultSet = await store.query(predicates);
      while (resultSet.goToNextRow()) {
        list.push(this.messageFromResultSet(resultSet));
      }
    } catch (e) {
      Logger.error(`MessageDao.getByConversation failed: ${JSON.stringify(e)}`);
      throw new Error(`MessageDao error: ${JSON.stringify(e)}`);
    } finally {
      if (resultSet) {
        try {
          resultSet.close();
        } catch (e) {
          /* 关闭失败可忽略 */
        }
      }
    }
    return list;
  }

  /* 更新单条消息激活状态（切换分支 / 重建激活链时调用） */
  async updateActive(id: string, active: boolean): Promise<void> {
    const store = this.store;
    if (!store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        is_active: active ? 1 : 0,
      };
      const predicates = new relationalStore.RdbPredicates("message");
      predicates.equalTo("id", id);
      await store.update(values, predicates);
    } catch (e) {
      Logger.error(`MessageDao.updateActive failed: ${JSON.stringify(e)}`);
      throw new Error(`MessageDao error: ${JSON.stringify(e)}`);
    }
  }

  /* 批量更新激活状态（重建激活链，避免逐条 N 次 UPDATE） */
  async updateActiveBatch(ids: string[], active: boolean): Promise<void> {
    const store = this.store;
    if (!store || ids.length === 0) return;
    try {
      const values: relationalStore.ValuesBucket = {
        is_active: active ? 1 : 0,
      };
      const predicates = new relationalStore.RdbPredicates("message");
      predicates.in("id", ids);
      await store.update(values, predicates);
    } catch (e) {
      Logger.error(`MessageDao.updateActiveBatch failed: ${JSON.stringify(e)}`);
      throw new Error(`MessageDao error: ${JSON.stringify(e)}`);
    }
  }

  /* 统计对话消息条数（删除子树后判断对话是否已空） */
  async countByConversation(conversationId: string): Promise<number> {
    const store = this.store;
    if (!store) return 0;
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("message");
      predicates.equalTo("conversation_id", conversationId);
      resultSet = await store.query(predicates, ["id"]);
      return resultSet.rowCount;
    } catch (e) {
      Logger.error(`MessageDao.countByConversation failed: ${JSON.stringify(e)}`);
      throw new Error(`MessageDao error: ${JSON.stringify(e)}`);
    } finally {
      if (resultSet) {
        try {
          resultSet.close();
        } catch (e) {
          /* 关闭失败可忽略 */
        }
      }
    }
  }

  /* 对话下全部消息置为非激活（重建激活链：先全部熄灭再点亮目标链） */
  async setAllInactive(conversationId: string): Promise<void> {
    const store = this.store;
    if (!store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        is_active: 0,
      };
      const predicates = new relationalStore.RdbPredicates("message");
      predicates.equalTo("conversation_id", conversationId);
      await store.update(values, predicates);
    } catch (e) {
      Logger.error(`MessageDao.setAllInactive failed: ${JSON.stringify(e)}`);
      throw new Error(`MessageDao error: ${JSON.stringify(e)}`);
    }
  }

  /* 删除对话时级联删除其全部消息 */
  async deleteByConversationIds(conversationIds: string[]): Promise<void> {
    const store = this.store;
    if (!store || conversationIds.length === 0) return;
    try {
      const predicates = new relationalStore.RdbPredicates("message");
      predicates.in("conversation_id", conversationIds);
      await store.delete(predicates);
    } catch (e) {
      Logger.error(`MessageDao.deleteByConversationIds failed: ${JSON.stringify(e)}`);
      throw new Error(`MessageDao error: ${JSON.stringify(e)}`);
    }
  }

  /* 删除单条消息及其后续子树时使用 */
  async deleteByIds(ids: string[]): Promise<void> {
    const store = this.store;
    if (!store || ids.length === 0) return;
    try {
      const predicates = new relationalStore.RdbPredicates("message");
      predicates.in("id", ids);
      await store.delete(predicates);
    } catch (e) {
      Logger.error(`MessageDao.deleteByIds failed: ${JSON.stringify(e)}`);
      throw new Error(`MessageDao error: ${JSON.stringify(e)}`);
    }
  }

  /* 游标行 → Message 对象 */
  private messageFromResultSet(rs: relationalStore.ResultSet): Message {
    const msg = new Message("", "assistant", "");
    try {
      msg.id = rs.getString(rs.getColumnIndex("id"));
      msg.conversationId = rs.getString(rs.getColumnIndex("conversation_id"));
      msg.role = rs.getString(rs.getColumnIndex("role")) as "user" | "assistant" | "system";
      msg.content = rs.getString(rs.getColumnIndex("content"));
      msg.reasoning = rs.getString(rs.getColumnIndex("reasoning"));
      /* 思考过程中浏览过的网页（旧库迁移前可能缺失，读取失败则保持空列表） */
      try {
        const raw = rs.getString(rs.getColumnIndex("searched_webs"));
        if (raw.length > 0) {
          msg.searchedWebs = JSON.parse(raw) as WebPage[];
        }
      } catch (e) {
        /* 旧库无该列或 JSON 非法：保持空列表 */
      }
      /* 生成状态（旧库迁移前可能缺失，读取失败则保持默认 complete） */
      try {
        msg.generationStatus = rs.getString(rs.getColumnIndex("generation_status")) === "partial" ? "partial" : "complete";
      } catch (e) {
        /* 旧库无该列：保持默认 complete */
      }
      /* 统一错误信息（旧库迁移前可能缺失，读取失败则保持无错误） */
      try {
        msg.error = jsonToError(rs.getString(rs.getColumnIndex("error_text")));
      } catch (e) {
        /* 旧库无该列：保持无错误 */
      }
      /* 思考耗时（旧库迁移前可能缺失，读取失败则保持 0） */
      try {
        msg.thinkingDuration = rs.getDouble(rs.getColumnIndex("thinking_duration"));
      } catch (e) {
        /* 旧库无该列：保持默认 0 */
      }
      msg.createdAt = rs.getLong(rs.getColumnIndex("created_at"));
      /* 分支字段（旧库迁移前可能缺失，读取失败则保持默认值） */
      try {
        msg.parentId = rs.getString(rs.getColumnIndex("parent_id"));
        msg.branchGroupId = rs.getString(rs.getColumnIndex("branch_group_id"));
        msg.variantIndex = rs.getLong(rs.getColumnIndex("variant_index"));
        msg.isActive = rs.getLong(rs.getColumnIndex("is_active")) === 1;
      } catch (e) {
        /* 旧库无分支列：保持默认值（parentId="" → 按时间序渲染，兼容无分支旧对话） */
      }
    } catch (e) {
      /* 单行读取异常：保留默认值 */
    }
    return msg;
  }
}
