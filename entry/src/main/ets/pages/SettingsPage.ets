/**
 * 设置页面
 * 用户在此填写 AI API 配置：
 *   - API 地址、API Key、模型名称（必填，用于对话）
 *   - 搜索 API 地址、搜索 API 密钥（可选，用于联网搜索）
 * 点击"保存"后持久化到 Preferences，返回主页面
 *
 * 阶段四：Navigation 路由重构
 * - 不再作为 @Entry 页面，由 HomePage 的 Navigation 以 NavDestination 形式承载
 * - 返回操作使用 NavPathStack.pop()
 */

import { KeyboardAvoidMode } from "@kit.ArkUI";
import { AppConfig } from "../config/AppConfig";
import { showToast } from "../common/Utils";

@ComponentV2
export struct SettingsPage {
  // 路由栈（NavDestination.onReady 获取）：返回上一页
  private pathStack: NavPathStack = new NavPathStack();
  // 表单状态（初始值取自 AppConfig，保证编辑时能看到已保存的值）
  @Local baseUrl: string = "";
  @Local apiKey: string = "";
  @Local model: string = "";
  @Local searchBaseUrl: string = "";
  @Local searchApiKey: string = "";
  private saveTimerId: number = -1; // 保存后返回的定时器，离开页面时清理
  private globalKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.RESIZE;

  aboutToAppear(): void {
    // 输入法避让：本页是表单页，切到"上抬"模式（键盘弹出时页面整体上抬，保证当前输入框不被遮挡）
    this.globalKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode(); // 记录进入前的模式
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);

