/**
 * 侧边栏页 ViewModel（状态管理 V2）
 * 承载 SideBarPage 的数据与业务逻辑：
 *   - 历史对话加载 / 搜索过滤 / 时间分组
 *   - 收藏 Tab 数据（顶级文件夹 + 未分类收藏对话）
 *   - 多选编辑模式（选中集合、全选、批量删除/移动）
 *   - 重命名 / 收藏 / 取消收藏 / 移动 / 删除
 *
 * 页面（SideBarPage）只保留：build 布局、Tab 滑动动画、路由跳转、
 * 弹窗打开/关闭（openCustomDialog + @Builder）、删除二次确认弹窗
 */

import { ConversationRepository } from "../database/RepositoryConversation";
import { CategoryRepository } from "../database/RepositoryCategory";
import { Conversation } from "../model/Conversation";
import { Category } from "../model/Category";
import { AppConfig } from "../config/AppConfig";
import { getGroupName } from "../common/TimeUtil";
import { showToast } from "../common/Utils";
import { moveCategoryTo, moveConversationTo, saveCategoryEdit } from "../common/FolderOps";

// 时间分组项：一组对话
export interface GroupItem {
  name: string; // 组名：今天 / 昨天 / 7天内 / 30天内 / xxxx年x月
  conversations: Conversation[]; // 该组下的对话列表
}

@ObservedV2
export class SideBarViewModel {
  // ===== UI 可观察状态（@Trace：页面 build 中读取，变化时自动刷新） =====
  @Trace currentTab: number = 0; // 当前 Tab：0=历史 1=收藏（默认历史）
  @Trace conversations: Conversation[] = []; // 全量对话（历史Tab数据源）
  @Trace groups: GroupItem[] = []; // 分组后的对话（渲染数据源）
  @Trace topFolders: Category[] = []; // 顶级文件夹列表（收藏 Tab）
  @Trace uncategorizedConvs: Conversation[] = []; // 未分类对话列表（收藏 Tab）
  @Trace searchText: string = ""; // 搜索关键字
  @Trace isEditMode: boolean = false; // 多选编辑模式
  @Trace selectedIds: string[] = []; // 已选中对话 ID
  @Trace listVersion: number = 0; // 列表刷新版本号：重命名/改色等键不变的内容变更后自增，强制 ForEach 重建

  // ===== 数据加载 =====

  /** 从数据库查询全部对话（按更新时间倒序）并重新分组 */
  async loadConversations(): Promise<void> {
    const list = await ConversationRepository.getInstance().getAll();
    this.conversations = list;
    this.rebuildGroups();
  }

  /**
   * 根据搜索关键字重新构建分组
   * 规则：对话先按 updatedAt 倒序，再归入 今天/昨天/7天内/30天内/年月 各组
   */
  rebuildGroups(): void {
    const keyword = this.searchText.trim().toLowerCase();
    // 1. 过滤（有关键字时按标题匹配）
    const filtered =
      keyword.length === 0
        ? this.conversations
        : this.conversations.filter((c: Conversation) => c.title.toLowerCase().includes(keyword));

    // 2. 按更新时间倒序
    const sorted = filtered
      .slice()
      .sort((a: Conversation, b: Conversation) => b.updatedAt - a.updatedAt);

    // 3. 遍历分组（保持各组出现顺序：今天 → 昨天 → 7天内 → 30天内 → 年月）
    const result: GroupItem[] = [];
    const groupIndexMap: Map<string, number> = new Map(); // 组名 → 在 result 中的下标
    sorted.forEach((conv: Conversation) => {
      const name = getGroupName(conv.updatedAt);
      const idx = groupIndexMap.get(name);
      if (idx === undefined) {
        // 新组
        groupIndexMap.set(name, result.length);
        result.push({ name: name, conversations: [conv] });
      } else {
        result[idx].conversations.push(conv);
      }
    });
    this.groups = result;
  }

