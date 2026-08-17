/**
 * 侧边栏页 ViewModel（状态管理 V2）
 * 承载 SideBarPage 的数据与业务逻辑：
 *   - 历史对话加载 / 时间分组（搜索已独立到 SearchPage / SearchViewModel）
 *   - 收藏 Tab 数据（顶级文件夹 + 未分类收藏对话）
 *   - 多选编辑模式（选中集合、全选、批量删除/移动）
 *   - 重命名 / 收藏 / 取消收藏 / 移动 / 删除
 *
 * 页面（SideBarPage）只保留：build 布局、Tab 滑动动画、路由跳转、
 * 弹窗打开/关闭（openCustomDialog + @Builder）、删除二次确认弹窗
 */

import { ConversationRepository } from "../database/ConversationRepository";
import { CategoryRepository } from "../database/CategoryRepository";
import { Conversation } from "../model/Conversation";
import { Category } from "../model/Category";
import { getGroupName } from "../common/TimeUtil";
import { showToast } from "../common/Utils";
import { ChatViewModel } from "./ChatViewModel";

/* 时间分组项：一组对话 */
export interface GroupItem {
  name: string; // 组名：今天 / 昨天 / 7天内 / 30天内 / xxxx年x月
  conversations: Conversation[]; // 该组下的对话列表
}

@ObservedV2
export class SideBarViewModel {
  /* UI 可观察状态（@Trace：页面 build 中读取，变化时自动刷新） */
  @Trace currentTab: number = 0; // 当前 Tab：0=历史 1=收藏（默认历史）
  @Trace conversations: Conversation[] = []; // 全量对话（历史Tab数据源）
  @Trace groups: GroupItem[] = []; // 分组后的对话（渲染数据源）
  @Trace topFolders: Category[] = []; // 顶级文件夹列表（收藏 Tab）
  @Trace uncategorizedConvs: Conversation[] = []; // 未分类对话列表（收藏 Tab）
  @Trace isEditMode: boolean = false; // 多选编辑模式
  @Trace selectedIds: string[] = []; // 已选中对话 ID
  @Trace listVersion: number = 0; // 列表刷新版本号：重命名/改色等键不变的内容变更后自增，强制 ForEach 重建

  /* 数据加载 */

  /* 从数据库查询全部对话（按更新时间倒序）并重新分组 */
  async loadConversations(): Promise<void> {
    const list = await ConversationRepository.getInstance().getAll();
    this.conversations = list;
    this.rebuildGroups();
  }

  /**
   * 重新构建历史对话分组（搜索独立到 SearchPage，此处为全量分组）
   * 规则：对话先按 updatedAt 倒序，再归入 今天/昨天/7天内/30天内/年月 各组
   */
  rebuildGroups(): void {
    this.groups = this.buildGroups(this.conversations);
  }

  /* 公共分组逻辑：按更新时间倒序后归入 今天/昨天/7天内/30天内/年月 各组 */
  private buildGroups(list: Conversation[]): GroupItem[] {
    /* 1. 按更新时间倒序 */
    const sorted = list
      .slice()
      .sort((a: Conversation, b: Conversation) => b.updatedAt - a.updatedAt);

    /* 2. 遍历分组（保持各组出现顺序：今天 → 昨天 → 7天内 → 30天内 → 年月） */
    const result: GroupItem[] = [];
    const groupIndexMap: Map<string, number> = new Map(); // 组名 → 在 result 中的下标
    sorted.forEach((conv: Conversation) => {
      const name = getGroupName(conv.updatedAt);
      const idx = groupIndexMap.get(name);
      if (idx === undefined) {
        groupIndexMap.set(name, result.length);
        result.push({ name: name, conversations: [conv] });
      } else {
        result[idx].conversations.push(conv);
      }
    });
    return result;
  }

  /* 加载收藏 Tab 数据：顶级文件夹 + 已收藏但未放入文件夹的对话 */
  async loadFavorites(): Promise<void> {
    /* 顶级文件夹：parent_id 为空 */
    this.topFolders = await CategoryRepository.getInstance().getByParent("");
    /* 未分类收藏对话：已收藏（is_favorite=1）且 category_id 为空 */
    const favorites = await ConversationRepository.getInstance().getFavorites();
    this.uncategorizedConvs = favorites.filter((c: Conversation) => c.categoryId.length === 0);
  }

  /* Tab 与选中 */

  /* 顶部 Tab 点击：更新高亮状态（页面负责 Swiper 带动画切换） */
  setCurrentTab(index: number): void {
    this.currentTab = index;
  }

  /* 多选编辑模式 */

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

  /**
   * 当前可见对话（供全选使用）：
   * 收藏 Tab 的可见集合是「未分类收藏对话」；若仍拍平历史分组，
   * 在收藏 Tab 点「全选 → 删除」会把全部历史对话（含未收藏）误删
   */
  private getAllVisible(): Conversation[] {
    if (this.currentTab === 1) {
      return this.uncategorizedConvs.slice();
    }
    const result: Conversation[] = [];
    this.groups.forEach((g: GroupItem) =>
      g.conversations.forEach((c: Conversation) => result.push(c)),
    );
    return result;
  }