    // 回显已保存的配置
    const config = AppConfig.getInstance().getConfig();
    this.baseUrl = config.baseUrl;
    this.apiKey = config.apiKey;
    this.model = config.model;
    this.searchBaseUrl = config.searchBaseUrl;
    this.searchApiKey = config.searchApiKey;
  }

  aboutToDisappear(): void {
    // 离开页面时清理返回定时器，避免越层返回
    if (this.saveTimerId !== -1) {
      clearTimeout(this.saveTimerId);
      this.saveTimerId = -1;
    }
    // 离开页面时恢复全局压缩模式
    this.getUIContext().setKeyboardAvoidMode(this.globalKeyboardAvoidMode);
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部标题栏
        Row() {
          // 返回按钮
          Row() {
            SymbolGlyph($r("sys.symbol.chevron_left"))
              .fontSize($r('app.float.font_icon_xl'))
              .fontWeight(700)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(40)
          .justifyContent(FlexAlign.Start)
          .onClick(() => {
            this.pathStack.pop();
          })

          // 标题
          Text("设置")
            .fontSize($r('app.float.font_title'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          // 右侧占位（保持对称）
          Row().width(40)
        }
        .width("100%")
        .height($r('app.float.title_bar_height'))
        .padding({ left: $r('app.float.space_xl'), right: $r('app.float.space_xl') })
        .backgroundColor($r('app.color.title_bar_bg'))
        .border({
          width: { bottom: 1 },
          color: { bottom: $r('app.color.divider') },
        })
        // 上抬避让时让标题栏保持原位，不被键盘顶出屏幕
        .expandSafeArea([SafeAreaType.KEYBOARD])

        // 表单区域
        Scroll() {
          Column() {
            // 必填区：AI 对话配置
            Text("AI 对话配置（必填）")
              .fontSize($r('app.float.font_model_name'))
              .fontColor($r('app.color.text_secondary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ top: $r('app.float.space_md'), bottom: $r('app.float.space_sm') })

            // API 地址
            Text("API 地址")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_primary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ bottom: $r('app.float.space_xs') })
            TextInput({
              placeholder: "https://api.deepseek.com/chat/completions",
              text: this.baseUrl,
            })
              .fontSize($r('app.float.font_input'))
              .fontColor($r('app.color.text_primary'))
              .placeholderColor($r('app.color.text_secondary'))
              .backgroundColor($r('app.color.page_bg'))
              .borderRadius(10)
              .borderWidth(1)
              .borderColor($r('app.color.input_border'))
              .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md') })
              .margin({ bottom: $r('app.float.space_md') })
              .onChange((value: string) => {
                this.baseUrl = value;
              })

            // API Key
            Text("API Key")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_primary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ bottom: $r('app.float.space_xs') })
            TextInput({ placeholder: "sk-xxxxxxxxxxxxxxxxxxxxxxxx", text: this.apiKey })
              .fontSize($r('app.float.font_input'))
              .fontColor($r('app.color.text_primary'))
              .placeholderColor($r('app.color.text_secondary'))
              .backgroundColor($r('app.color.page_bg'))
              .borderRadius(10)
              .borderWidth(1)
              .borderColor($r('app.color.input_border'))
              .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md') })
              .margin({ bottom: $r('app.float.space_md') })
              .type(InputType.Password)
              // 密码输入，防偷窥
              .onChange((value: string) => {
                this.apiKey = value;
              })

            // 模型名称
            Text("模型名称")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_primary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ bottom: $r('app.float.space_xs') })
            TextInput({ placeholder: "deepseek-v4-flash", text: this.model })
              .fontSize($r('app.float.font_input'))
              .fontColor($r('app.color.text_primary'))
              .placeholderColor($r('app.color.text_secondary'))
              .backgroundColor($r('app.color.page_bg'))
              .borderRadius(10)
              .borderWidth(1)
              .borderColor($r('app.color.input_border'))
              .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md') })
              .onChange((value: string) => {
                this.model = value;
              })

            // 可选区：联网搜索配置
            Text("联网搜索配置（可选）")
              .fontSize($r('app.float.font_model_name'))
              .fontColor($r('app.color.text_secondary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ top: $r('app.float.space_xl'), bottom: $r('app.float.space_sm') })
            Text("搜索 API 地址")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_primary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ bottom: $r('app.float.space_xs') })
            TextInput({
              placeholder: "https://api.bochaai.com/v1/web-search",
              text: this.searchBaseUrl,
            })
              .fontSize($r('app.float.font_input'))
              .fontColor($r('app.color.text_primary'))
              .placeholderColor($r('app.color.text_secondary'))
              .backgroundColor($r('app.color.page_bg'))
              .borderRadius(10)
              .borderWidth(1)
              .borderColor($r('app.color.input_border'))
              .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md') })
              .margin({ bottom: $r('app.float.space_md') })
              .onChange((value: string) => {
                this.searchBaseUrl = value;
              })
            Text("搜索 API 密钥")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_primary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ bottom: $r('app.float.space_xs') })
            TextInput({ placeholder: "sk-xxxxxxxxxxxx（留空则不校验）", text: this.searchApiKey })
              .fontSize($r('app.float.font_input'))
              .fontColor($r('app.color.text_primary'))
              .placeholderColor($r('app.color.text_secondary'))
              .backgroundColor($r('app.color.page_bg'))
              .borderRadius(10)
              .borderWidth(1)
              .borderColor($r('app.color.input_border'))
              .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md') })
              .type(InputType.Password)
              .onChange((value: string) => {
                this.searchApiKey = value;
              })

            // 保存按钮
            Button("保存")
              .width("100%")
              .height(44)
              .fontSize($r('app.float.font_button'))
              .fontColor(Color.White)
              .backgroundColor($r('app.color.primary'))
              .borderRadius(22)
              .margin({ top: $r('app.float.space_xl') })
              .onClick(() => {
                this.handleSave();
              })
          }
          .width("100%")
          .padding({ left: $r('app.float.space_lg'), right: $r('app.float.space_lg') })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width("100%")
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

  // 保存按钮逻辑：校验必填项 → 持久化 → 提示并返回

  private async handleSave(): Promise<void> {
    const config = AppConfig.getInstance();

    // 必填校验：AI 对话配置三项不能为空
    if (
      this.baseUrl.trim().length === 0 ||
      this.apiKey.trim().length === 0 ||
      this.model.trim().length === 0
    ) {
      showToast($r('app.string.config_incomplete'));
      return;
    }

    // 保存（内部持久化到 Preferences）
    await config.updateConfig(
      this.baseUrl.trim(),
      this.apiKey.trim(),
      this.model.trim(),
      this.searchBaseUrl.trim(),
      this.searchApiKey.trim(),
    );

    showToast($r('app.string.save_success'));
    // 延时返回，让 Toast 可见（记录定时器便于离开页面时清理）
    this.saveTimerId = setTimeout(() => {
      this.saveTimerId = -1;
      this.pathStack.pop();
    }, 500);
  }
}
