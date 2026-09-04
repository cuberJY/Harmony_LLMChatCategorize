/**
 * 设置页面（主菜单）
 *
 * 设置页重构：由「单页表单」改为「列表式主菜单」，与主流 App 一致。
 * 当前仅保留两个设置项（其余项后续按需追加）：
 *   - 模型配置  → 二级页 ModelConfigPage（供应商/模型/API Key 表单）
 *   - 账号登录  → 二级页 AccountSyncPage（华为云空间同步状态与引导）
 *
 * 导航：本页为 NavDestination（由 SideBarPage pushPathByName 进入），
 * 二级页通过 NavPathStack.pushPathByName 再入栈，返回用 pop()。
 */

import { common } from "@kit.AbilityKit";
import { KeyboardAvoidMode } from "@kit.ArkUI";
import { AppConfig } from "../config/AppConfig";
import { SafeAreaHelper } from "../common/Utils";

@ComponentV2
export struct SettingsPage {
  /* 路由栈（NavDestination.onReady 获取）：返回上一页 / 跳转二级设置页 */
  private pathStack: NavPathStack = new NavPathStack();
  /* 沉浸式系统栏高度（vp，EntryAbility 注入）：aboutToAppear 一次性读取 */
  @Local statusBarHeightVp: number = 0;
  @Local navBarHeightVp: number = 0;
  private globalKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.RESIZE; // 记录全局避让模式

  aboutToAppear(): void {
    /* 读取系统栏高度（标题栏/内容区避让用） */
    this.statusBarHeightVp = SafeAreaHelper.getStatusBarHeight();
    this.navBarHeightVp = SafeAreaHelper.getNavBarHeight();
    /* 键盘避让：记住全局模式后固定 RESIZE（上层页面可能切成 NONE，返回时恢复） */
    this.globalKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    /* 确保配置已加载（主菜单展示当前模型名需要） */
    const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppConfig.getInstance().init(hostContext);
  }

  aboutToDisappear(): void {
    /* 离开页面恢复全局避让模式（上层页面期望 NONE，保持其行为不变） */
    this.getUIContext().setKeyboardAvoidMode(this.globalKeyboardAvoidMode);
  }

  build() {
    NavDestination() {
      Column() {
        /* 标题栏：返回键 + 居中标题 */
        Row() {
          Row() {
            SymbolGlyph($r("sys.symbol.chevron_left"))
              .fontSize($r('app.float.font_icon_xxl'))
              .fontWeight(700)
              .fontColor([$r('app.color.font_primary')])
          }
          .width(40)
          .justifyContent(FlexAlign.Start)
          .onClick(() => {
            this.pathStack.pop();
          })

          Text("设置")
            .fontSize($r('app.float.font_title'))
            .fontWeight(700)
            .fontColor($r('app.color.font_primary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Row().width(40)
        }
        .width("100%")
        .height(SafeAreaHelper.getTitleBarHeight(this.getUIContext()) + this.statusBarHeightVp)
        .padding({
          top: this.statusBarHeightVp,
          left: $r('app.float.space_xl'),
          right: $r('app.float.space_xl'),
        })
        .backgroundColor($r('app.color.title_bar_bg'))
        .border({
          width: { bottom: 2 },
          color: { bottom: $r('app.color.divider') },
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

        /* 设置项列表（主菜单） */
        List() {
          ListItem() {
            this.settingRow(
              $r("sys.symbol.gearshape"),
              "模型配置",
              AppConfig.getInstance().getConfig().model.length > 0
                ? AppConfig.getInstance().getModel()
                : "",
              () => {
                this.pathStack.pushPathByName("ModelConfigPage", undefined);
              },
            )
          }

          ListItem() {
            this.settingRow(
              $r("sys.symbol.person"),
              "账号登录",
              "华为账号云同步",
              () => {
                this.pathStack.pushPathByName("AccountSyncPage", undefined);
              },
            )
          }
        }
        .width("100%")
        .layoutWeight(1)
        .backgroundColor($r('app.color.page_bg'))
        .divider({ strokeWidth: 1, color: $r('app.color.divider') })
      }
      .width("100%")
      .height("100%");
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }

  /**
   * 设置项行：图标 + 标题 + 副标题（右侧箭头）
   * @param icon     系统图标（sys.symbol）
   * @param title    设置项标题
   * @param subtitle 副标题（模型名 / 说明；空串不显示）
   * @param onClick  点击回调（跳转二级页）
   */
  @Builder
  settingRow(icon: Resource, title: string, subtitle: string, onClick: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize($r('app.float.font_icon_lg'))
        .fontWeight(500)
        .fontColor([$r('app.color.font_primary')])
        .width(40)

      Text(title)
        .fontSize($r('app.float.font_body'))
        .fontColor($r('app.color.font_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Start)

      if (subtitle.length > 0) {
        Text(subtitle)
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      SymbolGlyph($r("sys.symbol.chevron_right"))
        .fontSize($r('app.float.font_icon_sm'))
        .fontWeight(400)
        .fontColor([$r('app.color.font_secondary')])
        .margin({ left: $r('app.float.space_xs') })
    }
    .width("100%")
    .height(56)
    .padding({ left: $r('app.float.space_lg'), right: $r('app.float.space_lg') })
    .alignItems(VerticalAlign.Center)
    .onClick(onClick)
  }
}