  /** 加载收藏 Tab 数据：顶级文件夹 + 已收藏但未放入文件夹的对话 */
  async loadFavorites(): Promise<void> {
    // 顶级文件夹：parent_id 为空
    this.topFolders = await CategoryRepository.getInstance().getByParent("");
    // 未分类收藏对话：已收藏（is_favorite=1）且 category_id 为空
    const favorites = await ConversationRepository.getInstance().getFavorites();
    this.uncategorizedConvs = favorites.filter((c: Conversation) => c.categoryId.length === 0);
  }

  // ===== Tab 与选中 =====

  /** 顶部 Tab 点击：更新高亮状态（页面负责 Swiper 带动画切换） */
  setCurrentTab(index: number): void {
    this.currentTab = index;
  }

  /** 用户选中某条历史对话：存入 AppConfig（页面负责 router.back() 返回） */
  selectConversation(conv: Conversation): void {
    AppConfig.getInstance().selectedConversation = conv;
  }

  // ===== 多选编辑模式 =====

  /** 进入多选模式（可预选长按的那一项） */
  enterEditMode(preSelectId: string): void {
    this.isEditMode = true;
    this.selectedIds = preSelectId.length > 0 ? [preSelectId] : [];
  }

  exitEditMode(): void {
    this.isEditMode = false;
    this.selectedIds = [];
  }

  toggleSelect(id: string, checked: boolean): void {
    // @Trace 数组：用新数组赋值确保 UI 刷新（避免依赖 push/splice 的观察行为）
    if (checked && this.selectedIds.indexOf(id) < 0) {
      this.selectedIds = this.selectedIds.concat(id);
    } else if (!checked && this.selectedIds.indexOf(id) >= 0) {
      this.selectedIds = this.selectedIds.filter((x: string) => x !== id);
    }
  }

  // 当前可见对话（分组拍平，供全选使用）
  private getAllVisible(): Conversation[] {
    const result: Conversation[] = [];
    this.groups.forEach((g: GroupItem) =>
      g.conversations.forEach((c: Conversation) => result.push(c)),
    );
    return result;
  }

  isAllSelected(): boolean {
    const visible = this.getAllVisible();
    return visible.length > 0 && this.selectedIds.length === visible.length;
  }

  toggleSelectAll(): void {
    if (this.isAllSelected()) {
      this.selectedIds = [];
    } else {
      this.selectedIds = this.getAllVisible().map((c: Conversation) => c.id);
    }
  }

  // ===== 对话操作 =====

  /** 执行重命名：更新内存 + 数据库 */
  async doRename(id: string, newTitle: string): Promise<void> {
    const conv = this.conversations.find((c: Conversation) => c.id === id);
    if (!conv) return;
    conv.title = newTitle; // 更新内存对象
    // 收藏 Tab 的 uncategorizedConvs 是另一批实例，需同步，否则收藏列表不实时刷新
    const uc = this.uncategorizedConvs.find((c: Conversation) => c.id === id);
    if (uc) uc.title = newTitle;
    await ConversationRepository.getInstance().update(conv); // 持久化
    this.listVersion++; // 强制 ForEach 重建，刷新对话标题
    showToast($r('app.string.rename_success'));
  }

  /** 执行收藏：置 is_favorite=1 并写入收藏位置 */
  async doFavorite(conv: Conversation, folderId: string): Promise<void> {
    // 历史列表中的对应实例同步更新（列表数据源可能是另一批实例）
    const hist = this.conversations.find((c: Conversation) => c.id === conv.id);
    if (hist) {
      hist.isFavorite = true;
      hist.categoryId = folderId;
    }
    conv.isFavorite = true;
    conv.categoryId = folderId;
    await ConversationRepository.getInstance().setFavorite(conv, true);
    await this.loadFavorites(); // 刷新收藏 Tab（对话可能进入文件夹或未分类）
    this.listVersion++; // 刷新历史列表：星标出现、菜单变为"取消收藏"
    showToast($r('app.string.favorited'));
  }

