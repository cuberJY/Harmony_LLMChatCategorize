import { Message } from "../model/Message";

/**
 * 消息列表数据源（配合 LazyForEach 使用）
 * 实现 IDataSource 接口，只渲染可视区域内的消息，减少渲染开销
 */
export class MessageDataSource implements IDataSource {
  private messages: Message[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.messages.length;
  }

  getData(index: number): Message {
    return this.messages[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  // 添加一条消息并通知 LazyForEach 创建对应 ListItem
  push(msg: Message): void {
    this.messages.push(msg);
    this.listeners.forEach((l: DataChangeListener) => l.onDataAdd(this.messages.length - 1));
  }

  // 整体替换消息列表（分支切换/激活链重建后调用，触发 LazyForEach 全量重载）
  replaceAll(list: Message[]): void {
    this.messages = list;
    this.listeners.forEach((l: DataChangeListener) => l.onDataReloaded());
  }

  // 增量替换 [start, start+deleteCount) 区间为新 items（切换分支等局部更新用）：
  // 用 onDataDelete/onDataAdd 精准通知，避免 onDataReloaded 全量重建导致前缀消息 Markdown 重渲染
  replaceRange(start: number, deleteCount: number, insertItems: Message[]): void {
    // 1. 删除旧区间（数组从后往前，保持前面 item 的 index 不变）
    for (let i = deleteCount - 1; i >= 0; i--) {
      this.messages.splice(start + i, 1);
    }
    for (let i = deleteCount - 1; i >= 0; i--) {
      this.listeners.forEach((l: DataChangeListener) => l.onDataDelete(start + i));
    }
    // 2. 插入新 items（数组从前往后）
    for (let i = 0; i < insertItems.length; i++) {
      this.messages.splice(start + i, 0, insertItems[i]);
    }
    for (let i = 0; i < insertItems.length; i++) {
      this.listeners.forEach((l: DataChangeListener) => l.onDataAdd(start + i));
    }
  }

  // 获取内部数组引用（用于构造上下文等只读场景）
  getAll(): Message[] {
    return this.messages;
  }

  // 清空所有消息
  clear(): void {
    this.messages = [];
    this.listeners.forEach((l: DataChangeListener) => l.onDataReloaded());
  }
}
