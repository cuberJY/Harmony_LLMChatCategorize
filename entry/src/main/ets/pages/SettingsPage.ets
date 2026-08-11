/**
 * 设置页面
 * 用户在此配置 AI 供应商：
 *   - 供应商选择（下拉，目前仅 DeepSeek）：自动带出该供应商的模型列表与 API 地址
 *   - 模型名称选择（下拉，由所选供应商的 ModelPresets.models 提供）
 *   - API Key（必填，用于对话）
 * 点击"保存"后持久化到 Preferences，返回主页面
 *
 * 模型配置预设化
 * - 不再手动填写 API 地址 / 模型名称，改为"供应商 + 模型"两级下拉选择（providerId / model 持久化）
 * - baseUrl / 模型列表由 ModelPresets 预设推导，后续接入多模型只需追加预设
 * - 移除联网搜索配置（博查）：搜索已迁移至 LLM 服务端 web_search 工具
 *
 * Navigation 路由重构
 * - 不再作为 @Entry 页面，由 HomePage 的 Navigation 以 NavDestination 形式承载
 * - 返回操作使用 NavPathStack.pop()
 */

import { KeyboardAvoidMode } from "@kit.ArkUI";
import { AppConfig } from "../config/AppConfig";
import { MODEL_PRESETS, getModelPreset } from "../config/ModelPresets";
import { showToast } from "../common/Utils";

@ComponentV2
export struct SettingsPage {
  // 路由栈（NavDestination.onReady 获取）：返回上一页
  private pathStack: NavPathStack = new NavPathStack();
  // 表单状态（初始值取自 AppConfig，保证编辑时能看到已保存的值）
  @Local providerId: string = "";
  @Local selectedIndex: number = 0; // 供应商下拉当前选中项索引
  @Local selectedModel: string = ""; // 模型下拉当前选中的模型名
  @Local modelIndex: number = 0; // 模型下拉当前选中项索引
  @Local apiKey: string = "";
  private saveTimerId: number = -1; // 保存后返回的定时器，离开页面时清理
  private globalKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.RESIZE;

  aboutToAppear(): void {
    // 输入法避让：本页是表单页，切到"上抬"模式（键盘弹出时页面整体上抬，保证当前输入框不被遮挡）
    this.globalKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode(); // 记录进入前的模式
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);

    // 回显已保存的配置
    const config = AppConfig.getInstance().getConfig();
    this.providerId = config.providerId;
    // 根据已保存的供应商定位下拉选中项（找不到时回退第一项）
    const idx = MODEL_PRESETS.findIndex((p) => p.id === this.providerId);
    this.selectedIndex = idx >= 0 ? idx : 0;
    // 模型：回显已保存的模型名；无记录或不属于当前供应商时回退默认模型
    this.selectedModel =
      config.model.length > 0 ? config.model : getModelPreset(this.providerId).defaultModel;
    const midx = getModelPreset(this.providerId).models.indexOf(this.selectedModel);
    this.modelIndex = midx >= 0 ? midx : 0;
    this.apiKey = config.apiKey;
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
            .fontWeight(700)
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
            // 供应商选择
            Text("供应商")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_primary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ bottom: $r('app.float.space_xs') })
            Select(this.buildSelectOptions())
              .selected(this.selectedIndex)
              .value(this.getProviderName())
              .font({ size: $r('app.float.font_input') })
              .fontColor($r('app.color.text_primary'))
              .selectedOptionFont({ size: $r('app.float.font_input') })
              .selectedOptionFontColor($r('app.color.text_primary'))
              .optionFont({ size: $r('app.float.font_input') })
              .optionFontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.page_bg'))
              .borderRadius(10)
              .borderWidth(1)
              .borderColor($r('app.color.input_border'))
              .height(44)
              .width("100%")
              .onSelect((index: number) => {
                // 切换供应商 → 模型列表随之切换，重置为该供应商默认模型
                this.selectedIndex = index;
                this.providerId = MODEL_PRESETS[index].id;
                this.selectedModel = getModelPreset(this.providerId).defaultModel;
                this.modelIndex = 0;
              })
            // 当前选中供应商的接口信息（只读展示，不可手动修改）
            Text(`接口：${getModelPreset(this.providerId).endpoint}`)
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_secondary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ top: $r('app.float.space_sm'), bottom: $r('app.float.space_md') })

            // 模型名称选择（由所选供应商的 ModelPresets.models 提供，当前仅 deepseek-v4-flash）
            Text("模型名称")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.text_primary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ top: $r('app.float.space_md'), bottom: $r('app.float.space_xs') })
            Select(this.buildModelOptions())
              .selected(this.modelIndex)
              .value(this.getSelectedModelName())
              .font({ size: $r('app.float.font_input') })
              .fontColor($r('app.color.text_primary'))
              .selectedOptionFont({ size: $r('app.float.font_input') })
              .selectedOptionFontColor($r('app.color.text_primary'))
              .optionFont({ size: $r('app.float.font_input') })
              .optionFontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.page_bg'))
              .borderRadius(10)
              .borderWidth(1)
              .borderColor($r('app.color.input_border'))
              .height(44)
              .width("100%")
              .onSelect((index: number) => {
                this.modelIndex = index;
                this.selectedModel = getModelPreset(this.providerId).models[index];
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

  // 供应商下拉选项：来自 ModelPresets 预设（未来多供应商自动出现在这里）
  private buildSelectOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    MODEL_PRESETS.forEach((preset) => {
      options.push({ value: preset.providerName });
    });
    return options;
  }

  // 模型下拉选项：来自当前供应商预设的 models 列表（未来多模型自动出现在这里）
  private buildModelOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    const models = getModelPreset(this.providerId).models;
    models.forEach((m: string) => {
      options.push({ value: m });
    });
    return options;
  }

  // 供应商下拉当前显示的文本（绑定 .value，解决 Select 不显示当前值的问题）
  private getProviderName(): string {
    return getModelPreset(this.providerId).providerName;
  }

  // 模型下拉当前显示的文本（绑定 .value；无选择记录时显示默认模型）
  private getSelectedModelName(): string {
    return this.selectedModel.length > 0
      ? this.selectedModel
      : getModelPreset(this.providerId).defaultModel;
  }

  // 保存按钮逻辑：校验必填项 → 持久化 → 提示并返回

  private async handleSave(): Promise<void> {
    const config = AppConfig.getInstance();

    // 必填校验：API Key 不能为空
    if (this.apiKey.trim().length === 0) {
      showToast($r('app.string.config_incomplete'));
      return;
    }

    // 归一化所选模型：不属于当前供应商时回退默认模型（防御性校验）
    const models = getModelPreset(this.providerId).models;
    const model = models.indexOf(this.selectedModel) >= 0 ? this.selectedModel : models[0];

    // 保存（Key 加密入 Asset Store，供应商与模型选择入 Preferences）
    await config.updateConfig(this.providerId, this.apiKey.trim(), model);

    showToast($r('app.string.save_success'));
    // 延时返回，让 Toast 可见（记录定时器便于离开页面时清理）
    this.saveTimerId = setTimeout(() => {
      this.saveTimerId = -1;
      this.pathStack.pop();
    }, 500);
  }
}
