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
import { showToast, getGlobalUiContext } from "../common/Utils";
import { ChatViewModel } from "./ChatViewModel";

@ObservedV2
export class FolderViewModel {
  /* UI 可观察状态（@Trace：页面 build 中读取，变化时自动刷新） */
  @Trace folderId: string = ""; // 当前文件夹 id
  @Trace folderName: string = ""; // 当前文件夹名称
  @Trace subFolders: Category[] = []; // 子文件夹列表
  @Trace convs: Conversation[] = []; // 该文件夹下的对话列表
  @Trace listVersion: number = 0; // 列表刷新版本号：重命名/改色等键不变的内容变更后自增，强制 ForEach 重建
  @Trace isEditMode: boolean = false; // 多选编辑模式
  @Trace selectedIds: string[] = []; // 已选中对话 ID

  /* 路由参数与数据加载 */

  /* 设置路由参数（页面 aboutToAppear 调用） */
  setParams(folderId: string, folderName: string): void {
    this.folderId = folderId;
    this.folderName = folderName;
  }

  /* 加载当前文件夹的数据：子文件夹 + 该文件夹下的对话 */
  async loadData(): Promise<void> {
    this.subFolders = await CategoryRepository.getInstance().getByParent(this.folderId);
    this.convs = await ConversationRepository.getInstance().getByCategory(this.folderId);
  }

  /* 多选编辑模式（与 SideBarPage 收藏 Tab 行为对齐） */

  /* 进入多选模式（可预选长按的那一项） */
  enterEditMode(preSelectId: string): void {
    this.isEditMode = true;
    this.selectedIds = preSelectId.length > 0 ? [preSelectId] : [];
  }

  exitEditMode(): void {
    this.isEditMode = false;
    this.selectedIds = [];
  }

  toggleSelect(id: string, checked: boolean): void {
    /* @Trace 数组：用新数组赋值确保 UI 刷新（避免依赖 push/splice 的观察行为） */
    if (checked && this.selectedIds.indexOf(id) < 0) {
      this.selectedIds = this.selectedIds.concat(id);
    } else if (!checked && this.selectedIds.indexOf(id) >= 0) {
      this.selectedIds = this.selectedIds.filter((x: string) => x !== id);
    }
  }

  /* 全选可见集合 = 当前文件夹下的对话（文件夹本身不可多选/取消收藏） */
  private getAllVisible(): Conversation[] {
    return this.convs.slice();
  }

  isAllSelected(): boolean {
    const visible = this.getAllVisible();
    if (visible.length === 0) return false;
    return visible.every((c: Conversation) => this.selectedIds.indexOf(c.id) >= 0)
      && this.selectedIds.length === visible.length;
  }

  toggleSelectAll(): void {
    const visible = this.getAllVisible();
    if (visible.length > 0 && visible.every((c: Conversation) => this.selectedIds.indexOf(c.id) >= 0)) {
      this.selectedIds = [];
    } else {
      this.selectedIds = visible.map((c: Conversation) => c.id);
    }
  }

  /* 文件夹操作 */

  /* 执行新建子文件夹，颜色一并入库（与收藏 Tab 新建文件夹一致） */
  async createSubFolder(name: string, color: string): Promise<void> {
    const cat = new Category(undefined, name, this.folderId, color);
    const ok = await CategoryRepository.getInstance().insert(cat);
    if (!ok) {
      showToast(getGlobalUiContext(), $r('app.string.toast_op_failed'));
      return;
    }
    await this.loadData();
    showToast(getGlobalUiContext(), $r('app.string.toast_created_folder', name));
  }

  /* 执行编辑子文件夹：重命名 + 切换图标颜色 */
  async saveEdit(cat: Category, name: string, color: string): Promise<void> {
    const oldName = cat.name;
    const oldColor = cat.color;
    const ok = await CategoryRepository.getInstance().updateInfo(cat, name, color);
    if (!ok) {
      cat.name = oldName; // 失败回滚内存
      cat.color = oldColor;
      showToast(getGlobalUiContext(), $r('app.string.toast_op_failed'));
      return;
    }
    await this.loadData();
    this.listVersion++; // 强制 ForEach 重建，刷新名称/颜色
    showToast(getGlobalUiContext(), $r('app.string.saved'));
  }

