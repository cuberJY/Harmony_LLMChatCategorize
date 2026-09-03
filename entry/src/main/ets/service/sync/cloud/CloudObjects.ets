/**
 * 云数据库对象类（Cloud DB DatabaseObject 子类）
 *
 * 作用：Cloud Foundation Kit 的 cloudDatabase 通过 DatabaseObject 子类读写云数据库。
 * 每个子类的字段必须与 AGC 云侧对象类型（即 schema.json 中定义的 objectTypes）完全一致：
 *   - String  → string | undefined
 *   - Integer → number | undefined
 *   - Double  → number | undefined
 * naturalbase_ClassName() 返回的对象类型名 = 云侧表名（conversation / message / category）。
 *
 * 这三个类是「云空间同步」的数据载体：本地 RDB 数据序列化成这些对象后 upsert 到云端，
 * 云端数据查询回来后反序列化为这些对象再合并回本地 RDB。
 */

import { cloudDatabase } from '@kit.CloudFoundationKit';

/**
 * 对话云对象（对应云侧对象类型 conversation）
 */
export class CloudConversation extends cloudDatabase.DatabaseObject {
  public id: string | undefined = undefined;
  public title: string | undefined = undefined;
  public category_id: string | undefined = undefined;
  public is_favorite: number | undefined = undefined;
  public is_pinned: number | undefined = undefined;
  public is_user_named: number | undefined = undefined;
  public created_at: number | undefined = undefined;
  public updated_at: number | undefined = undefined;

  public naturalbase_ClassName(): string {
    return "conversation";
  }
}

/**
 * 消息云对象（对应云侧对象类型 message）
 */
export class CloudMessage extends cloudDatabase.DatabaseObject {
  public id: string | undefined = undefined;
  public conversation_id: string | undefined = undefined;
  public role: string | undefined = undefined;
  public content: string | undefined = undefined;
  public images: string | undefined = undefined;
  public files: string | undefined = undefined;
  public reasoning: string | undefined = undefined;
  public searched_webs: string | undefined = undefined;
  public generation_status: string | undefined = undefined;
  public error_text: string | undefined = undefined;
  public thinking_duration: number | undefined = undefined;
  public created_at: number | undefined = undefined;
  public parent_id: string | undefined = undefined;
  public branch_group_id: string | undefined = undefined;
  public variant_index: number | undefined = undefined;
  public is_active: number | undefined = undefined;

  public naturalbase_ClassName(): string {
    return "message";
  }
}

/**
 * 文件夹云对象（对应云侧对象类型 category）
 */
export class CloudCategory extends cloudDatabase.DatabaseObject {
  public id: string | undefined = undefined;
  public name: string | undefined = undefined;
  public parent_id: string | undefined = undefined;
  public color: string | undefined = undefined;
  public sort_order: number | undefined = undefined;
  public is_pinned: number | undefined = undefined;
  public created_at: number | undefined = undefined;

  public naturalbase_ClassName(): string {
    return "category";
  }
}
