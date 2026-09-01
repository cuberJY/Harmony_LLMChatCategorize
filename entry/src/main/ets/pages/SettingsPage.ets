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

import { common } from "@kit.AbilityKit";
import { KeyboardAvoidMode } from "@kit.ArkUI";
import { AppConfig } from "../config/AppConfig";
import { MODEL_PRESETS, getModelPreset } from "../config/ModelPresets";
import { showToast, SafeAreaHelper } from "../common/Utils";

@ComponentV2
export struct SettingsPage {
  /* 路由栈（NavDestination.onReady 获取）：返回上一页 */
  private pathStack: NavPathStack = new NavPathStack();
  /* 表单状态（初始值取自 AppConfig，保证编辑时能看到已保存的值） */
  @Local providerId: string = "";
  @Local selectedIndex: number = 0; // 供应商下拉当前选中项索引
  @Local selectedModel: string = ""; // 模型下拉当前选中的模型名
  @Local modelIndex: number = 0; // 模型下拉当前选中项索引
  @Local apiKey: string = "";
  /* 沉浸式系统栏高度（vp，EntryAbility 注入）：aboutToAppear 一次性读取（V2 无 @StorageProp，用 @Local + 手动读取） */
  @Local statusBarHeightVp: number = 0;
  @Local navBarHeightVp: number = 0;
  private globalKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.RESIZE; // 记录全局避让模式
  private saveTimerId: number = -1; // 保存后返回的定时器，离开页面时清理
  private isSaving: boolean = false; // 保存中标记（防连点重复保存与双 pop）

  aboutToAppear(): void {
    /* 读取系统栏高度（标题栏/内容区避让用） */
    this.statusBarHeightVp = SafeAreaHelper.getStatusBarHeight();
    this.navBarHeightVp = SafeAreaHelper.getNavBarHeight();
    /* 键盘避让：记住全局模式后固定 RESIZE（表单输入需要键盘避让）。
       背景：从 SideBarPage/FolderPage push 进入时，这两页已把全局模式切成 NONE，
       本页若不显式改回 RESIZE，键盘弹出时视口不压缩、API Key 输入框会被键盘盖住。
       注意只能用 RESIZE（OFFSET 在窗口未弹过键盘时会造成避让状态卡死的历史问题） */
    this.globalKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
 
    /* 回显已保存的配置 */
    const config = AppConfig.getInstance().getConfig();
    this.providerId = config.providerId;
    /* 根据已保存的供应商定位下拉选中项（找不到时回退第一项） */
    const idx = MODEL_PRESETS.findIndex((p) => p.id === this.providerId);
    this.selectedIndex = idx >= 0 ? idx : 0;
    /* 模型：回显已保存的模型名；无记录或不属于当前供应商时回退默认模型 */
    this.selectedModel =
      config.model.length > 0 ? config.model : getModelPreset(this.providerId).defaultModel;
    const midx = getModelPreset(this.providerId).models.indexOf(this.selectedModel);
    this.modelIndex = midx >= 0 ? midx : 0;
    this.apiKey = config.apiKey;
    /* 修复：AppConfig.init 失败后无重试路径，此处幂等重试（成功即返回） */
    const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppConfig.getInstance().init(hostContext);
  }

  aboutToDisappear(): void {
    /* 离开页面恢复全局模式（上层 SideBarPage/FolderPage 期望 NONE，保持其行为不变） */
    this.getUIContext().setKeyboardAvoidMode(this.globalKeyboardAvoidMode);
    /* 离开页面时清理返回定时器，避免越层返回 */
    if (this.saveTimerId !== -1) {
      clearTimeout(this.saveTimerId);
      this.saveTimerId = -1;
    }
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Row() {
            SymbolGlyph($r("sys.symbol.chevron_left"))
              .fontSize($r('app.float.font_icon_xl'))
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
        /* 沉浸式：SYSTEM 背景延伸 + 显式 padding 内容避让；KEYBOARD 保留键盘避让（标题栏不被键盘顶出） */
        .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.KEYBOARD])

