/**
 * 应用入口 Ability
 * onCreate 预加载配置并初始化后台保活服务；onWindowStageCreate 设置键盘避让模式
 */
import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import { AppConfig } from '../config/AppConfig';
import { BackgroundRunGuardService } from '../service/BackgroundRunGuardService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    /* 预加载用户配置（Preferences），页面使用配置时已就绪 */
    AppConfig.getInstance().init(this.context);
    /* 初始化后台长时任务保活服务（流式期间退后台保持网络连接） */
    BackgroundRunGuardService.getInstance().initialize(this.context);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }
  

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/HomePage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

      /* 设置键盘避让模式为 RESIZE */
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    /* 回到前台：通知保活服务（停止长时任务，恢复正常状态） */
    BackgroundRunGuardService.getInstance().onAppBackgroundChanged(false);
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    /* 退到后台：若仍有流式任务，由保活服务自动申请长时任务 */
    BackgroundRunGuardService.getInstance().onAppBackgroundChanged(true);
  }
}