/**
 * 时间工具函数
 * 统一「今天/昨天/7天内/30天内/更早」分组与智能时间格式化逻辑，
 * 供消息分割线与历史对话分组复用，避免重复实现
 */

/**
 * 根据时间戳计算历史对话所属分组名
 * 规则：今天/昨天/7天内/30天内，更早按 "yyyy年M月" 归组
 * @param timestamp 时间戳（毫秒）
 */
export function getGroupName(timestamp: number): string {
  const date = new Date(timestamp);
  const now = new Date();
  /* 未来时间戳（时钟回拨）钳制为今天 */
  if (timestamp > Date.now()) {
    return "今天";
  }

  /* 今天 */
  if (date.toDateString() === now.toDateString()) {
    return "今天";
  }
  /* 昨天 */
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) {
    return "昨天";
  }
  /* 7天内 / 30天内：归零到当天 00:00:00，用日历日差比较 */
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const msgDayStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  const diffDays = Math.floor((todayStart - msgDayStart) / (1000 * 60 * 60 * 24));
  if (diffDays < 7) {
    return "7天内";
  }
  if (diffDays < 30) {
    return "30天内";
  }
  /* 更早 → 年月分组 */
  return `${date.getFullYear()}年${date.getMonth() + 1}月`;
}

/**
 * 智能时间格式化（用于消息时间分割线）
 * 规则：今天 → "HH:MM"；昨天 → "昨天 HH:MM"；本周 → "星期X HH:MM"；同年 → "M/D HH:MM"；跨年 → "yyyy/M/D HH:MM"
 * @param timestamp 时间戳（毫秒）
 */
export function formatSmartTime(timestamp: number): string {
  const date = new Date(timestamp);
  const now = new Date();
  /* 未来时间戳（时钟回拨）钳制为今天 HH:MM */
  if (timestamp > now.getTime()) {
    return `${date.getHours().toString().padStart(2, "0")}:${date.getMinutes().toString().padStart(2, "0")}`;
  }

  const time = `${date.getHours().toString().padStart(2, "0")}:${date.getMinutes().toString().padStart(2, "0")}`;
  /* 同一天 */
  if (date.toDateString() === now.toDateString()) {
    return time;
  }
  /* 昨天 */
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) {
    return `昨天 ${time}`;
  }
  /* 7天内：归零到当天 00:00:00，用日历日差比较 */
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const msgDayStart = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  const diffDays = Math.floor((todayStart - msgDayStart) / (1000 * 60 * 60 * 24));

  if (diffDays < 7 && diffDays >= 2) {
    const weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"];
    return `${weekdays[date.getDay()]} ${time}`;
  }
  /* 同年 */
  if (date.getFullYear() === now.getFullYear()) {
    return `${date.getMonth() + 1}/${date.getDate()} ${time}`;
  }
  /* 跨年 */
  return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()} ${time}`;
}