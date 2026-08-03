/**
 * 文件夹/对话公共操作
 * 集中管理 SideBarPage 与 FolderPage 中重复的移动、编辑等数据操作
 * 依赖模型与数据库，仅供页面层调用
 */

import { Category } from "../model/Category";
import { Conversation } from "../model/Conversation";
import { DatabaseHelper } from "../database/DatabaseHelper";

/**
 * 计算"移动文件夹"的候选目标列表
 * 规则：全部文件夹 - 自身及子孙（防止成环；空串"不分类"由选择器提供，表示移到顶级）
 * @param catId 被移动的文件夹 id
 */
export async function getMoveFolderCandidates(catId: string): Promise<Category[]> {
  const all = await DatabaseHelper.getInstance().getCategories();
  const exclude = await DatabaseHelper.getInstance().getCategorySubtreeIds(catId);
  // 候选目标 = 全部文件夹 - 自身及子孙
  return all.filter((c: Category) => exclude.indexOf(c.id) < 0);
}

/**
 * 执行移动文件夹：更新 parentId 并持久化
 * @param cat 被移动的文件夹（@Observed，直接改字段即可驱动 UI）
 * @param targetId 目标父文件夹 id，空串 = 移到顶级
 */
export async function moveCategoryTo(cat: Category, targetId: string): Promise<void> {
  cat.parentId = targetId; // 空串 = 移到顶级
  await DatabaseHelper.getInstance().updateCategory(cat);
}

/**
 * 执行移动对话：更新分类并持久化
 * @param conv 被移动的对话（@Observed，直接改字段即可驱动 UI）
 * @param folderId 目标文件夹 id，空串 = 移出不分类
 */
export async function moveConversationTo(conv: Conversation, folderId: string): Promise<void> {
  conv.categoryId = folderId;
  await DatabaseHelper.getInstance().updateConversation(conv);
}

/**
 * 保存文件夹编辑：更新名称与颜色并持久化
 * @param cat 被编辑的文件夹
 * @param name 新名称
 * @param color 新颜色
 */
export async function saveCategoryEdit(cat: Category, name: string, color: string): Promise<void> {
  cat.name = name;
  cat.color = color; // 更新图标颜色
  await DatabaseHelper.getInstance().updateCategory(cat);
}
