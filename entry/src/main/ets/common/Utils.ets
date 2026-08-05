/**
 * 通用工具模块
 * 集中管理跨页面/跨模型复用的轻量公共能力：
 *   - generateId:       统一 ID 生成（Conversation / Category 复用）
 *   - showToast:        统一 Toast 提示入口
 *   - showDeleteConfirm: 统一"删除"二次确认弹窗（各页面复用）
 * 本模块不依赖业务模块（模型/数据库），避免循环依赖
 */

import { promptAction, UIContext } from "@kit.ArkUI";

/**
 * 生成唯一随机 ID（毫秒时间戳 + 随机串）
 * 统一 Conversation 与 Category 的 ID 生成逻辑
 */
export function generateId(): string {
  return `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
}

/**
 * 统一 Toast 提示（行为与直接调用 promptAction.showToast({ message }) 一致）
 * @param message 提示文案
 */
export function showToast(message: string | Resource): void {
  promptAction.showToast({ message: message });
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
      fontColor: Color.Red,
      action: () => {
        onConfirm();
      },
    },
  });
}
