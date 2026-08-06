/**
 * 文件夹页 ViewModel（状态管理 V2）
 * 承载 FolderPage 的数据与业务逻辑：
 *   - 当前文件夹的子文件夹 + 对话加载
 *   - 新建子文件夹 / 编辑（重命名+改色）/ 删除（级联）
 *   - 移动文件夹 / 移动对话 / 重命名对话 / 删除对话 / 取消收藏
 *
 * 页面（FolderPage）只保留：build 布局、路由参数读取、路由跳转、
 * 弹窗打开/关闭（openCustomDialog + @Builder）、删除二次确认弹窗
 */

import { ConversationRepository } from "../database/RepositoryConversation";
import { CategoryRepository } from "../database/RepositoryCategory";
import { Conversation } from "../model/Conversation";
import { Category } from "../model/Category";
import { showToast } from "../common/Utils";
import { moveCategoryTo, moveConversationTo, saveCategoryEdit } from "../common/FolderOps";

@ObservedV2
export class FolderViewModel {
  // ===== UI 可观察状态（@Trace：页面 build 中读取，变化时自动刷新） =====
  @Trace folderId: string = ""; // 当前文件夹 id
  @Trace folderName: string = ""; // 当前文件夹名称
  @Trace subFolders: Category[] = []; // 子文件夹列表
  @Trace convs: Conversation[] = []; // 该文件夹下的对话列表
  @Trace listVersion: number = 0; // 列表刷新版本号：重命名/改色等键不变的内容变更后自增，强制 ForEach 重建

  // ===== 路由参数与数据加载 =====

  // 设置路由参数（页面 aboutToAppear 调用）
  setParams(folderId: string, folderName: string): void {
    this.folderId = folderId;
    this.folderName = folderName;
  }

  // 加载当前文件夹的数据：子文件夹 + 该文件夹下的对话
  async loadData(): Promise<void> {
    this.subFolders = await CategoryRepository.getInstance().getByParent(this.folderId);
    this.convs = await ConversationRepository.getInstance().getByCategory(this.folderId);
  }

  // ===== 文件夹操作 =====

  // 执行新建子文件夹
  async createSubFolder(name: string): Promise<void> {
    const cat = new Category(undefined, name, this.folderId);
    await CategoryRepository.getInstance().insert(cat);
    await this.loadData();
    showToast(`已创建「${name}」`);
  }

  // 执行编辑子文件夹：重命名 + 切换图标颜色
  async saveEdit(cat: Category, name: string, color: string): Promise<void> {
    await saveCategoryEdit(cat, name, color); // 更新名称与颜色并持久化
    await this.loadData();
    this.listVersion++; // 强制 ForEach 重建，刷新名称/颜色
    showToast($r('app.string.saved'));
  }

  // 执行删除文件夹（级联）
  async deleteFolderCascade(id: string): Promise<void> {
    await CategoryRepository.getInstance().deleteCategoryCascade(id);
    await this.loadData();
    showToast($r('app.string.folder_deleted'));
  }

  // 执行移动文件夹：更新 parentId 并刷新列表
  async moveFolder(cat: Category, targetId: string): Promise<void> {
    await moveCategoryTo(cat, targetId); // 空串 = 移到顶级
    await this.loadData();
    showToast(targetId.length > 0 ? $r('app.string.moved') : $r('app.string.moved_to_top'));
  }

  // ===== 对话操作 =====

  // 执行移动对话：更新分类，移出当前文件夹则从列表移除
  async moveConv(conv: Conversation, folderId: string): Promise<void> {
    await moveConversationTo(conv, folderId);
    // 若移出的目标不是当前文件夹 → 从当前列表移除
    if (folderId !== this.folderId) {
      this.convs = this.convs.filter((c: Conversation) => c.id !== conv.id);
    }
    showToast($r('app.string.moved_ok'));
  }

  // 执行重命名对话
  async renameConv(conv: Conversation, name: string): Promise<void> {
    conv.title = name;
    await ConversationRepository.getInstance().update(conv);
    this.listVersion++; // 强制 ForEach 重建，刷新对话标题
    showToast($r('app.string.rename_conv_success'));
  }

  // 执行删除对话
  async deleteConv(id: string): Promise<void> {
    await ConversationRepository.getInstance().deleteConversations([id]);
    this.convs = this.convs.filter((c: Conversation) => c.id !== id);
    showToast($r('app.string.deleted'));
  }

  // 取消收藏：清空收藏标记与位置，并从当前文件夹移除（未收藏对话不参与文件夹分类）
  async unfavorite(conv: Conversation): Promise<void> {
    await ConversationRepository.getInstance().setFavorite(conv, false);
    conv.isFavorite = false;
    conv.categoryId = "";
    // 从当前文件夹对话列表移除（对话不再属于任何文件夹）
    this.convs = this.convs.filter((c: Conversation) => c.id !== conv.id);
    this.listVersion++;
    showToast($r('app.string.unfavorited'));
  }
}