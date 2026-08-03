/**
 * 时间工具函数
 * 统一「今天/昨天/7天内/30天内/更早」分组与智能时间格式化逻辑
 * 供 ChatPage（消息时间分割线）、SideBarPage（历史对话分组）复用，
 * 避免同一套判定逻辑在多处重复实现
 */

/**
 * 根据时间戳计算历史对话所属分组名
 *   今天 → "今天"
 *   昨天 → "昨天"
 *   7天内 → "7天内"
 *   30天内 → "30天内"
 *   更早 → "2026年6月"
 * @param timestamp 时间戳（毫秒）
 */
export function getGroupName(timestamp: number): string {
  const date = new Date(timestamp);
  const now = new Date();

  // 今天
  if (date.toDateString() === now.toDateString()) {
    return "今天";
  }
  // 昨天
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) {
    return "昨天";
  }
  // 7天内 / 30天内：归零到当天 00:00:00，用日历日差比较
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const msgDayStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  const diffDays = Math.floor((todayStart - msgDayStart) / (1000 * 60 * 60 * 24));
  if (diffDays < 7) {
    return "7天内";
  }
  if (diffDays < 30) {
    return "30天内";
  }
  // 更早 → 年月分组
  return `${date.getFullYear()}年${date.getMonth() + 1}月`;
}

/**
 * 智能时间格式化（用于消息时间分割线）
 *   今天 → "14:30"
 *   昨天 → "昨天 14:30"
 *   本周 → "星期三 14:30"
 *   同年 → "7/9 14:30"
 *   跨年 → "2026/7/9 14:30"
 * @param timestamp 时间戳（毫秒）
 */
export function formatSmartTime(timestamp: number): string {
  const date = new Date(timestamp);
  const now = new Date();

  // HH:MM 格式
  const time = `${date.getHours().toString().padStart(2, "0")}:${date.getMinutes().toString().padStart(2, "0")}`;
  // 同一天
  if (date.toDateString() === now.toDateString()) {
    return time;
  }
  // 昨天
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) {
    return `昨天 ${time}`;
  }
  // 7天内：归零到当天 00:00:00，用日历日差比较
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const msgDayStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  const diffDays = Math.floor((todayStart - msgDayStart) / (1000 * 60 * 60 * 24));

  if (diffDays < 7 && diffDays >= 2) {
    const weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"];
    return `${weekdays[date.getDay()]} ${time}`;
  }
  // 同年
  if (date.getFullYear() === now.getFullYear()) {
    return `${date.getMonth() + 1}/${date.getDate()} ${time}`;
  }
  // 跨年
  return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()} ${time}`;
}