  /* 执行置顶/取消置顶（文件夹）：切换标记、DB 持久化、失败回滚，重载排序 */
  async togglePinFolder(cat: Category): Promise<void> {
    const oldPin = cat.isPinned;
    cat.isPinned = !oldPin;
    const ok = await CategoryRepository.getInstance().setPinned(cat, cat.isPinned);
    if (!ok) {
      cat.isPinned = oldPin;
      showToast(getGlobalUiContext(), $r('app.string.toast_op_failed'));
      return;
    }
    await this.loadData(); // 重载：置顶文件夹排到当前文件夹列表顶部
    this.listVersion++;
    showToast(getGlobalUiContext(), cat.isPinned ? $r('app.string.toast_pinned') : $r('app.string.toast_unpinned'));
  }

  /* 执行删除文件夹（级联） */
  async deleteFolderCascade(id: string): Promise<void> {
    const ok = await CategoryRepository.getInstance().deleteCategoryCascade(id);
    if (!ok) {
      showToast(getGlobalUiContext(), $r('app.string.toast_op_failed'));
      return;
    }
    await this.loadData();
    showToast(getGlobalUiContext(), $r('app.string.folder_deleted'));
  }

  /* 执行移动文件夹：更新 parentId 并刷新列表 */
  async moveFolder(cat: Category, targetId: string): Promise<void> {
    const oldParent = cat.parentId;
    const ok = await CategoryRepository.getInstance().moveTo(cat, targetId); // 空串 = 移到顶级
    if (!ok) {
      cat.parentId = oldParent; // 失败回滚内存
      showToast(getGlobalUiContext(), $r('app.string.toast_op_failed'));
      return;
    }
    await this.loadData();
    showToast(getGlobalUiContext(), targetId.length > 0 ? $r('app.string.moved') : $r('app.string.moved_to_top'));
  }

  /* 对话操作 */

  /* 执行移动对话：更新分类，移出当前文件夹则从列表移除 */
  async moveConv(conv: Conversation, folderId: string): Promise<void> {
    const oldCat = conv.categoryId;
    const oldFav = conv.isFavorite;
    const ok = await ConversationRepository.getInstance().moveTo(conv, folderId);
    if (!ok) {
      conv.categoryId = oldCat; // 失败回滚内存
      conv.isFavorite = oldFav;
      showToast(getGlobalUiContext(), $r('app.string.toast_op_failed'));
      return;
    }
    /* 若移出的目标不是当前文件夹 → 从当前列表移除 */
    if (folderId !== this.folderId) {
      this.convs = this.convs.filter((c: Conversation) => c.id !== conv.id);
    }
    showToast(getGlobalUiContext(), $r('app.string.moved_ok'));
  }

  /* 执行重命名对话 */
  async renameConv(conv: Conversation, name: string): Promise<void> {
    const oldTitle = conv.title;
    conv.title = name;
    conv.isUserNamed = true; // 用户手动命名：此后不再自动生成 AI 标题
    const ok = await ConversationRepository.getInstance().update(conv);
    if (!ok) {
      conv.title = oldTitle; // 失败回滚内存
      showToast(getGlobalUiContext(), $r('app.string.toast_op_failed'));
      return;
    }
    this.listVersion++; // 强制 ForEach 重建，刷新对话标题
    showToast(getGlobalUiContext(), $r('app.string.rename_conv_success'));
  }

  /* 执行置顶/取消置顶（对话）：切换标记、DB 持久化、失败回滚，重载排序 */
  async togglePinConv(conv: Conversation): Promise<void> {
    const oldPin = conv.isPinned;
    conv.isPinned = !oldPin;
    const ok = await ConversationRepository.getInstance().setPinned(conv, conv.isPinned);
    if (!ok) {
      conv.isPinned = oldPin;
      showToast(getGlobalUiContext(), $r('app.string.toast_op_failed'));
      return;
    }
    await this.loadData(); // 重载：置顶对话排到当前文件夹列表顶部
    this.listVersion++;
    showToast(getGlobalUiContext(), conv.isPinned ? $r('app.string.toast_pinned') : $r('app.string.toast_unpinned'));
  }

