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