  isAllSelected(): boolean {
    const visible = this.getAllVisible();
    if (visible.length === 0) return false;
    /* 按成员逐一校验，避免陈旧/跨 Tab id 造成全选判定错误 */
    return visible.every((c: Conversation) => this.selectedIds.indexOf(c.id) >= 0)
      && this.selectedIds.length === visible.length;
  }

  toggleSelectAll(): void {
    const visible = this.getAllVisible();
    /* 选中集 = 当前 Tab 可见集合本身（覆盖赋值，同时清除任何陈旧/跨 Tab 的 id） */
    if (visible.length > 0 && visible.every((c: Conversation) => this.selectedIds.indexOf(c.id) >= 0)) {
      this.selectedIds = [];
    } else {
      this.selectedIds = visible.map((c: Conversation) => c.id);
    }
  }

  /* 对话操作 */

  /* 执行重命名：更新内存 + 数据库 */
  async doRename(id: string, newTitle: string): Promise<void> {
    const conv = this.conversations.find((c: Conversation) => c.id === id);
    if (!conv) return;
    const oldTitle = conv.title;
    conv.title = newTitle;
    const ok = await ConversationRepository.getInstance().update(conv);
    if (!ok) {
      conv.title = oldTitle; // 失败回滚内存，避免界面与数据库不一致
      showToast("操作失败，请重试");
      return;
    }
    /* DB 重载收藏 Tab（uncategorizedConvs 与历史列表可能是不同实例，统一以数据库为准） */
    await this.loadFavorites();
    this.rebuildGroups(); // 搜索态下改名后立即重算分组，保持过滤结果与标题一致
    this.listVersion++; // 强制 ForEach 重建，刷新对话标题
    showToast($r('app.string.rename_success'));
  }

  /* 执行收藏：置 is_favorite=1 并写入收藏位置 */
  async doFavorite(conv: Conversation, folderId: string): Promise<void> {
    const oldFav = conv.isFavorite;
    const oldCat = conv.categoryId;
    conv.isFavorite = true;
    conv.categoryId = folderId;
    const ok = await ConversationRepository.getInstance().setFavorite(conv, true);
    if (!ok) {
      conv.isFavorite = oldFav; // 失败回滚内存
      conv.categoryId = oldCat;
      showToast("操作失败，请重试");
      return;
    }
    /* DB 重载：历史列表与收藏列表统一以数据库为准，消除跨列表实例手动同步 */
    await this.loadConversations();
    await this.loadFavorites();
    this.listVersion++; // 强制 ForEach 重建：星标出现、菜单变为"取消收藏"
    showToast($r('app.string.favorited'));
  }

  /* 执行取消收藏：置 is_favorite=0、清空收藏位置，并从收藏列表移除 */
  async doUnfavorite(conv: Conversation): Promise<void> {
    const oldFav = conv.isFavorite;
    const oldCat = conv.categoryId;
    const ok = await ConversationRepository.getInstance().setFavorite(conv, false); // 同时清空 categoryId
    if (!ok) {
      conv.isFavorite = oldFav; // 失败回滚内存
      conv.categoryId = oldCat;
      showToast("操作失败，请重试");
      return;
    }
    /* DB 重载：历史列表与收藏列表统一以数据库为准，消除跨列表实例手动同步 */
    await this.loadConversations();
    await this.loadFavorites();
    this.listVersion++; // 强制 ForEach 重建：星标消失、菜单变回"收藏"
    showToast($r('app.string.unfavorited'));
  }

  /* 执行置顶/取消置顶（对话）：切换标记、DB 持久化、失败回滚，重载排序 */
  async togglePinConv(conv: Conversation): Promise<void> {
    const oldPin = conv.isPinned;
    conv.isPinned = !oldPin;
    const ok = await ConversationRepository.getInstance().setPinned(conv, conv.isPinned);
    if (!ok) {
      conv.isPinned = oldPin; // 失败回滚内存
      showToast("操作失败，请重试");
      return;
    }
    await this.loadFavorites(); // DB 重载：置顶对话自动排到顶部
    this.listVersion++; // 强制 ForEach 重建：置顶图标出现、菜单文案切换
    showToast(conv.isPinned ? "已置顶" : "已取消置顶");
  }

  /* 执行置顶/取消置顶（文件夹）：同上 */
  async togglePinFolder(cat: Category): Promise<void> {
    const oldPin = cat.isPinned;
    cat.isPinned = !oldPin;
    const ok = await CategoryRepository.getInstance().setPinned(cat, cat.isPinned);
    if (!ok) {
      cat.isPinned = oldPin;
      showToast("操作失败，请重试");
      return;
    }
    await this.loadFavorites();
    this.listVersion++;
    showToast(cat.isPinned ? "已置顶" : "已取消置顶");
  }

