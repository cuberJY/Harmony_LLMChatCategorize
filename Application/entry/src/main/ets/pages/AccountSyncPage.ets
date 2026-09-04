/**
 * 账号登录（云空间同步状态）二级页
 *
 * 由设置主菜单「账号登录」进入。
 * 本应用不内置账号体系；云同步基于 AGC 云数据库（Cloud Foundation Kit），
 * 认证采用 AGC Auth 匿名登录（应用启动时自动完成，无需用户手动登录）。
 * 本页职责：
 *   - 展示当前云同步状态（已同步 / 未初始化 / 网络错误等）
 *   - 「立即同步」手动触发全量双向同步
 *   - 说明云同步机制与前提
 *
 * 云同步前提（需在 AGC 侧完成）：
 *   1. 已开通「认证服务」与「云数据库」
 *   2. agconnect-services.json 已放入 AppScope/resources/rawfile/
 *   3. schema.json 已生成（CloudDev 部署自动产出）
 *   4. 设备联网（WLAN/蜂窝）
 */

import { KeyboardAvoidMode } from "@kit.ArkUI";
import { SafeAreaHelper, showToast } from "../common/Utils";
import { SyncManager, SyncStatusCode, SyncStatusListener } from "../service/sync/SyncManager";

@ComponentV2
export struct AccountSyncPage {
  /* 路由栈（NavDestination.onReady 获取）：返回上一页 */
  private pathStack: NavPathStack = new NavPathStack();
  /* 当前同步状态码（初始未知；注册 SyncManager 监听后刷新） */
  @Local syncStatus: SyncStatusCode = SyncStatusCode.UNKNOWN;
  /* 是否正在手动同步（防连点） */
  @Local syncing: boolean = false;
  /* 沉浸式系统栏高度（vp）：aboutToAppear 一次性读取 */
  @Local statusBarHeightVp: number = 0;
  @Local navBarHeightVp: number = 0;
  private globalKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.RESIZE; // 记录全局避让模式
  /* SyncManager 状态回调（命名引用，aboutToDisappear 注销用） */
  private onSyncStatus: SyncStatusListener = (code: SyncStatusCode): void => {
    this.syncStatus = code;
  };

  aboutToAppear(): void {
    /* 读取系统栏高度（标题栏/内容区避让用） */
    this.statusBarHeightVp = SafeAreaHelper.getStatusBarHeight();
    this.navBarHeightVp = SafeAreaHelper.getNavBarHeight();
    this.globalKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    /* 注册同步状态监听（registerListener 会立即回调一次当前状态） */
    SyncManager.getInstance().registerListener(this.onSyncStatus);
  }

  aboutToDisappear(): void {
    /* 注销同步状态监听，防止回调泄漏 */
    SyncManager.getInstance().unregisterListener(this.onSyncStatus);
    /* 离开页面恢复全局避让模式 */
    this.getUIContext().setKeyboardAvoidMode(this.globalKeyboardAvoidMode);
  }

  build() {
    NavDestination() {
      Column() {
        /* 标题栏：返回键 + 居中标题（与现有页面规范一致） */
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

          Text("账号登录")
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

        Scroll() {
          Column() {
            /* 同步状态卡片 */
            Column() {
              Row() {
                SymbolGlyph(this.statusIcon())
                  .fontSize($r('app.float.font_icon_xxl'))
                  .fontWeight(500)
                  .fontColor([this.statusColor()])
                Text(SyncManager.statusText(this.syncStatus))
                  .fontSize($r('app.float.font_body'))
                  .fontColor($r('app.color.font_primary'))
                  .layoutWeight(1)
                  .textAlign(TextAlign.Start)
                  .margin({ left: $r('app.float.space_md') })
              }
              .width("100%")
              .alignItems(VerticalAlign.Center)

              Text("云同步基于 AGC 云数据库自动进行，应用回到前台会自动合并多设备数据。")
                .fontSize($r('app.float.font_body'))
                .fontColor($r('app.color.font_secondary'))
                .width("100%")
                .textAlign(TextAlign.Start)
                .margin({ top: $r('app.float.space_md') })
            }
            .width("100%")
            .padding($r('app.float.space_lg'))
            .backgroundColor($r('app.color.page_bg'))
            .borderRadius($r('app.float.setting_select_radius'))
            .borderWidth(1)
            .borderColor($r('app.color.input_border'))

            /* 立即同步按钮 */
            Button(this.syncing ? "同步中…" : "立即同步")
              .width("100%")
              .height($r('app.float.input_height'))
              .fontSize($r('app.float.font_button'))
              .fontColor(Color.White)
              .backgroundColor($r('app.color.brand'))
              .borderRadius(22)
              .margin({ top: $r('app.float.space_xl') })
              .enabled(!this.syncing)
              .onClick(() => {
                this.handleSyncNow();
              })

            /* 同步机制说明 */
            Text("云同步说明：\n1. 数据存储于 AGC 云数据库，多台设备登录后自动合并\n2. 应用回到前台会自动同步，也可点击「立即同步」手动触发\n3. 需设备联网（建议 WLAN）")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.font_secondary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .lineHeight($r('app.float.line_height_thinking'))
              .margin({ top: $r('app.float.space_lg') })
          }
          .width("100%")
          .padding({ left: $r('app.float.space_lg'), right: $r('app.float.space_lg') })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width("100%")
        .padding({ bottom: this.navBarHeightVp })
        .backgroundColor($r('app.color.page_bg'))
      }
      .width("100%")
      .height("100%");
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }

  /* 手动立即同步：SyncManager → CloudSyncService 全量双向同步 */
  private async handleSyncNow(): Promise<void> {
    if (this.syncing) {
      return;
    }
    this.syncing = true;
    const ok: boolean = await SyncManager.getInstance().syncNow();
    this.syncing = false;
    if (ok) {
      showToast(this.getUIContext(), $r('app.string.sync_started'));
    } else {
      showToast(this.getUIContext(), $r('app.string.sync_failed'));
    }
  }

  /* 状态图标（已同步 ✓ / 未初始化或异常 ⚠ / 未知 …） */
  private statusIcon(): Resource {
    if (this.syncStatus === SyncStatusCode.SYNCED) {
      return $r("sys.symbol.checkmark");
    }
    if (this.syncStatus === SyncStatusCode.UNKNOWN) {
      return $r("sys.symbol.clock");
    }
    return $r("sys.symbol.xmark");
  }

  /* 状态颜色：已同步 = 品牌色；异常 = 警示色；未知 = 次要色 */
  private statusColor(): Resource {
    if (this.syncStatus === SyncStatusCode.SYNCED) {
      return $r('app.color.brand');
    }
    if (this.syncStatus === SyncStatusCode.UNKNOWN) {
      return $r('app.color.font_secondary');
    }
    return $r('app.color.text_danger');
  }
}
