/**
 * 设置页面
 * 用户在此填写 AI API 配置：
 *   - API 地址、API Key、模型名称（必填，用于对话）
 *   - 搜索 API 地址、搜索 API 密钥（可选，用于联网搜索）
 * 点击"保存"后持久化到 Preferences，返回主页面
 */

import { router, promptAction } from "@kit.ArkUI";
import { AppConfig } from "../config/AppConfig";
import { COLORS, FONT_SIZES, SPACING } from "../common/AppConstants";

@Entry
@Component
struct SettingsPage {
  // 表单状态（初始值取自 AppConfig，保证编辑时能看到已保存的值）
  @State baseUrl: string = "";
  @State apiKey: string = "";
  @State model: string = "";
  @State searchBaseUrl: string = "";
  @State searchApiKey: string = "";

  aboutToAppear(): void {
    // 回显已保存的配置
    const config = AppConfig.getInstance().getConfig();
    this.baseUrl = config.baseUrl;
    this.apiKey = config.apiKey;
    this.model = config.model;
    this.searchBaseUrl = config.searchBaseUrl;
    this.searchApiKey = config.searchApiKey;
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        // 返回按钮
        Row() {
          SymbolGlyph($r("sys.symbol.chevron_left"))
            .fontSize(FONT_SIZES.ICON_XL)
            .fontWeight(700)
            .fontColor([Color.Black])
        }
        .width(40)
        .justifyContent(FlexAlign.Start)
        .onClick(() => {
          router.back();
        })
        
        // 标题
        Text("设置")
          .fontSize(FONT_SIZES.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        // 右侧占位（保持对称）
        Row()
          .width(40)
      }
      .width("100%")
      .height(SPACING.TITLE_BAR_HEIGHT)
      .padding({ left: SPACING.XL, right: SPACING.XL })
      .backgroundColor(COLORS.TITLE_BAR_BG)
      .border({
        width: { bottom: 1 },
        color: { bottom: COLORS.DIVIDER },
      })

      // 表单区域
      Scroll() {
        Column() {
          // 必填区：AI 对话配置
          Text("AI 对话配置（必填）")
            .fontSize(FONT_SIZES.MODEL_NAME)
            .fontColor(COLORS.TEXT_SECONDARY)
            .width("100%")
            .textAlign(TextAlign.Start)
            .margin({ top: SPACING.MD, bottom: SPACING.SM })

          // API 地址
          Text("API 地址")
            .fontSize(FONT_SIZES.BODY)
            .fontColor(COLORS.TEXT_PRIMARY)
            .width("100%")
            .textAlign(TextAlign.Start)
            .margin({ bottom: SPACING.XS })

          TextInput({ placeholder: "https://api.deepseek.com/chat/completions", text: this.baseUrl })
            .fontSize(FONT_SIZES.INPUT)
            .fontColor(COLORS.TEXT_PRIMARY)
            .placeholderColor(COLORS.TEXT_SECONDARY)
            .backgroundColor(COLORS.PAGE_BG)
            .borderRadius(10)
            .borderWidth(1)
            .borderColor(COLORS.INPUT_BORDER)
            .padding({ left: SPACING.MD, right: SPACING.MD })
            .margin({ bottom: SPACING.MD })
            .onChange((value: string) => {
              this.baseUrl = value;
            })

          // API Key
          Text("API Key")
            .fontSize(FONT_SIZES.BODY)
            .fontColor(COLORS.TEXT_PRIMARY)
            .width("100%")
            .textAlign(TextAlign.Start)
            .margin({ bottom: SPACING.XS })

          TextInput({ placeholder: "sk-xxxxxxxxxxxxxxxxxxxxxxxx", text: this.apiKey })
            .fontSize(FONT_SIZES.INPUT)
            .fontColor(COLORS.TEXT_PRIMARY)
            .placeholderColor(COLORS.TEXT_SECONDARY)
            .backgroundColor(COLORS.PAGE_BG)
            .borderRadius(10)
            .borderWidth(1)
            .borderColor(COLORS.INPUT_BORDER)
            .padding({ left: SPACING.MD, right: SPACING.MD })
            .margin({ bottom: SPACING.MD })
            .type(InputType.Password) // 密码输入，防偷窥
            .onChange((value: string) => {
              this.apiKey = value;
            })

          // 模型名称
          Text("模型名称")
            .fontSize(FONT_SIZES.BODY)
            .fontColor(COLORS.TEXT_PRIMARY)
            .width("100%")
            .textAlign(TextAlign.Start)
            .margin({ bottom: SPACING.XS })

          TextInput({ placeholder: "deepseek-v4-flash", text: this.model })
            .fontSize(FONT_SIZES.INPUT)
            .fontColor(COLORS.TEXT_PRIMARY)
            .placeholderColor(COLORS.TEXT_SECONDARY)
            .backgroundColor(COLORS.PAGE_BG)
            .borderRadius(10)
            .borderWidth(1)
            .borderColor(COLORS.INPUT_BORDER)
            .padding({ left: SPACING.MD, right: SPACING.MD })
            .onChange((value: string) => {
              this.model = value;
            })

          // 可选区：联网搜索配置
          Text("联网搜索配置（可选）")
            .fontSize(FONT_SIZES.MODEL_NAME)
            .fontColor(COLORS.TEXT_SECONDARY)
            .width("100%")
            .textAlign(TextAlign.Start)
            .margin({ top: SPACING.XL, bottom: SPACING.SM })

          Text("搜索 API 地址")
            .fontSize(FONT_SIZES.BODY)
            .fontColor(COLORS.TEXT_PRIMARY)
            .width("100%")
            .textAlign(TextAlign.Start)
            .margin({ bottom: SPACING.XS })

          TextInput({ placeholder: "https://api.bochaai.com/v1/web-search", text: this.searchBaseUrl })
            .fontSize(FONT_SIZES.INPUT)
            .fontColor(COLORS.TEXT_PRIMARY)
            .placeholderColor(COLORS.TEXT_SECONDARY)
            .backgroundColor(COLORS.PAGE_BG)
            .borderRadius(10)
            .borderWidth(1)
            .borderColor(COLORS.INPUT_BORDER)
            .padding({ left: SPACING.MD, right: SPACING.MD })
            .margin({ bottom: SPACING.MD })
            .onChange((value: string) => {
              this.searchBaseUrl = value;
            })

          Text("搜索 API 密钥")
            .fontSize(FONT_SIZES.BODY)
            .fontColor(COLORS.TEXT_PRIMARY)
            .width("100%")
            .textAlign(TextAlign.Start)
            .margin({ bottom: SPACING.XS })

          TextInput({ placeholder: "sk-xxxxxxxx（留空则不校验）", text: this.searchApiKey })
            .fontSize(FONT_SIZES.INPUT)
            .fontColor(COLORS.TEXT_PRIMARY)
            .placeholderColor(COLORS.TEXT_SECONDARY)
            .backgroundColor(COLORS.PAGE_BG)
            .borderRadius(10)
            .borderWidth(1)
            .borderColor(COLORS.INPUT_BORDER)
            .padding({ left: SPACING.MD, right: SPACING.MD })
            .type(InputType.Password)
            .onChange((value: string) => {
              this.searchApiKey = value;
            })

          // 保存按钮
          Button("保存")
            .width("100%")
            .height(44)
            .fontSize(FONT_SIZES.BUTTON)
            .fontColor(Color.White)
            .backgroundColor(COLORS.PRIMARY)
            .borderRadius(22)
            .margin({ top: SPACING.XL })
            .onClick(() => {
              this.handleSave();
            })
        }
        .width("100%")
        .padding({ left: SPACING.MD, right: SPACING.MD })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width("100%")
      .backgroundColor(COLORS.PAGE_BG)
    }
    .width("100%")
    .height("100%");
  }

  // 保存按钮逻辑：校验必填项 → 持久化 → 提示并返回

  private async handleSave(): Promise<void> {
    const config = AppConfig.getInstance();

    // 必填校验：AI 对话配置三项不能为空
    if (this.baseUrl.trim().length === 0
      || this.apiKey.trim().length === 0
      || this.model.trim().length === 0) {
      promptAction.showToast({ message: "请填写完整的 AI 对话配置" });
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

    promptAction.showToast({ message: "保存成功" });
    // 延时返回，让 Toast 可见
    setTimeout(() => {
      router.back();
    }, 500);
  }
}