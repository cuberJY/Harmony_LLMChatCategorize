/**
*应用全局常量定义
*集中管理颜色、字号、间距，便于后续换肤/暗黑模式扩展
*/

// 颜色常量
export enum COLORS {
  PRIMARY = "#cd2d65f8", // 主题蓝 — 发送按钮、链接
  // 页面背景
  PAGE_BG = "#FFFFFF", // 页面背景色
  TITLE_BAR_BG = "#FFFFFF", // 标题栏背景
  DIVIDER = "#EEEEEE", // 分割线
  SEND_BTN_DISABLED = "#CCCCCC", // 发送按钮禁用态
  // 气泡
  BUBBLE_BG_USER = "#E8F4FD", // 用户气泡背景（浅蓝）
  BUBBLE_BG_AI = "#FFFFFF", // AI 气泡背景（白）
  BUBBLE_BG_THINKING = "#F7F7F8", // 思考中气泡背景（灰）
  // 文字
  TEXT_PRIMARY = "#1A1A1A", // 主文字色
  TEXT_SECONDARY = "#999999", // 次要文字（时间戳等）
  TEXT_IMPORTANT = "#2D65F8", // 重要文字
  TEXT_USER = "#1A1A1A", // 用户消息
  TEXT_AI = "#1A1A1A", // AI消息
  TEXT_DANGER = "#FF4D4F", // 危险文字
  // 输入
  INPUT_BG = "#FFFFFF", // 输入区背景
  INPUT_BORDER = "#E0E0E0", // 输入框边框
  // 输入区卡片
  INPUT_CONTAINER_BG = "#FFFFFF", // 输入区卡片背景
  // 切换按钮
  TOGGLE_BG_ACTIVE = "#E8F4FD", // 切换按钮激活态背景
  TOGGLE_BG_INACTIVE = "#F0F0F0", // 切换按钮默认态背景
  TOGGLE_TEXT_ACTIVE = "#2D65F8", // 切换按钮激活态文字
  TOGGLE_TEXT_INACTIVE = "#666666", // 切换按钮默认态文字
  // 悬浮菜单
  MENU_BG = "#CDFFFFFF", // 对话管理
  STAR_GOLD = "#FFB800", // 收藏星标金色
  FAB_SHADOW = "#662D65F8", // 悬浮按钮阴影
};

// 字号常量
export enum FONT_SIZES {
  TITLE = 18, // 标题栏
  NAME = 16, // 名称
  TIME = 11, // 时间戳
  THINKING = 13, // 思考中文字
  BODY = 15, // 消息正文
  MODEL_NAME = 12, // 模型名称
  INPUT = 15, // 输入框

  REMIND = 17, // 提示文字 
  BUTTON = 14, // 按钮文字
  TOGGLE = 16, // 切换按钮文字

  ICON_SM = 12,   // 小图标
  ICON_MD = 14,   // 中图标
  ICON_LG = 16,   // 大图标
  ICON_XL = 20,   // 超大图标
  ICON_XXL = 24,  // 超超大图标
};

// 间距常量
export enum SPACING {
  XS = 4, // 微间距
  SM = 8, // 小间距
  MD = 12, // 中间距
  LG = 16, // 大间距
  XL = 20, // 超大间距
  XXL = 24, // 超超大间距

  TITLE_BAR_HEIGHT = 60, // 标题栏高度
};

// 气泡样式常量
export enum BUBBLE {
  RADIUS = 12, // 圆角半径
  MAX_WIDTH_RATIO_USER = 0.75, // 气泡最大宽度占屏幕比
  MAX_WIDTH_RATIO_AI = 1, // 气泡最大宽度占屏幕比
  PADDING_H = 14, // 水平内边距
  PADDING_V = 10, // 垂直内边距
};

// 文件夹图标色板（8 色预设，EditFolderDialog 与 Category 默认色共用）
export const FOLDER_COLORS: string[] = [
  "#FF9F0A", // 橙
  "#FF3B30", // 红
  "#FF2D55", // 粉
  "#AF52DE", // 紫
  "#0A84FF", // 蓝
  "#5AC8FA", // 青
  "#34C759", // 绿
  "#8E8E93", // 灰
];

// 统一提示文案（集中管理静态 Toast 消息）
export enum MESSAGES {
  NAME_EMPTY = "名称不能为空", // 名称类输入为空
  TITLE_EMPTY = "标题不能为空", // 对话标题为空
  RENAME_SUCCESS = "标题修改成功", // 对话重命名成功
  RENAME_CONV_SUCCESS = "重命名成功", // 文件夹内对话重命名成功
  FAVORITED = "已收藏", // 收藏成功
  UNFAVORITED = "已取消收藏", // 取消收藏成功
  SAVED = "已保存", // 文件夹编辑保存成功
  MOVED = "已移动", // 文件夹移动成功
  MOVED_TO_TOP = "已移到顶级", // 文件夹移到顶级
  MOVED_OK = "移动成功", // 对话移动成功
  MOVED_OUT = "已移出不分类", // 批量移出不分类
  FOLDER_DELETED = "文件夹已删除", // 文件夹删除成功
  DELETED = "已删除", // 对话删除成功
  STREAMING_BUSY = "正在回复中，请稍候", // 流式回复中禁止连发
  CONFIG_INCOMPLETE = "请填写完整的 AI 对话配置", // 设置页必填校验
  SAVE_SUCCESS = "保存成功", // 设置保存成功
}
