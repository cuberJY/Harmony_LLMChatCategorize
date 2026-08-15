/**
 * 后台长时任务保活服务（方案 A：dataTransfer 长时任务）
 * 背景：应用退后台约 2 秒网络被冻结、约 12 秒被释放，流式 SSE 连接会被掐断。
 * 后台且有流式任务时申请 dataTransfer 长时任务豁免冻结；任务结束或回前台时及时释放。
 * 前提（已在 module.json5 配置）：KEEP_BACKGROUND_RUNNING 权限 + backgroundModes ["dataTransfer"]。
 */
import { Context, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

/* 与 AppScope/app.json5 中的 bundleName 保持一致 */
const BUNDLE_NAME = 'com.cuberjy.chatcategorize';
const ABILITY_NAME = 'EntryAbility';

export class BackgroundRunGuardService {
  private static instance: BackgroundRunGuardService | null = null;
  private context: Context | null = null; // UIAbility 上下文（onCreate 时注入）
  private appInBackground: boolean = false;
  private streamingTaskCount: number = 0; // 进行中的流式任务数（ChatViewModel 同步）
  private continuousTaskActive: boolean = false;
  private syncInProgress: boolean = false; // 防止并发重入
  private syncAgainRequested: boolean = false; // 重入期间状态又变化，需再同步一次

  static getInstance(): BackgroundRunGuardService {
    if (BackgroundRunGuardService.instance === null) {
      BackgroundRunGuardService.instance = new BackgroundRunGuardService();
    }
    return BackgroundRunGuardService.instance;
  }

  initialize(context: Context): void {
    this.context = context;
  }

  /* EntryAbility.onForeground/onBackground 调用，切换后台状态 */
  onAppBackgroundChanged(inBackground: boolean): void {
    this.appInBackground = inBackground;
    this.syncContinuousTaskState();
  }

  /* ChatViewModel 在流任务登记/结束时调用，传入当前进行中的任务数 */
  updateStreamingTaskCount(count: number): void {
    this.streamingTaskCount = Math.max(0, count);
    this.syncContinuousTaskState();
  }

  /**
   * 同步长时任务状态：
   *   后台 + 有任务 → 启动长时任务（保活）
   *   前台 或 无任务 → 停止长时任务（释放）
   */
  private async syncContinuousTaskState(): Promise<void> {
    if (this.syncInProgress) {
      this.syncAgainRequested = true; // 正在同步中又来了新状态，结束后再补一次
      return;
    }
    this.syncInProgress = true;

    try {
      if (this.context === null) {
        return;
      }
      if (this.appInBackground && this.streamingTaskCount > 0) {
        await this.startContinuousTaskIfNeeded();
      } else {
        await this.stopContinuousTaskIfNeeded();
      }
    } finally {
      this.syncInProgress = false;
      if (this.syncAgainRequested) {
        this.syncAgainRequested = false;
        void this.syncContinuousTaskState();
      }
    }
  }

  private async startContinuousTaskIfNeeded(): Promise<void> {
    if (this.context === null || this.continuousTaskActive) {
      return;
    }
    try {
      const wantAgentObj = await this.createWantAgent();
      await backgroundTaskManager.startBackgroundRunning(this.context, ['dataTransfer'], wantAgentObj);
      this.continuousTaskActive = true;
      console.info('BackgroundRunGuard', 'startBackgroundRunning ok (dataTransfer)');
    } catch (error) {
      /* 申请失败不阻断流式本身，仅失去后台保活能力 */
      console.error('BackgroundRunGuard', `startBackgroundRunning failed: ${JSON.stringify(error)}`);
    }
  }

  private async stopContinuousTaskIfNeeded(): Promise<void> {
    if (this.context === null || !this.continuousTaskActive) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context);
      this.continuousTaskActive = false;
      console.info('BackgroundRunGuard', 'stopBackgroundRunning ok');
    } catch (error) {
      console.error('BackgroundRunGuard', `stopBackgroundRunning failed: ${JSON.stringify(error)}`);
    }
  }

  /* 构造 WantAgent：长时任务通知被点击时拉起应用 */
  private async createWantAgent(): Promise<WantAgent> {
    const wantInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: BUNDLE_NAME,
          abilityName: ABILITY_NAME
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 100,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    try {
      return await wantAgent.getWantAgent(wantInfo);
    } catch (error) {
      console.error('BackgroundRunGuard', `createWantAgent failed: ${JSON.stringify(error)}`);
      throw new Error(`createWantAgent failed: ${JSON.stringify(error)}`);
    }
  }
}
