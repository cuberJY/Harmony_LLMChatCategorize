/**
 * 统一日志封装
 * 基于 @kit.PerformanceAnalysisKit 的 hilog
 * 全局统一 domain 与 tag，替换散落的 console.error，便于按模块过滤与定位
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

// 应用日志域：0x0000~0xFFFF 为应用自定义范围，与 EntryAbility 保持一致
const DOMAIN: number = 0x0000;
// 统一日志标签，便于 adb/hdc hilog 按 tag 过滤
const TAG: string = 'ChatCategorize';

export class Logger {
  static info(message: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', message);
  }

  static warn(message: string): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', message);
  }

  static error(message: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', message);
  }

  static debug(message: string): void {
    hilog.debug(DOMAIN, TAG, '%{public}s', message);
  }
}
