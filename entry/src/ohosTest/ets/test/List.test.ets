import { describe, expect, it } from '@ohos/hypium';
import { getGroupName, formatSmartTime } from '../../../main/ets/common/TimeUtil';
import { generateId } from '../../../main/ets/common/Utils';

// 时间工具纯函数测试
// 用例基于相对当前时刻的时间偏移，验证"今天/昨天/7天内/30天内/更早"分组与智能时间格式化
export default function testsuite() {
  describe('TimeUtilTest', () => {
    it('getGroupName_today', 0, () => {
      // 当前时刻 → 今天
      expect(getGroupName(Date.now())).assertEqual('今天');
    });

    it('getGroupName_yesterday', 0, () => {
      // 24 小时前 → 昨天
      expect(getGroupName(Date.now() - 24 * 3600 * 1000)).assertEqual('昨天');
    });

    it('getGroupName_within7Days', 0, () => {
      // 3 天前 → 7天内
      expect(getGroupName(Date.now() - 3 * 24 * 3600 * 1000)).assertEqual('7天内');
    });

    it('getGroupName_within30Days', 0, () => {
      // 15 天前 → 30天内
      expect(getGroupName(Date.now() - 15 * 24 * 3600 * 1000)).assertEqual('30天内');
    });

    it('getGroupName_olderThan30Days', 0, () => {
      // 60 天前 → 年月格式（如 "2026年6月"）
      const name = getGroupName(Date.now() - 60 * 24 * 3600 * 1000);
      expect(/^\d{4}年\d{1,2}月$/.test(name)).assertTrue();
    });

    it('formatSmartTime_today', 0, () => {
      // 今天 → 仅显示 HH:MM
      const time = formatSmartTime(Date.now());
      expect(/^\d{2}:\d{2}$/.test(time)).assertTrue();
    });

    it('formatSmartTime_yesterday', 0, () => {
      // 24 小时前 → 以"昨天"开头
      const time = formatSmartTime(Date.now() - 24 * 3600 * 1000);
      expect(time.startsWith('昨天')).assertTrue();
    });

    it('formatSmartTime_withinWeek', 0, () => {
      // 3 天前 → 以"星期"开头（同日历周的星期几）
      const time = formatSmartTime(Date.now() - 3 * 24 * 3600 * 1000);
      expect(time.startsWith('星期')).assertTrue();
    });

    it('formatSmartTime_older', 0, () => {
      // 40 天前 → 含"/"（月/日 或 年/月/日 格式）
      const time = formatSmartTime(Date.now() - 40 * 24 * 3600 * 1000);
      expect(time.includes('/')).assertTrue();
    });
  });

  describe('UtilsTest', () => {
    it('generateId_notEmpty', 0, () => {
      // 生成的 id 非空
      expect(generateId().length > 0).assertTrue();
    });

    it('generateId_unique', 0, () => {
      // 连续生成两次结果不同（毫秒时间戳 + 随机串）
      const a = generateId();
      const b = generateId();
      expect(a !== b).assertTrue();
    });
  });
}
