/**
 * 搜索 ViewModel（状态管理 V2）
 * 承载搜索面板的搜索状态与逻辑（从 SideBarViewModel 迁出，随搜索面板独立）：
 *   - 标题匹配（内存同步）+ 消息内容匹配（DB 异步）双通道
 *   - 输入 200ms 防抖 + 版本号竞态守卫
 *   - 内容搜索范围切换（仅激活分支 / 全部消息）
 *   - 结果为「对话分组」：一个对话一组，组内列出该对话所有命中消息（按发送时间升序），每条可精确定位
 */

import { ConversationRepository } from "../database/ConversationRepository";
import { Conversation } from "../model/Conversation";
import { ContentSnippet } from "../model/Message";

/* 命中消息（内容命中）：片段 + 发送时间，可精确跳转定位到该条消息 */
export interface SearchHit {
  messageId: string; // 命中的消息 ID（打开对话后滚动定位用）
  snippet: string; // 命中片段（关键字居中截取）
  createdAt: number; // 消息发送时间戳（组内时间展示）
}

/* 搜索结果分组：一个对话为一组
   titleHit=对话标题命中（组头高亮/计数）；hits=内容命中的所有消息（按时间升序）
   仅标题命中时 hits 为空；仅内容命中时 titleHit=false */
export interface SearchResultGroup {
  conversation: Conversation;
  titleHit: boolean; // 是否标题命中
  hits: SearchHit[]; // 内容命中消息（可能为空）
}

@ObservedV2
export class SearchViewModel {
  /* UI 可观察状态（@Trace：页面 build 中读取，变化时自动刷新） */
  @Trace searchText: string = ""; // 搜索关键字
  @Trace searchScope: "active" | "all" = "active"; // 内容搜索范围：active=仅激活分支消息  all=全部消息（含被覆盖的变体）
  @Trace results: SearchResultGroup[] = []; // 分组搜索结果（渲染数据源）

  /* 全量对话数据源（结果由 results 承载，无需 @Trace） */
  private conversations: Conversation[] = [];
  /* 内容搜索内部状态（非 UI 可观察）：防抖定时器 + 竞态守卫版本号 */
  private debounceTimer: number = -1; // 输入防抖定时器（200ms 后执行 DB 查询）
  private searchVersion: number = 0; // 每次输入自增；DB 查询返回时若版本已过期则丢弃结果，防快速输入竞态

  /* 加载全量对话（进入页面 / 返回时刷新数据源） */
  async loadConversations(): Promise<void> {
    this.conversations = await ConversationRepository.getInstance().getAll();
    if (this.searchText.trim().length === 0) {
      this.results = []; // 无关键字：空态（不在结果里平铺全部对话）
    } else {
      this.onSearchChanged(this.searchText); // 已有搜索词（如返回时）：重算保持结果一致
    }
  }