  /** 执行取消收藏：置 is_favorite=0、清空收藏位置，并从收藏列表移除 */
  async doUnfavorite(conv: Conversation): Promise<void> {
    await ConversationRepository.getInstance().setFavorite(conv, false); // 同时清空 categoryId
    // 历史列表中的对应实例同步更新（收藏 Tab 与历史列表可能是不同实例）
    const hist = this.conversations.find((c: Conversation) => c.id === conv.id);
    if (hist) {
      hist.isFavorite = false;
      hist.categoryId = "";
    }
    conv.isFavorite = false;
    conv.categoryId = "";
    await this.loadFavorites(); // 刷新收藏 Tab（未分类收藏可能变化）
    this.listVersion++; // 刷新历史列表：星标消失、菜单变回"收藏"
    showToast($r('app.string.unfavorited'));
  }

  /** 执行移动文件夹：更新 parentId 并刷新列表 */
  async doMoveFolder(cat: Category, targetId: string): Promise<void> {
    await moveCategoryTo(cat, targetId); // 空串 = 移到顶级
    await this.loadFavorites();
    showToast(targetId.length > 0 ? $r('app.string.moved') : $r('app.string.moved_to_top'));
  }

  /** 执行移动对话：更新分类并刷新收藏列表 */
  async doMoveConv(conv: Conversation, folderId: string): Promise<void> {
    await moveConversationTo(conv, folderId);
    // 收藏 Tab 的未分类列表可能因分类变化而增删，重新加载刷新
    await this.loadFavorites();
    showToast($r('app.string.moved_ok'));
  }

  /** 执行批量移动：选中对话统一移入目标文件夹，然后退出编辑模式并刷新 */
  async doBatchMove(folderId: string): Promise<void> {
    const ids = this.selectedIds.slice(); // 先拷贝，避免退出编辑模式时被清空
    await ConversationRepository.getInstance().move(ids, folderId);
    this.exitEditMode();
    await this.loadFavorites(); // 移入文件夹后从"未分类"消失
    showToast(folderId.length > 0 ? `已移动 ${ids.length} 个对话` : $r('app.string.moved_out'));
  }

  /** 执行删除：先拷贝 id，再删除 → 退出编辑模式 → 刷新 */
  async doDelete(ids: string[]): Promise<void> {
    this.removeConversationsLocally(ids); // 内存中移除
    this.exitEditMode();
    await ConversationRepository.getInstance().deleteConversations(ids); // 删数据库
    showToast(`已删除 ${ids.length} 个对话`);
  }

  /** 执行删除文件夹（级联） */
  async doDeleteFolder(id: string): Promise<void> {
    await CategoryRepository.getInstance().deleteCategoryCascade(id);
    await this.loadFavorites();
    showToast($r('app.string.folder_deleted'));
  }

  /** 执行新建顶级文件夹 */
  async createFolder(name: string, color: string): Promise<void> {
    const cat = new Category(undefined, name, undefined, color); // 颜色一并入库
    await CategoryRepository.getInstance().insert(cat);
    await this.loadFavorites(); // 刷新收藏 Tab
    showToast(`已创建 ${name}`);
  }

  /** 执行编辑文件夹：重命名 + 切换图标颜色 */
  async saveEdit(cat: Category, name: string, color: string): Promise<void> {
    await saveCategoryEdit(cat, name, color); // 更新名称与颜色并持久化
    await this.loadFavorites();
    this.listVersion++; // 强制 ForEach 重建，刷新名称/颜色
    showToast($r('app.string.saved'));
  }

  /** 从内存数据源移除指定对话，并同步渲染分组 */
  private removeConversationsLocally(ids: string[]): void {
    // 从全量数据源移除：保证后续搜索/重新分组不会把已删项带回来
    this.conversations = this.conversations.filter((c: Conversation) => ids.indexOf(c.id) < 0);
    // 从渲染用分组中移除，并剔除被删空的分组
    this.groups = this.groups
      .map(
        (g: GroupItem): GroupItem => ({
          name: g.name,
          conversations: g.conversations.filter((c: Conversation) => ids.indexOf(c.id) < 0),
        }),
      )
      .filter((g: GroupItem) => g.conversations.length > 0);
    // 同步移除收藏 Tab 的未分类对话，否则切到收藏界面仍会显示已删除的对话
    this.uncategorizedConvs = this.uncategorizedConvs.filter(
      (c: Conversation) => ids.indexOf(c.id) < 0,
    );
  }
}