import { Message } from "../model/Message";
import { ConversationRepository } from "../database/ConversationRepository";

/**
 * 分支组变体信息（用于气泡左下角渲染 "< 当前 / 总数 >"）
 * @param current 当前变体序号（1 起）
 * @param total 分支组内变体总数
 */
export interface VariantInfo {
  current: number;
  total: number;
}

/**
 * 分支链管理器：承载对话分支相关的数据逻辑
 *
 * 职责边界（与 ChatViewModel 分工）：
 *   - 持有"当前对话全部消息缓存"（含非激活分支变体）与"变体信息缓存"
 *   - 分支链构建 / 变体统计 / 分支熄灭 / 删除后的兄弟定位 等纯数据逻辑
 *   - 不触碰 UI 相关对象（listScroller / messageDataSource / 滚动控制），
 *     列表替换与滚动由 ChatViewModel 在调用本类结果后自行完成
 */
export class BranchChainManager {
  // 当前对话的全部消息缓存（含非激活分支变体），分支切换/变体统计/激活链重建均基于它
  private allMessages: Message[] = [];
  // 分支组信息缓存（key = 消息 id）：避免 LazyForEach 重建时对每条消息重复 O(n) 过滤+排序
  private variantInfoCache: Map<string, VariantInfo> = new Map();

  // ===== 数据访问接口（ChatViewModel 通过以下方法读写缓存，缓存变更时自动失效变体信息缓存） =====

  // 整体替换消息缓存（加载历史对话时调用）
  setAll(list: Message[]): void {
    this.allMessages = list;
    this.variantInfoCache.clear();
  }

  // 追加一条消息（普通发送 / 新建变体时调用）
  add(msg: Message): void {
    this.allMessages.push(msg);
    this.variantInfoCache.clear();
  }

  // 批量移除消息（删除消息及其子树时调用）
  removeMany(ids: string[]): void {
    this.allMessages = this.allMessages.filter((m: Message) => ids.indexOf(m.id) < 0);
    this.variantInfoCache.clear();
  }

  // 清空消息缓存（新建对话时调用）
  clearAll(): void {
    this.allMessages = [];
    this.variantInfoCache.clear();
  }

  // 获取全部消息引用（只读遍历场景：持久化激活链 / 重建激活链等）
  getAll(): Message[] {
    return this.allMessages;
  }

  // 按 id 查找消息（编辑用户消息定位目标等）
  getById(id: string): Message | undefined {
    return this.allMessages.find(m => m.id === id);
  }

  // 当前缓存的消息总数
  size(): number {
    return this.allMessages.length;
  }

  // ===== 分支链计算 =====

  /**
   * 构建激活链：从根消息（parentId=""）出发，沿激活子节点延伸
   * 兼容旧数据（全部消息 parentId 为空）→ 按时间正序返回
   */
  buildActiveChain(): Message[] {
    const all = this.allMessages;
    if (all.length === 0) return [];
    const hasParent = all.some(m => m.parentId.length > 0);
    if (!hasParent) {
      return all.slice().sort((a, b) => a.createdAt - b.createdAt);
    }
    // 根 = parentId 为空的消息（多个根取激活的，否则取最早的）
    const roots = all.filter(m => m.parentId.length === 0)
      .sort((a, b) => a.createdAt - b.createdAt);
    if (roots.length === 0) {
      return all.slice().sort((a, b) => a.createdAt - b.createdAt);
    }
    const root = roots.find(r => r.isActive) ?? roots[0];
    const chain: Message[] = [];
    const visited = new Set<string>();
    // string 游标遍历（避免 while 条件对可选变量收窄失效的 ArkTS 编译限制）
    let curId: string = root.id;
    while (true) {
      if (visited.has(curId)) break; // 防环兜底
      const node = all.find(m => m.id === curId);
      if (node === undefined) break;
      visited.add(curId);
      chain.push(node);
      const children = all.filter(m => m.parentId === node.id);
      if (children.length === 0) break;
      const next = this.selectNextChild(children);
      if (next === undefined) break;
      curId = next.id;
    }
    return chain;
  }

  /**
   * 从一组子节点（同父的变体兄弟）中选择激活链延续：
   * 优先选 isActive 节点；全部非激活时取组内最早变体（variantIndex 最小 = 原始分支）
   */
  selectNextChild(children: Message[]): Message | undefined {
    const active = children.filter(c => c.isActive);
    if (active.length > 0) return active[0];
    const sorted = children.slice().sort((a, b) => a.variantIndex - b.variantIndex);
    return sorted.length > 0 ? sorted[0] : undefined;
  }

