/**
 * 应用全局业务常量
 * 颜色/字号/文案等已迁移至资源文件（$r() 引用）；
 * 本文件仅保留无法用资源表达的常量：文件夹色板、气泡宽度比例、弹窗位置与延迟
 */

/* 文件夹图标色板（8 色预设，EditFolderDialog 与 Category 默认色共用） */
export const FOLDER_COLORS: string[] = [
  "#ffe84026",
  "#ffed6f22",
  "#ffe4ba10",
  "#ff64bb5c",
  "#ff60cfbe",
  "#ff46b2e3",
  "#ffac49f4",
  "#ff5649f8",
];

/* 文件夹默认图标颜色（唯一真源，其余文件一律引用此常量，禁止再写 #FF9F0A 字面量） */
export const DEFAULT_FOLDER_COLOR: string = FOLDER_COLORS[0];

/* 用户气泡最大宽度占屏幕比例（constraintSize 需拼 "75%" 形式字符串，无法用资源表达） */
export const BUBBLE_MAX_WIDTH_RATIO_USER: number = 0.8;
/* AI 气泡最大宽度占屏幕比例（=100%，即不限制） */
export const BUBBLE_MAX_WIDTH_RATIO_AI: number = 1;

/**
 * 自定义弹窗（openCustomDialog）位置常量
 * 输入型弹窗统一居中并向上偏移：矮弹窗（重命名）-10，高弹窗（新建/编辑）-40
 * 类型用 Offset（含 dx/dy），与 openCustomDialog options.offset 的参数类型一致
 */
export const DIALOG_OFFSET_SLIGHT: Offset = { dx: 0, dy: -5 };
export const DIALOG_OFFSET_TALL: Offset = { dx: 0, dy: -34 };
/* 输入弹窗键盘避让：弹窗底部与键盘顶部的最小间距（vp） */
export const DIALOG_KEYBOARD_MARGIN: number = 16;
/* 长按菜单触发弹窗的延迟打开时间（ms）：等 bindContextMenu 子窗口关闭动画结束，避免弹窗被吞 */
export const DIALOG_DELAY_AFTER_MENU: number = 150;
