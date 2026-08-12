/**
 * 应用全局常量（阶段1后精简版）
 *
 * 颜色（COLORS）、字号（FONT_SIZES）、间距（SPACING）、提示文案（MESSAGES）
 * 均已迁移至资源文件，通过 $r() 引用：
 *   - 颜色/深色适配 → resources/{base,dark}/element/color.json
 *   - 字号/间距     → resources/base/element/float.json
 *   - 文案/多语言   → resources/base/element/string.json
 *
 * 本文件仅保留无法用资源表达的"业务性常量"：
 *   - FOLDER_COLORS：文件夹图标色板（功能性数据，非主题色）
 *   - BUBBLE_MAX_WIDTH_RATIO_*：气泡最大宽度比例（需参与百分比字符串计算，必须为 number）
 */

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

// 文件夹默认图标颜色（唯一真源，其余文件一律引用此常量，禁止再写 #FF9F0A 字面量）
export const DEFAULT_FOLDER_COLOR: string = FOLDER_COLORS[0];

// 用户气泡最大宽度占屏幕比例（constraintSize 需拼 "75%" 形式字符串，无法用资源表达）
export const BUBBLE_MAX_WIDTH_RATIO_USER: number = 0.8;
// AI 气泡最大宽度占屏幕比例（=100%，即不限制）
export const BUBBLE_MAX_WIDTH_RATIO_AI: number = 1;