        Scroll() {
          Column() {
            Text("供应商")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.font_primary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ bottom: $r('app.float.space_xs') })
            Select(this.buildSelectOptions())
              .selected(this.selectedIndex)
              .value(this.getProviderName())
              .font({ size: $r('app.float.font_input') })
              .fontColor($r('app.color.font_primary'))
              .selectedOptionFont({ size: $r('app.float.font_input') })
              .selectedOptionFontColor($r('app.color.font_primary'))
              .optionFont({ size: $r('app.float.font_input') })
              .optionFontColor($r('app.color.font_primary'))
              .backgroundColor($r('app.color.page_bg'))
              .borderRadius($r('app.float.setting_select_radius'))
              .borderWidth(1)
              .borderColor($r('app.color.input_border'))
              .height($r('app.float.input_height'))
              .width("100%")
              .onSelect((index: number) => {
                /* 切换供应商 → 模型列表随之切换，重置为该供应商默认模型 */
                this.selectedIndex = index;
                this.providerId = MODEL_PRESETS[index].id;
                this.selectedModel = getModelPreset(this.providerId).defaultModel;
                this.modelIndex = 0;
              })
            /* 当前选中供应商的接口信息（只读展示，不可手动修改） */
            Text(`接口：${getModelPreset(this.providerId).endpoint}`)
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.font_secondary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ top: $r('app.float.space_sm') })

            /* 模型列表由所选供应商的 ModelPresets.models 提供 */
            Text("模型名称")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.font_primary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ top: $r('app.float.space_md'), bottom: $r('app.float.space_xs') })
            Select(this.buildModelOptions())
              .selected(this.modelIndex)
              .value(this.getSelectedModelName())
              .font({ size: $r('app.float.font_input') })
              .fontColor($r('app.color.font_primary'))
              .selectedOptionFont({ size: $r('app.float.font_input') })
              .selectedOptionFontColor($r('app.color.font_primary'))
              .optionFont({ size: $r('app.float.font_input') })
              .optionFontColor($r('app.color.font_primary'))
              .backgroundColor($r('app.color.page_bg'))
              .borderRadius($r('app.float.setting_select_radius'))
              .borderWidth(1)
              .borderColor($r('app.color.input_border'))
              .height($r('app.float.input_height'))
              .width("100%")
              .onSelect((index: number) => {
                this.modelIndex = index;
                this.selectedModel = getModelPreset(this.providerId).models[index];
              })

            Text("API Key")
              .fontSize($r('app.float.font_body'))
              .fontColor($r('app.color.font_primary'))
              .width("100%")
              .textAlign(TextAlign.Start)
              .margin({ top: $r('app.float.space_md'), bottom: $r('app.float.space_xs') })
            TextInput({ placeholder: "sk-xxxxxxxxxxxxxxxxxxxxxxxx", text: this.apiKey })
              .fontSize($r('app.float.font_input'))
              .fontColor($r('app.color.font_primary'))
              .placeholderColor($r('app.color.font_secondary'))
              .backgroundColor($r('app.color.page_bg'))
              .borderRadius($r('app.float.setting_select_radius'))
              .borderWidth(1)
              .borderColor($r('app.color.input_border'))
              .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md') })
              .margin({ bottom: $r('app.float.space_md') })
              .type(InputType.Password)
              .onChange((value: string) => {
                this.apiKey = value;
              })

            Button("保存")
              .width("100%")
              .height($r('app.float.input_height'))
              .fontSize($r('app.float.font_button'))
              .fontColor(Color.White)
              .backgroundColor($r('app.color.brand'))
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
        /* 沉浸式：内容区底部避让导航条 */
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

  /* 供应商下拉选项：来自 ModelPresets 预设（未来多供应商自动出现在这里） */
  private buildSelectOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    MODEL_PRESETS.forEach((preset) => {
      options.push({ value: preset.providerName });
    });
    return options;
  }

  /* 模型下拉选项：来自当前供应商预设的 models 列表（未来多模型自动出现在这里） */
  private buildModelOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    const models = getModelPreset(this.providerId).models;
    models.forEach((m: string) => {
      options.push({ value: m });
    });
    return options;
  }

  /* 供应商下拉当前显示的文本（绑定 .value，解决 Select 不显示当前值的问题） */
  private getProviderName(): string {
    return getModelPreset(this.providerId).providerName;
  }

  /* 模型下拉当前显示的文本（绑定 .value；无选择记录时显示默认模型） */
  private getSelectedModelName(): string {
    return this.selectedModel.length > 0
      ? this.selectedModel
      : getModelPreset(this.providerId).defaultModel;
  }

  /* 保存按钮逻辑：校验必填项 → 持久化 → 提示并返回 */

  private async handleSave(): Promise<void> {
    /* 防重入：连点保存会导致两次 updateConfig 与两个返回定时器（双 pop 越层返回） */
    if (this.isSaving) {
      return;
    }
    this.isSaving = true;
    try {
      const config = AppConfig.getInstance();

      /* 必填校验：API Key 不能为空 */
      if (this.apiKey.trim().length === 0) {
        showToast(this.getUIContext(), $r('app.string.config_incomplete'));
        return;
      }

      /* 归一化所选模型：不属于当前供应商时回退默认模型（防御性校验） */
      const models = getModelPreset(this.providerId).models;
      const model = models.indexOf(this.selectedModel) >= 0 ? this.selectedModel : models[0];

      /* 保存（Key 加密入 Asset Store，供应商与模型选择入 Preferences） */
      const ok: boolean = await config.updateConfig(this.providerId, this.apiKey.trim(), model);
      if (!ok) {
        /* 落盘失败：提示并停留本页，避免"提示成功但重启后配置丢失" */
        showToast(this.getUIContext(), $r('app.string.save_failed'));
        return;
      }

      showToast(this.getUIContext(), $r('app.string.save_success'));
      /* 延时返回，让 Toast 可见（先清旧定时器，杜绝双 pop） */
      if (this.saveTimerId !== -1) {
        clearTimeout(this.saveTimerId);
      }
      this.saveTimerId = setTimeout(() => {
        this.saveTimerId = -1;
        this.pathStack.pop();
      }, 500);
    } finally {
      this.isSaving = false;
    }
  }
}