  /* 执行删除对话 */
  async deleteConv(id: string): Promise<void> {
    const ok = await ConversationRepository.getInstance().deleteConversations([id]);
    if (!ok) {
      showToast(getGlobalUiContext(), $r('app.string.toast_op_failed'));
      return;
    }
    /* 删除对话时同步中止并清理其流任务（与侧边栏 doDelete 对齐，避免后台流/保活泄漏） */
    const chatVm = ChatViewModel.getInstance();
    if (chatVm !== null) {
      chatVm.abortTasksOfConversations([id]);
    }
    this.convs = this.convs.filter((c: Conversation) => c.id !== id);
    showToast(getGlobalUiContext(), $r('app.string.deleted'));
  }

  /* 取消收藏：清空收藏标记与位置，并从当前文件夹移除（未收藏对话不参与文件夹分类） */
  async unfavorite(conv: Conversation): Promise<void> {
    const oldFav = conv.isFavorite;
    const oldCat = conv.categoryId;
    const ok = await ConversationRepository.getInstance().setFavorite(conv, false);
    if (!ok) {
      conv.isFavorite = oldFav; // 失败回滚内存
      conv.categoryId = oldCat;
      showToast(getGlobalUiContext(), $r('app.string.toast_op_failed'));
      return;
    }
    conv.isFavorite = false;
    conv.categoryId = "";
    /* 从当前文件夹对话列表移除（对话不再属于任何文件夹） */
    this.convs = this.convs.filter((c: Conversation) => c.id !== conv.id);
    this.listVersion++;
    showToast(getGlobalUiContext(), $r('app.string.unfavorited'));
  }

  /* 批量操作（多选编辑模式） */

  /* 执行批量取消收藏：退出编辑模式后重载列表，选中对话不再属于当前文件夹 */
  async doBatchUnfavorite(): Promise<void> {
    const ids = this.selectedIds.slice(); // 先拷贝，避免退出编辑模式时被清空
    this.exitEditMode();
    const ok = await ConversationRepository.getInstance().unfavoriteByIds(ids);
    if (!ok) {
      showToast(getGlobalUiContext(), $r('app.string.toast_op_failed'));
      return;
    }
    await this.loadData();
    this.listVersion++;
    showToast(getGlobalUiContext(), $r('app.string.toast_unfavorited_n', ids.length));
  }

  /* 执行批量删除：退出编辑模式后重载列表，并同步中止删除对话的流任务 */
  async doBatchDelete(): Promise<void> {
    const ids = this.selectedIds.slice(); // 先拷贝，避免退出编辑模式时被清空
    this.exitEditMode();
    const ok = await ConversationRepository.getInstance().deleteConversations(ids);
    if (!ok) {
      showToast(getGlobalUiContext(), $r('app.string.toast_op_failed'));
      return;
    }
    const chatVm = ChatViewModel.getInstance();
    if (chatVm !== null) {
      chatVm.abortTasksOfConversations(ids);
    }
    await this.loadData();
    this.listVersion++;
    showToast(getGlobalUiContext(), $r('app.string.toast_deleted_n', ids.length));
  }

  /* 执行批量移动：选中对话统一移入目标文件夹，退出编辑模式后重载 */
  async doBatchMove(folderId: string): Promise<void> {
    const ids = this.selectedIds.slice(); // 先拷贝，避免退出编辑模式时被清空
    this.exitEditMode();
    const ok = await ConversationRepository.getInstance().move(ids, folderId);
    if (!ok) {
      showToast(getGlobalUiContext(), $r('app.string.toast_op_failed'));
      return;
    }
    await this.loadData();
    this.listVersion++;
    showToast(getGlobalUiContext(), folderId.length > 0 ? $r('app.string.toast_moved_n', ids.length) : $r('app.string.moved_out'));
  }
}