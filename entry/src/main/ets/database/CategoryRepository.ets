/**
 * 文件夹树 聚合仓库（Repository）
 *
 * 职责：
 *   1. 作为页面访问文件夹数据的唯一入口（页面不直接触碰 DAO）
 *   2. 承载级联删除事务（跨 category / conversation 表）：
 *      deleteCategoryCascade：递归收集子孙 → 清空对话分类 → 删除文件夹（事务，中断自动回滚）
 *   3. 查询方法统一吞掉 DAO 异常并返回默认值（页面无需感知）
 */

import { relationalStore } from "@kit.ArkData";
import { Category } from "../model/Category";
import { DatabaseHelper } from "./DatabaseHelper";
import { CategoryDao } from "./CategoryDao";
import { ConversationDao } from "./ConversationDao";
import { Logger } from "../common/Logger";

export class CategoryRepository {
  private static instance: CategoryRepository;

  private constructor() {}

  static getInstance(): CategoryRepository {
    if (!CategoryRepository.instance) {
      CategoryRepository.instance = new CategoryRepository();
    }
    return CategoryRepository.instance;
  }

  // 共享 RdbStore（init 完成前为 undefined）
  private get store(): relationalStore.RdbStore | undefined {
    return DatabaseHelper.getInstance().getStore();
  }

  // 查询全部分类，按排序序号升序
  async getAll(): Promise<Category[]> {
    try {
      return await CategoryDao.getInstance().getAll();
    } catch (e) {
      Logger.error(`CategoryRepository.getAll failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  // 按父文件夹查询子文件夹；parentId 传空串查顶级文件夹
  async getByParent(parentId: string): Promise<Category[]> {
    try {
      return await CategoryDao.getInstance().getByParent(parentId);
    } catch (e) {
      Logger.error(`CategoryRepository.getByParent failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  // 新增分类（返回是否成功，失败由调用方提示用户）
  async insert(cat: Category): Promise<boolean> {
    try {
      await CategoryDao.getInstance().insert(cat);
      return true;
    } catch (e) {
      Logger.error(`CategoryRepository.insert failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  // 更新文件夹（名称、颜色、父文件夹、排序）（返回是否成功）
  async update(cat: Category): Promise<boolean> {
    try {
      await CategoryDao.getInstance().update(cat);
      return true;
    } catch (e) {
      Logger.error(`CategoryRepository.update failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /**
   * 移动文件夹：更新 parentId 并持久化（阶段七：由 common/FolderOps.moveCategoryTo 下沉）
   * @param cat 被移动的文件夹（@Observed，直接改字段即可驱动 UI）
   * @param targetId 目标父文件夹 id，空串 = 移到顶级
   */
  async moveTo(cat: Category, targetId: string): Promise<boolean> {
    cat.parentId = targetId; // 空串 = 移到顶级
    return this.update(cat);
  }

  /**
   * 编辑文件夹：更新名称与颜色并持久化（阶段七：由 common/FolderOps.saveCategoryEdit 下沉）
   * @param cat 被编辑的文件夹
   * @param name 新名称
   * @param color 新颜色
   */
  async updateInfo(cat: Category, name: string, color: string): Promise<boolean> {
    cat.name = name;
    cat.color = color; // 更新图标颜色
    return this.update(cat);
  }

  /**
   * 计算"移动文件夹"的候选目标列表（阶段七：由 common/FolderOps.getMoveFolderCandidates 下沉）
   * 规则：全部文件夹 - 自身及子孙（防止成环；空串"不分类"由选择器提供，表示移到顶级）
   * @param catId 被移动的文件夹 id
   */
  async getMoveCandidates(catId: string): Promise<Category[]> {
    const all = await this.getAll();
    const exclude = await this.getSubtreeIds(catId);
    // 候选目标 = 全部文件夹 - 自身及子孙
    return all.filter((c: Category) => exclude.indexOf(c.id) < 0);
  }

  // 收集某文件夹及其全部子孙文件夹的 id（移动文件夹时排除循环目标）
  async getSubtreeIds(id: string): Promise<string[]> {
    try {
      return await CategoryDao.getInstance().getSubtreeIds(id);
    } catch (e) {
      Logger.error(`CategoryRepository.getSubtreeIds failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  /**
   * 级联删除文件夹：删除自身 + 所有子孙文件夹 + 清空相关对话的分类
   * 跨表事务：中断自动回滚，避免"文件夹删了但对话分类没清"的半删状态
   */
  async deleteCategoryCascade(id: string): Promise<boolean> {
    const store = this.store;
    if (!store) return false;
    store.beginTransaction(); // 开启事务
    try {
      // 1. 递归收集所有要删除的文件夹 id（含自身与子孙）
      const toDelete = await CategoryDao.getInstance().getSubtreeIds(id);
      if (toDelete.length > 0) {
        // 2. 这些文件夹下的对话设为未分类（category_id 清空，不删对话）
        await ConversationDao.getInstance().clearCategory(toDelete);
        // 3. 删除文件夹记录（含子文件夹）
        await CategoryDao.getInstance().deleteByIds(toDelete);
      }
      store.commit(); // 全部成功才提交（空集合也正常提交）
      return true;
    } catch (e) {
      store.rollBack(); // 任一失败回滚，避免"文件夹删了但对话分类没清"的半删状态
      Logger.error(`CategoryRepository.deleteCategoryCascade failed: ${JSON.stringify(e)}`);
      return false;
    }
  }
}