  /* 执行移动文件夹：更新 parentId 并刷新列表 */
  async doMoveFolder(cat: Category, targetId: string): Promise<void> {
    const oldParent = cat.parentId;
    const ok = await CategoryRepository.getInstance().moveTo(cat, targetId); // 空串 = 移到顶级
    if (!ok) {
      cat.parentId = oldParent; // 失败回滚内存
      showToast("操作失败，请重试");
      return;
    }
    await this.loadFavorites();
    showToast(targetId.length > 0 ? $r('app.string.moved') : $r('app.string.moved_to_top'));
  }

  /* 执行移动对话：更新分类并刷新列表 */
  async doMoveConv(conv: Conversation, folderId: string): Promise<void> {
    const oldCat = conv.categoryId;
    const oldFav = conv.isFavorite;
    const ok = await ConversationRepository.getInstance().moveTo(conv, folderId);
    if (!ok) {
      conv.categoryId = oldCat; // 失败回滚内存
      conv.isFavorite = oldFav;
      showToast("操作失败，请重试");
      return;
    }
    /* DB 重载：历史列表与收藏列表统一以数据库为准 */
    await this.loadConversations();
    await this.loadFavorites();
    showToast($r('app.string.moved_ok'));
  }

  /* 执行批量移动：选中对话统一移入目标文件夹，然后退出编辑模式并刷新 */
  async doBatchMove(folderId: string): Promise<void> {
    const ids = this.selectedIds.slice(); // 先拷贝，避免退出编辑模式时被清空
    const ok = await ConversationRepository.getInstance().move(ids, folderId);
    this.exitEditMode();
    if (!ok) {
      showToast("操作失败，请重试");
      return;
    }
    /* DB 重载：历史列表与收藏列表统一以数据库为准 */
    await this.loadConversations();
    await this.loadFavorites();
    showToast(folderId.length > 0 ? `已移动 ${ids.length} 个对话` : $r('app.string.moved_out'));
  }

  /* 执行批量取消收藏：选中对话置 is_favorite=0 并清空分类，退出编辑模式后重载 */
  async doBatchUnfavorite(): Promise<void> {
    const ids = this.selectedIds.slice(); // 先拷贝，避免退出编辑模式时被清空
    this.exitEditMode();
    const ok = await ConversationRepository.getInstance().unfavoriteByIds(ids);
    if (!ok) {
      showToast("操作失败，请重试");
      return;
    }
    /* DB 重载：历史列表与收藏列表统一以数据库为准 */
    await this.loadConversations();
    await this.loadFavorites();
    this.listVersion++;
    showToast(`已取消收藏 ${ids.length} 个对话`);
  }

  /* 执行删除：先拷贝 id，再删除 → 退出编辑模式 → DB 重载 */
  async doDelete(ids: string[]): Promise<void> {
    this.exitEditMode();
    const ok = await ConversationRepository.getInstance().deleteConversations(ids);
    if (!ok) {
      showToast("操作失败，请重试");
      return;
    }
    /* 删除对话时同步中止并清理其流任务（后台流/保活计数随之释放） */
    const chatVm = ChatViewModel.getInstance();
    if (chatVm !== null) {
      chatVm.abortTasksOfConversations(ids);
    }
    /* DB 重载：历史列表、分组、收藏列表统一以数据库为准，消除多处内存同步 */
    await this.loadConversations();
    await this.loadFavorites();
    this.listVersion++;
    showToast(`已删除 ${ids.length} 个对话`);
  }

  /* 执行删除文件夹（级联）：文件夹下对话的分类会被清空（clearCategory） */
  async doDeleteFolder(id: string): Promise<void> {
    const ok = await CategoryRepository.getInstance().deleteCategoryCascade(id);
    if (!ok) {
      showToast("操作失败，请重试");
      return;
    }
    /* DB 重载：历史列表（对话分类变化）与收藏列表统一以数据库为准 */
    await this.loadConversations();
    await this.loadFavorites();
    showToast($r('app.string.folder_deleted'));
  }

  /* 执行新建顶级文件夹 */
  async createFolder(name: string, color: string): Promise<void> {
    const cat = new Category(undefined, name, undefined, color); // 颜色一并入库
    const ok = await CategoryRepository.getInstance().insert(cat);
    if (!ok) {
      showToast("操作失败，请重试");
      return;
    }
    await this.loadFavorites();
    showToast(`已创建 ${name}`);
  }

  /* 执行编辑文件夹：重命名 + 切换图标颜色 */
  async saveEdit(cat: Category, name: string, color: string): Promise<void> {
    const oldName = cat.name;
    const oldColor = cat.color;
    const ok = await CategoryRepository.getInstance().updateInfo(cat, name, color);
    if (!ok) {
      cat.name = oldName; // 失败回滚内存
      cat.color = oldColor;
      showToast("操作失败，请重试");
      return;
    }
    await this.loadFavorites();
    this.listVersion++; // 强制 ForEach 重建，刷新名称/颜色
    showToast($r('app.string.saved'));
  }
}