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

import { ConversationRepository } from "../database/ConversationRepository";
import { CategoryRepository } from "../database/CategoryRepository";
import { Conversation } from "../model/Conversation";
import { Category } from "../model/Category";
import { showToast } from "../common/Utils";

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

  // 文件夹操作

  // 执行新建子文件夹（失败提示）
  async createSubFolder(name: string): Promise<void> {
    const cat = new Category(undefined, name, this.folderId);
    const ok = await CategoryRepository.getInstance().insert(cat);
    if (!ok) {
      showToast("操作失败，请重试");
      return;
    }
    await this.loadData();
    showToast(`已创建「${name}」`);
  }

  // 执行编辑子文件夹：重命名 + 切换图标颜色（失败回滚内存并提示）
  async saveEdit(cat: Category, name: string, color: string): Promise<void> {
    const oldName = cat.name;
    const oldColor = cat.color;
    const ok = await CategoryRepository.getInstance().updateInfo(cat, name, color); // 更新名称与颜色并持久化
    if (!ok) {
      cat.name = oldName; // 失败回滚内存
      cat.color = oldColor;
      showToast("操作失败，请重试");
      return;
    }
    await this.loadData();
    this.listVersion++; // 强制 ForEach 重建，刷新名称/颜色
    showToast($r('app.string.saved'));
  }

  // 执行删除文件夹（级联）（失败提示）
  async deleteFolderCascade(id: string): Promise<void> {
    const ok = await CategoryRepository.getInstance().deleteCategoryCascade(id);
    if (!ok) {
      showToast("操作失败，请重试");
      return;
    }
    await this.loadData();
    showToast($r('app.string.folder_deleted'));
  }

  // 执行移动文件夹：更新 parentId 并刷新列表（失败回滚内存并提示）
  async moveFolder(cat: Category, targetId: string): Promise<void> {
    const oldParent = cat.parentId;
    const ok = await CategoryRepository.getInstance().moveTo(cat, targetId); // 空串 = 移到顶级
    if (!ok) {
      cat.parentId = oldParent; // 失败回滚内存
      showToast("操作失败，请重试");
      return;
    }
    await this.loadData();
    showToast(targetId.length > 0 ? $r('app.string.moved') : $r('app.string.moved_to_top'));
  }

  // 对话操作

  // 执行移动对话：更新分类，移出当前文件夹则从列表移除（失败回滚内存并提示）
  async moveConv(conv: Conversation, folderId: string): Promise<void> {
    const oldCat = conv.categoryId;
    const ok = await ConversationRepository.getInstance().moveTo(conv, folderId);
    if (!ok) {
      conv.categoryId = oldCat; // 失败回滚内存
      showToast("操作失败，请重试");
      return;
    }
    // 若移出的目标不是当前文件夹 → 从当前列表移除
    if (folderId !== this.folderId) {
      this.convs = this.convs.filter((c: Conversation) => c.id !== conv.id);
    }
    showToast($r('app.string.moved_ok'));
  }

  // 执行重命名对话（失败回滚内存并提示）
  async renameConv(conv: Conversation, name: string): Promise<void> {
    const oldTitle = conv.title;
    conv.title = name;
    const ok = await ConversationRepository.getInstance().update(conv);
    if (!ok) {
      conv.title = oldTitle; // 失败回滚内存
      showToast("操作失败，请重试");
      return;
    }
    this.listVersion++; // 强制 ForEach 重建，刷新对话标题
    showToast($r('app.string.rename_conv_success'));
  }

  // 执行删除对话（失败提示）
  async deleteConv(id: string): Promise<void> {
    const ok = await ConversationRepository.getInstance().deleteConversations([id]);
    if (!ok) {
      showToast("操作失败，请重试");
      return;
    }
    this.convs = this.convs.filter((c: Conversation) => c.id !== id);
    showToast($r('app.string.deleted'));
  }

  // 取消收藏：清空收藏标记与位置，并从当前文件夹移除（未收藏对话不参与文件夹分类）（失败回滚内存并提示）
  async unfavorite(conv: Conversation): Promise<void> {
    const oldFav = conv.isFavorite;
    const oldCat = conv.categoryId;
    const ok = await ConversationRepository.getInstance().setFavorite(conv, false);
    if (!ok) {
      conv.isFavorite = oldFav; // 失败回滚内存
      conv.categoryId = oldCat;
      showToast("操作失败，请重试");
      return;
    }
    conv.isFavorite = false;
    conv.categoryId = "";
    // 从当前文件夹对话列表移除（对话不再属于任何文件夹）
    this.convs = this.convs.filter((c: Conversation) => c.id !== conv.id);
    this.listVersion++;
    showToast($r('app.string.unfavorited'));
  }
}