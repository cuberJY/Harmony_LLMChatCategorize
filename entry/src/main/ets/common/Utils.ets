/**
 * 通用工具模块
 * 集中管理跨页面复用的轻量公共能力：ID 生成、Toast 提示、删除二次确认弹窗；
 * 不依赖业务模块（模型/数据库），避免循环依赖
 */

import { promptAction, UIContext } from "@kit.ArkUI";

/**
 * 生成唯一随机 ID（毫秒时间戳 + 随机串），统一 Conversation 与 Category 的 ID 生成逻辑
 */
export function generateId(): string {
  /* padStart 保证随机段恒为 7 位（极小随机值不再产生退化短串） */
  return `${Date.now()}_${Math.random().toString(36).substring(2, 9).padStart(7, "0")}`;
}

/**
 * 去掉常见 Markdown 标记，得到近似纯文本（复制按钮用，避免粘贴出粗体/标题等源码标记）
 */
export function stripMarkdown(md: string): string {
  return md
    .split('\n')
    .map((line: string) => line
      .replace(/^#{1,6}\s+/, '')
      .replace(/^>\s?/, '')
      .replace(/^[-*+]\s+/, '')
      .replace(/^\d+\.\s+/, '')
      .replace(/```.*$/, '')
      .replace(/\*\*(.+?)\*\*/g, '$1')
      .replace(/`([^`]+)`/g, '$1'))
    .join('\n');
}

/**
 * 统一 Toast 提示（行为与直接调用 promptAction.showToast({ message }) 一致）
 * @param message 提示文案
 * @param bottom Toast 底部与屏幕底部的距离（vp，越大越靠上）。不传则用默认值（160vp）
 */
export function showToast(message: string | Resource, bottom: number = 160): void {
  const options: promptAction.ShowToastOptions = { message: message };
  if (bottom !== undefined) {
    options.bottom = bottom;
  }
  promptAction.showToast(options);
}

/**
 * 统一的"删除"二次确认弹窗
 * 标题 + 说明 + 取消/删除（红色），确认后执行回调
 * @param uiContext 页面 UIContext（调用处传 this.getUIContext()）
 * @param title 弹窗标题
 * @param message 删除说明文案
 * @param onConfirm 确认删除后的回调
 */
export function showDeleteConfirm(
  uiContext: UIContext,
  title: string | Resource,
  message: string | Resource,
  onConfirm: () => void,
): void {
  uiContext.showAlertDialog({
    title: title,
    message: message,
    primaryButton: {
      value: "取消",
      action: () => {
      },
    },
    secondaryButton: {
      value: "删除",
      fontColor: $r('app.color.text_danger'),
      action: () => {
        onConfirm();
      },
    },
  });
}
