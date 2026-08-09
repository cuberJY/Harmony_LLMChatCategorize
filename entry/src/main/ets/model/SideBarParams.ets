/**
 * SideBarPage 路由参数（Navigation 传参专用）
 * ArkTS 限制：对象字面量必须对应显式声明的类（arkts-no-untyped-obj-literals），
 * 因此路由参数用类实例传递，替代 { key: value } 字面量。
 */
export class SideBarParams {
  currentConversationId: string; // 当前打开的对话 id（历史列表据此高亮）

  constructor(currentConversationId: string) {
    this.currentConversationId = currentConversationId;
  }
}