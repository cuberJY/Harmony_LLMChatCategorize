/**
 * 应用入口 Ability
 * onCreate 预加载配置并初始化后台保活服务；onWindowStageCreate 设置键盘避让模式
 */
import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import { AppConfig } from '../config/AppConfig';
import { BackgroundRunGuardService } from '../service/BackgroundRunGuardService';
import { registerGlobalUiContext } from '../common/Utils';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  /* 主窗口引用（系统栏内容色随深浅色切换动态更新用；窗口销毁时置空） */
  private mainWindow?: window.Window;

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

    const mainWindow = windowStage.getMainWindowSync();
    this.mainWindow = mainWindow;
    /**
     * 沉浸式窗口（颜色沉浸）：
     * 1. 全屏布局：页面内容延伸到状态栏与底部导航条区域（edge-to-edge）
     * 2. 系统栏背景透明：露出页面自身背景（标题栏 title_bar_bg / 页面 page_bg），
     *    由各页面 .expandSafeArea 将背景真正铺到系统栏背后，实现"融为一体"
     * 3. 系统栏内容色随深浅色主题切换（见 applySystemBarStyle）
     */
    mainWindow.setWindowLayoutFullScreen(true);
    /* 按当前 colorMode 设置系统栏内容色（跟随系统模式下此处返回实际模式；未定义时按非深色兜底） */
    this.applySystemBarStyle(this.context.config.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);

    windowStage.loadContent('pages/HomePage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

      /* 注册全局 UIContext：ViewModel 等非组件层调用 showToast 时使用（替代废弃的 promptAction）。 */
      registerGlobalUiContext(mainWindow.getUIContext());

      /**
       * 将状态栏/导航条高度（vp）存入 AppStorage：各页面用显式 padding 避让系统栏。
       * 说明：expandSafeArea 在固定高度组件上只会"上移+尺寸不变"，safeAreaPadding 避让会失效，
       * 故改用真实系统栏高度做手动 padding，保证内容不被状态栏/导航条遮挡
       */
      const systemAvoid = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      AppStorage.setOrCreate('statusBarHeightVp', mainWindow.getUIContext().px2vp(systemAvoid.topRect.height));
      AppStorage.setOrCreate('navBarHeightVp', mainWindow.getUIContext().px2vp(systemAvoid.bottomRect.height));

      /* 设置键盘避让模式为 RESIZE */
      mainWindow.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    /* 窗口销毁：释放主窗口引用，避免后续配置变化时操作已失效窗口 */
    this.mainWindow = undefined;
  }

  /**
   * 按当前深浅色模式设置系统栏内容色（深色模式适配核心）：
   * - 背景色恒为透明：露出页面自身的深/浅背景（标题栏/输入区等）
   * - 内容色随主题切换：浅色=深字(#1A1A1A)，深色=浅字(#FFFFFF)，
   *   保证深色模式下状态栏时间/电量图标与导航条手势条不会"隐形"
   */
  private applySystemBarStyle(colorMode: number): void {
    if (this.mainWindow === undefined) {
      return; // 窗口未创建（如启动早期配置变化），onWindowStageCreate 时会再按最新模式设置
    }
    const isDark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    this.mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000', // 状态栏背景透明（露出页面背景）
      statusBarContentColor: isDark ? '#FFFFFF' : '#1A1A1A', // 状态栏内容
      navigationBarColor: '#00000000', // 底部导航条背景透明
      navigationBarContentColor: isDark ? '#FFFFFF' : '#1A1A1A', // 导航条手势条
    });
  }

  /**
   * 系统配置更新回调（深色/浅色切换等）：
   * 动态更新系统栏内容色，使状态栏/导航条与页面主题保持同步；
   * 同时把最新 colorMode 写入 AppStorage，供页面侧按需查询
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onConfigurationUpdate');
    this.applySystemBarStyle(newConfig.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    AppStorage.setOrCreate('currentColorMode', newConfig.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
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