  /* 输入变化（页面 TextInput.onChange 调用）：标题立即同步过滤 + 内容搜索防抖异步补全 */
  async onSearchChanged(value: string): Promise<void> {
    this.searchText = value;
    const version = ++this.searchVersion; // 版本号自增：本次输入的查询结果优先于历史输入
    const keyword = value.trim().toLowerCase();
    if (keyword.length === 0) {
      this.results = []; // 清空关键字：回到初始空态
      return;
    }
    /* 标题命中立即生效（纯内存，无需 DB）：输入即见结果，保证"即时反馈"体感 */
    this.applyTitleFilter(keyword);
    /* 内容命中防抖后查询：停笔 200ms 才查库，减少 message 表 LIKE 查询次数 */
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer);
    }
    this.debounceTimer = setTimeout(() => {
      this.searchByKeyword(keyword, version);
    }, 200);
  }

  /* 切换内容搜索范围（全部消息 / 仅激活分支）并立即重搜 */
  toggleSearchScope(): void {
    this.searchScope = this.searchScope === "active" ? "all" : "active";
    const keyword = this.searchText.trim().toLowerCase();
    if (keyword.length === 0) return;
    /* 1. 同步刷新：标题命中结果立即重建（范围不影响标题，但保证切换瞬间页面有反馈） */
    this.applyTitleFilter(keyword);
    /* 2. 立即重查内容命中：清理防抖定时器，DB 返回后合并刷新（不等 200ms） */
    this.submitSearch();
  }

  /* 输入法「搜索」键触发：取消防抖，立即执行搜索（不等 200ms） */
  submitSearch(): void {
    if (this.debounceTimer >= 0) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    const keyword = this.searchText.trim().toLowerCase();
    if (keyword.length === 0) return;
    /* 标题命中已实时显示；这里立即补查内容命中，DB 返回后合并刷新 */
    const version = ++this.searchVersion; // 使在途查询作废，本次结果优先
    this.searchByKeyword(keyword, version);
  }

  /* 仅按标题过滤并同步刷新（纯内存，供输入/搜索键的即时反馈） */
  private applyTitleFilter(keyword: string): void {
    const titleIds = new Set<string>();
    this.conversations.forEach((c: Conversation) => {
      if (c.title.toLowerCase().includes(keyword)) {
        titleIds.add(c.id);
      }
    });
    this.results = this.buildGroups(titleIds, new Map<string, SearchHit[]>());
  }

  /* 实际执行内容搜索：标题命中（内存）∪ 内容命中（DB message.content + 命中片段）后排序 */
  private async searchByKeyword(keyword: string, version: number): Promise<void> {
    /* 1. 内容命中（DB 查询：message 表 content 字段，按范围限定激活分支；返回全部命中消息） */
    const snippets = await ConversationRepository.getInstance()
      .getContentMatchSnippets(keyword, this.searchScope === "active");
    if (version !== this.searchVersion) {
      return; // 输入已变化：丢弃过期结果，防止旧查询覆盖新输入
    }
    /* 2. 标题命中（内存过滤，不查库） */
    const titleIds = new Set<string>();
    this.conversations.forEach((c: Conversation) => {
      if (c.title.toLowerCase().includes(keyword)) {
        titleIds.add(c.id);
      }
    });
    /* 3. 按对话聚合命中消息（snippets 已按时间升序，group 内顺序自然保持） */
    const snippetMap = new Map<string, SearchHit[]>();
    snippets.forEach((s: ContentSnippet) => {
      const hits = snippetMap.get(s.conversationId);
      if (hits === undefined) {
        snippetMap.set(s.conversationId, [{ messageId: s.messageId, snippet: s.snippet, createdAt: s.createdAt }]);
      } else {
        hits.push({ messageId: s.messageId, snippet: s.snippet, createdAt: s.createdAt });
      }
    });
    /* 4. 合并成组：标题命中或内容命中的对话都展示，按对话最后更新时间倒序 */
    this.results = this.buildGroups(titleIds, snippetMap);
  }

  /**
   * 合并构建结果组：标题命中 ∪ 内容命中的对话，按对话最后更新时间倒序
   * 同一对话的命中消息（hits）保持时间升序（DAO 查询已排序）
   */
  private buildGroups(titleIds: Set<string>, snippetMap: Map<string, SearchHit[]>): SearchResultGroup[] {
    const groups: SearchResultGroup[] = [];
    this.conversations.forEach((c: Conversation) => {
      const titleHit = titleIds.has(c.id);
      const hits = snippetMap.get(c.id);
      /* hits 在「或」条件中不做类型收缩，用三元显式判空取出 */
      const hitList = hits === undefined ? [] : hits;
      if (titleHit || hitList.length > 0) {
        groups.push({ conversation: c, titleHit: titleHit, hits: hitList });
      }
    });
    return groups.sort(
      (a: SearchResultGroup, b: SearchResultGroup) => b.conversation.updatedAt - a.conversation.updatedAt,
    );
  }
}