  /** 将节点及其激活后续链全部置为非激活（创建新分支时熄灭旧分支），同步持久化 */
  deactivateBranchFrom(node: Message): void {
    const stack: Message[] = [node];
    while (stack.length > 0) {
      const cur = stack.pop();
      if (cur === undefined) continue; // 栈已空（防御）
      if (!cur.isActive) continue; // 已被熄灭，跳过
      cur.isActive = false;
      ConversationRepository.getInstance().updateMessageActive(cur.id, false);
      // 继续熄灭其激活子节点（分支链保证每个父节点至多一个激活子节点）
      this.allMessages.forEach((m: Message) => {
        if (m.parentId === cur.id && m.isActive) {
          stack.push(m);
        }
      });
    }
  }

  // ===== 变体信息 =====

  /**
   * 分支组信息：返回 { current, total }，用于渲染 "< 当前 / 总数 >"
   * @param msg 当前消息
   * @returns current = 当前变体序号（1 起）；total = 分支组内变体总数
   */
  getVariantInfo(msg: Message): VariantInfo {
    // 命中缓存直接返回：同一消息在 LazyForEach 重建时无需重复 O(n) 过滤+排序
    const cached = this.variantInfoCache.get(msg.id);
    if (cached !== undefined) {
      return cached;
    }
    const info = this.computeVariantInfo(msg);
    this.variantInfoCache.set(msg.id, info);
    return info;
  }

  /** 计算分支组信息（无缓存，仅在缓存未命中时调用） */
  computeVariantInfo(msg: Message): VariantInfo {
    const group = this.allMessages.filter(m => m.branchGroupId === msg.branchGroupId);
    if (group.length === 0) {
      return { current: msg.variantIndex + 1, total: msg.variantIndex + 1 };
    }
    // 按变体序号排序，用"组内位置"计算当前序号
    // 原因：删除某条变体后 variantIndex 会留下空洞（如 0,1,2 删除 1 后剩 0,2），
    // 若直接用 variantIndex+1 计算 current，会出现 current > total（如显示 3/2）
    const sorted = group.slice().sort((a, b) => a.variantIndex - b.variantIndex);
    const pos = sorted.findIndex(m => m.id === msg.id);
    // 组内去重统计变体数（variantIndex 唯一）
    const indexes = new Set<number>();
    group.forEach(m => indexes.add(m.variantIndex));
    return { current: Math.max(1, pos + 1), total: Math.max(1, indexes.size) };
  }

  /** 计算指定分支组内的下一个变体序号（组内最大 index + 1） */
  nextVariantIndex(branchGroupId: string): number {
    let max = -1;
    this.allMessages.forEach((m: Message) => {
      if (m.branchGroupId === branchGroupId && m.variantIndex > max) {
        max = m.variantIndex;
      }
    });
    return max + 1;
  }

  /** 找到 AI 消息对应的用户提问（其父用户消息的内容），用作联网搜索关键词 */
  findPromptOf(aiMsg: Message): string {
    const parent = this.allMessages.find(m => m.id === aiMsg.parentId);
    return parent !== undefined ? parent.content : "";
  }

  /**
   * 删除消息后寻找"紧邻前一个变体"作为新激活目标：
   * 仅当被删除消息原本处于激活态、且其分支组内仍有剩余变体时，返回前一个变体
   * （如 6/8 被删除 → 激活 5/7）；被删除的是第一个变体时回退到剩余第一个（原 2 号 → 现 1 号）。
   * 其余情况返回 undefined，走原有 buildActiveChain 兜底（保持当前激活链不动）。
   */
  findPrevSiblingForDeleted(deleted: Message): Message | undefined {
    if (!deleted.isActive) return undefined; // 删除非激活变体不影响激活链
    if (deleted.parentId.length === 0) return undefined; // 根消息无兄弟变体概念
    const group = this.allMessages.filter(m => m.branchGroupId === deleted.branchGroupId && m.id !== deleted.id);
    if (group.length === 0) return undefined; // 无剩余兄弟（唯一变体被删）
    const sorted = group.slice().sort((a, b) => a.variantIndex - b.variantIndex);
    let prev: Message | undefined = undefined;
    for (const m of sorted) {
      if (m.variantIndex < deleted.variantIndex) {
        prev = m; // 持续记录"紧邻小于被删变体"的最后一个（即上一个变体）
      } else {
        break;
      }
    }
    return prev ?? sorted[0]; // 无更小变体（删的是第一个）→ 回退到剩余第一个
  }
}
