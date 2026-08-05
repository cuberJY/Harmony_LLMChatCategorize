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

  // 共享 RdbStore（init 完成前为 undefined）
  private get store(): relationalStore.RdbStore | undefined {
    return DatabaseHelper.getInstance().getStore();
  }

  /**
   * 新增分类
   */
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
        created_at: cat.createdAt,
      };
      await store.insert("category", values);
    } catch (e) {
      Logger.error(`CategoryDao.insert failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`CategoryDao error: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 查询全部分类，按排序序号升序
   */
  async getAll(): Promise<Category[]> {
    const store = this.store;
    if (!store) return [];
    const list: Category[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("category");
      predicates.orderByAsc("sort_order");
      resultSet = await store.query(predicates);
      while (resultSet.goToNextRow()) {
        list.push(this.categoryFromResultSet(resultSet));
      }
    } catch (e) {
      Logger.error(`CategoryDao.getAll failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`CategoryDao error: ${JSON.stringify(e)}`);
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
   * 更新文件夹（名称、颜色、父文件夹、排序），按 id 更新
   */
  async update(cat: Category): Promise<void> {
    const store = this.store;
    if (!store) return;
    try {
      const values: relationalStore.ValuesBucket = {
        name: cat.name,
        color: cat.color,
        parent_id: cat.parentId, // 支持移动到其他文件夹
        sort_order: cat.sortOrder,
      };
      const predicates = new relationalStore.RdbPredicates("category");
      predicates.equalTo("id", cat.id);
      await store.update(values, predicates);
    } catch (e) {
      Logger.error(`CategoryDao.update failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`CategoryDao error: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 按父文件夹查询子文件夹；parentId 传空串查顶级文件夹
   */
  async getByParent(parentId: string): Promise<Category[]> {
    const store = this.store;
    if (!store) return [];
    const list: Category[] = [];
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates("category");
      predicates.equalTo("parent_id", parentId);
      predicates.orderByAsc("sort_order");
      resultSet = await store.query(predicates);
      while (resultSet.goToNextRow()) {
        list.push(this.categoryFromResultSet(resultSet));
      }
    } catch (e) {
      Logger.error(`CategoryDao.getByParent failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`CategoryDao error: ${JSON.stringify(e)}`);
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
   * 按 id 批量删除文件夹（不含子孙收集与对话清理，由 Repository 事务内处理）
   */
  async deleteByIds(ids: string[]): Promise<void> {
    const store = this.store;
    if (!store || ids.length === 0) return;
    try {
      const predicates = new relationalStore.RdbPredicates("category");
      predicates.in("id", ids);
      await store.delete(predicates);
    } catch (e) {
      Logger.error(`CategoryDao.deleteByIds failed: ${JSON.stringify(e)}`);
      // ArkTS 限制只能抛 Error 类型，包装后上抛，由 Repository 捕获（事务回滚）
      throw new Error(`CategoryDao error: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 收集某文件夹及其全部子孙文件夹的 id（移动时排除循环目标 / 级联删除范围）
   */
  async getSubtreeIds(id: string): Promise<string[]> {
    const result: string[] = [];
    await this.collectCategoryIds(id, result);
    return result;
  }

  // 递归收集文件夹及其子孙文件夹 id（私有辅助）
  private async collectCategoryIds(id: string, result: string[]): Promise<void> {
    result.push(id);
    const children = await this.getByParent(id);
    for (const child of children) {
      await this.collectCategoryIds(child.id, result);
    }
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
