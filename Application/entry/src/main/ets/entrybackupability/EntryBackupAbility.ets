/**
 * 备份/恢复扩展 Ability
 * 备份与恢复 Preferences 配置与关系型数据库文件，文件命名与 DatabaseHelper / AppConfig 保持一致
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const DOMAIN = 0x0000;
/* 与 DatabaseHelper / AppConfig 中的命名保持一致 */
const DB_FILE = 'chatcategorize.db';
const PREFS_FILE = 'chatcategorize_config';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    try {
      const dest = this.context.backupDir; // 备份目录（系统提供）
      /* 1. Preferences 文件（providerId / model 明文配置） */
      await this.copyFileIfExists(
        `${this.context.preferencesDir}/${PREFS_FILE}`,
        `${dest}/${PREFS_FILE}`);
      /* 2. 关系型数据库（对话/消息/文件夹） */
      await this.copyFileIfExists(
        `${this.context.databaseDir}/rdb/${DB_FILE}`,
        `${dest}/${DB_FILE}`);
      hilog.info(DOMAIN, 'testTag', 'onBackup ok');
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'onBackup failed: %{public}s', JSON.stringify(e));
    }
  }

  async onRestore(bundleVersion: BundleVersion) {
    try {
      const src = this.context.backupDir;
      /* 反向拷贝：先确保目标目录存在 */
      try {
        fs.mkdirSync(this.context.preferencesDir, true);
        fs.mkdirSync(`${this.context.databaseDir}/rdb`, true);
      } catch (e) {
        /* 目录已存在等场景可忽略 */
      }
      await this.copyFileIfExists(`${src}/${PREFS_FILE}`, `${this.context.preferencesDir}/${PREFS_FILE}`);
      await this.copyFileIfExists(`${src}/${DB_FILE}`, `${this.context.databaseDir}/rdb/${DB_FILE}`);
      hilog.info(DOMAIN, 'testTag', 'onRestore ok %{public}s', JSON.stringify(bundleVersion));
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'onRestore failed: %{public}s', JSON.stringify(e));
    }
  }

  private async copyFileIfExists(from: string, to: string): Promise<void> {
    try {
      await fs.copyFile(from, to);
    } catch (e) {
      /* 源不存在或拷贝失败：单文件失败不阻断备份流程 */
      hilog.warn(DOMAIN, 'testTag', `copy file failed: ${from}`);
    }
  }
}
