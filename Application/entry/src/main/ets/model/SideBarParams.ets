/**
 * SideBarPage 路由参数（Navigation 传参专用）
 * ArkTS 限制（arkts-no-untyped-obj-literals）要求对象字面量对应显式类，故用类实例传参
 */
export class SideBarParams {
  currentConversationId: string; // 当前打开的对话 id（历史列表据此高亮）

  constructor(currentConversationId: string) {
    this.currentConversationId = currentConversationId;
  }
}