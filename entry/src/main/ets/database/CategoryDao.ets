/**
 * Category 表数据访问对象（DAO）
 * 单表 CRUD + 文件夹树递归收集；异常记录日志后向上抛，由 Repository 统一捕获
 */

import { relationalStore } from "@kit.ArkData";
import { Category } from "../model/Category";
import { DatabaseHelper } from "./DatabaseHelper";
import { Logger } from "../common/Logger";

export class CategoryDao {
  private static instance: CategoryDao;

  private constructor() {}

  static getInstance(): CategoryDao {
    if (!CategoryDao.instance) {
      CategoryDao.instance = new CategoryDao();
    }
    return CategoryDao.instance;
  }

  /* 共享 RdbStore（init 完成前为 undefined） */
  private get store(): relationalStore.RdbStore | undefined {
    return DatabaseHelper.getInstance().getStore();
  }

  async insert(cat: Category): Promise<void> {
    const store = this.store;
    if (!store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        id: cat.id,
        name: cat.name,
        parent_id: cat.parentId,
        color: cat.color,
        sort_order: cat.sortOrder,
        is_pinned: cat.isPinned ? 1 : 0,
        created_at: cat.createdAt,
      };
      await store.insert("category", values);
    } catch (e) {
      Logger.error(`CategoryDao.insert failed: ${JSON.stringify(e)}`);
      throw new Error(`CategoryDao error: ${JSON.stringify(e)}`);
    }
  }

  async setPinned(cat: Category, pinned: boolean): Promise<void> {
    const store = this.store;
    if (!store) return;
    try {
      const values: relationalStore.ValuesBucket = { is_pinned: pinned ? 1 : 0 };
      const predicates = new relationalStore.RdbPredicates("category");
      predicates.equalTo("id", cat.id);
      await store.update(values, predicates);
      cat.isPinned = pinned; // 同步内存对象
    } catch (e) {
      Logger.error(`CategoryDao.setPinned failed: ${JSON.stringify(e)}`);
      throw new Error(`CategoryDao error: ${JSON.stringify(e)}`);
    }
  }

  async update(cat: Category): Promise<void> {
    const store = this.store;
    if (!store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        name: cat.name,
        color: cat.color,
        parent_id: cat.parentId, // 支持移动到其他文件夹
        sort_order: cat.sortOrder,
        is_pinned: cat.isPinned ? 1 : 0,
      };
      const predicates = new relationalStore.RdbPredicates("category");
      predicates.equalTo("id", cat.id);
      await store.update(values, predicates);
    } catch (e) {
      Logger.error(`CategoryDao.update failed: ${JSON.stringify(e)}`);
      throw new Error(`CategoryDao error: ${JSON.stringify(e)}`);
    }
  }

  /* 只删文件夹记录；子孙收集与对话清理由 Repository 事务内处理 */
  async deleteByIds(ids: string[]): Promise<void> {
    const store = this.store;
    if (!store || ids.length === 0) return;
    try {
      const predicates = new relationalStore.RdbPredicates("category");
      predicates.in("id", ids);
      await store.delete(predicates);
    } catch (e) {
      Logger.error(`CategoryDao.deleteByIds failed: ${JSON.stringify(e)}`);
      throw new Error(`CategoryDao error: ${JSON.stringify(e)}`);
    }
  }


  /* 全部分类按排序序号升序 */
  async getAll(): Promise<Category[]> {
    const store = this.store;
    if (!store) return [];
    const list: Category[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("category");
      predicates.orderByDesc("is_pinned");
      predicates.orderByAsc("sort_order");
      resultSet = await store.query(predicates);
      while (resultSet.goToNextRow()) {
        list.push(this.categoryFromResultSet(resultSet));
      }
    } catch (e) {
      Logger.error(`CategoryDao.getAll failed: ${JSON.stringify(e)}`);
      throw new Error(`CategoryDao error: ${JSON.stringify(e)}`);
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

  /* parentId 传空串查顶级文件夹 */
  async getByParent(parentId: string): Promise<Category[]> {
    const store = this.store;
    if (!store) return [];
    const list: Category[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("category");
      predicates.equalTo("parent_id", parentId);
      predicates.orderByDesc("is_pinned");
      predicates.orderByAsc("sort_order");
      resultSet = await store.query(predicates);
      while (resultSet.goToNextRow()) {
        list.push(this.categoryFromResultSet(resultSet));
      }
    } catch (e) {
      Logger.error(`CategoryDao.getByParent failed: ${JSON.stringify(e)}`);
      throw new Error(`CategoryDao error: ${JSON.stringify(e)}`);
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

  /* 某文件夹及其全部子孙的 id（排除循环目标 / 级联删除范围） */
  async getSubtreeIds(id: string): Promise<string[]> {
    const result: string[] = [];
    await this.collectCategoryIds(id, result);
    return result;
  }

  /* 递归收集文件夹及其子孙 id */
  private async collectCategoryIds(id: string, result: string[]): Promise<void> {
    result.push(id);
    const children = await this.getByParent(id);
    for (const child of children) {
      await this.collectCategoryIds(child.id, result);
    }
  }

  /* 游标行 → Category 对象 */
  private categoryFromResultSet(rs: relationalStore.ResultSet): Category {
    const cat = new Category();
    try {
      cat.id = rs.getString(rs.getColumnIndex("id"));
      cat.name = rs.getString(rs.getColumnIndex("name"));
      cat.parentId = rs.getString(rs.getColumnIndex("parent_id"));
      cat.color = rs.getString(rs.getColumnIndex("color"));
      cat.sortOrder = rs.getLong(rs.getColumnIndex("sort_order"));
      cat.isPinned = rs.getLong(rs.getColumnIndex("is_pinned")) === 1;
      cat.createdAt = rs.getLong(rs.getColumnIndex("created_at"));
    } catch (e) {
      /* 单行读取异常：保留默认值 */
    }
    return cat;
  }
}
