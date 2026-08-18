/**
 * 分享卡片样式常量
 * 图片卡片（ShareSheetPanel 组件排版）与 HTML 卡片（ShareService 内联样式）共用，
 * 保证两种分享格式的视觉一致；修改此处即可统一调整分享卡片的配色。
 * 注：非 UI 资源（颜色用于生成 HTML 内联样式字符串，无法走 color.json 的 $r 引用），
 * 故用常量集中管理。
 */

/** 卡片背景色（浅灰） */
export const SHARE_CARD_BG: string = '#F7F8FA';

/** 卡片正文/标题文字色（近黑） */
export const SHARE_TEXT_PRIMARY: string = '#1A1A1A';

/** 用户气泡背景色（浅蓝） */
export const SHARE_USER_BUBBLE_BG: string = '#D6ECFF';

/** AI 气泡背景色（白） */
export const SHARE_AI_BUBBLE_BG: string = '#FFFFFF';

/** 提示文字色（灰，如"图片过长"提示） */
export const SHARE_HINT_TEXT: string = '#999999';

/** HTML 页面背景色（浅灰） */
export const SHARE_PAGE_BG: string = '#F7F8FA';
