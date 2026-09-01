/**
 * 底部聊天输入区域组件（状态管理 V2）
 * 布局结构（从上到下）：
 *   1. 模型名称（小字、次要色）
 *   2. 图片预览条（已选图片横向缩略图 + 右上角删除；发送后清空）
 *   3. TextArea 输入框（最多 4 行，透明背景融入卡片）
 *   4. 底部操作栏：左侧切换按钮组 + 右侧选图按钮（视觉模型可用）与发送按钮
 *
 * 切换按钮（思考强度 / 联网搜索）：
 *   - 状态由父级 ViewModel 持有（@Param 单向传入），点击后经 onThinkingChange / onWebSearchChange 上报，
 *     由 VM 更新唯一真源并回流刷新 → 发送 / 重新生成 / 新建分支使用同一份当前设置
 *   - 思考强度为多档位选择（关闭/轻量/深度/极限），点击按钮弹出下拉菜单（bindMenu，样式同设置页模型选择）；
 *     联网搜索为开/关切换
 *   - 发送时通过 onChange 上报文本与已选图片（开关值由 VM 直接读取，不再重复传递）
 *
 * 图片发送：
 *   - 选图按钮在发送按钮左侧；仅视觉模型且非编辑态显示
 *   - 点击弹出「从相册选择 / 拍照」菜单（PhotoViewPicker / CameraPicker，均免权限）
 *
 * V2 说明：@Local 为组件内部状态（输入文本/最大高度/已选图片），
 * @Param 为父组件传入的参数（模型名称/开关状态/编辑态），回调用 @Event 承载
 */

import { LengthMetrics } from "@kit.ArkUI";
import { inputMethod } from "@kit.IMEKit";
import { common } from "@kit.AbilityKit";
import { ThinkingEffort, ThinkingLevel, THINKING_LEVELS, thinkingLevelLabel, DEFAULT_THINKING_EFFORT } from "../../config/ModelPresets";
import { ImageAttachment, FileAttachment } from "../../model/Message";
import { ImageUtil } from "../../service/ImageUtil";
import { FileParser } from "../../service/FileParser";
import { showToast } from "../../common/Utils";
import { FileCard } from "./FileCard";
import { ImageCard } from "./ImageCard";

/** 单条消息图片附件上限 */
const MAX_IMAGES: number = 9;

@ComponentV2
export struct ChatInput {
  @Local inputText: string = "";
  /* 发送前已选图片附件（预览展示；发送成功后清空） */
  @Local images: ImageAttachment[] = [];
  /* 发送前已选文件附件（预览展示；发送成功后清空。单文件：再次选择即替换） */
  @Local files: FileAttachment[] = [];
  /* 输入框行高与行间距（用于精确计算最大高度） */
  private inputLineHeight: number = 22; // 行高，需 >= 输入字号（15fp）
  private inputLineSpacing: number = 0; // 行间距
  @Local inputMaxHeight: number = 0;

  aboutToAppear(): void {
    /* 官方公式：高度 = 行高 × 行数 + 行间距 × (行数 - 1) */
    this.inputMaxHeight = this.inputLineHeight * 5 + this.inputLineSpacing * 4;
    /* 修复：@Monitor 不触发初始值——挂载时若已带编辑预填需主动回填 */
    if (this.prefillText.length > 0) {
      this.inputText = this.prefillText;
    }
  }

  /* 发送/暂停按钮是否可用：生成中恒可用（暂停键）；否则输入框有内容才可点（发送键） */
  private isSendButtonEnabled(): boolean {
    return this.streamState === "streaming" || this.inputText.trim().length > 0 || this.images.length > 0 || this.files.length > 0;
  }

  /* 模型名称（由父组件传入） */
  @Param modelName: string = "";
  /* 编辑态预填文本（点击用户消息「编辑」后回填到输入框；非空即触发回填） */
  @Param prefillText: string = "";
  /* 编辑态预填图片（点击用户消息「编辑」后回填到预览条，编辑时可增删改；与 prefillText 联动回填） */
  @Param prefillImages: ImageAttachment[] = [];
  /* 编辑态预填文件（点击用户消息「编辑」后回填到预览条；与 prefillText/prefillImages 联动回填） */
  @Param prefillFiles: FileAttachment[] = [];
  /* 是否处于编辑态（编辑消息中，显示提示文案） */
  @Param isEditing: boolean = false;
  /* 思考强度（由 ViewModel 传入，唯一真源；none 关闭 / low 轻量 / high 深度 / max 极限） */
  @Param thinkingEffort: ThinkingEffort = DEFAULT_THINKING_EFFORT;
  /* 联网搜索开关（由 ViewModel 传入，唯一真源） */
  @Param webSearch: boolean = true;
  /**
   * 流式生成状态（由 ViewModel 传入，唯一真源）：
   * idle=发送键 / streaming=暂停键 / paused=显示「继续生成」按钮
   */
  @Param streamState: "idle" | "streaming" | "paused" = "idle";
  /* 底部导航条高度（vp，父级传入）：输入区内容用其手动避让，避免被导航条遮挡 */
  @Param navBarHeightVp: number = 0;
  /**
   * 键盘是否弹出（父级 keyboardHeightChange 驱动）：弹出时导航条已被键盘遮挡，
   * 底部 margin 无需再避让导航条，仅保留 16 间距 → 收紧 (keyboardUp ? 0 : navBarHeightVp) + 16
   */
  @Param keyboardUp: boolean = false;
  /* 当前模型是否支持图片输入（由 ViewModel 传入）：false 时隐藏选图按钮，不能发图 */
  @Param supportsVision: boolean = false;

  /* 监听 prefillText / prefillImages / prefillFiles 变化：回填内容到输入框（@Monitor 是 V2 监听 @Param 变化的机制）。
     三个都监听：纯图片/纯文件消息 content 为空（prefillText 不变）时，靠 prefillImages / prefillFiles 变化仍能触发回填 */
  @Monitor('prefillText', 'prefillImages', 'prefillFiles')
  onPrefillChanged(): void {
    if (this.prefillText.length > 0 || this.prefillImages.length > 0 || this.prefillFiles.length > 0) {
      this.inputText = this.prefillText;
      this.images = this.prefillImages; // 编辑态回填原图（编辑时可增删改）
      this.files = this.prefillFiles; // 编辑态回填原文件（编辑时可增删改）
      /* 编辑回填后自动弹出输入法：先清焦点再请求焦点（确保已聚焦时也能重新弹起键盘） */
      const focus = this.getUIContext().getFocusController();
      focus.clearFocus();
      setTimeout(() => {
        focus.requestFocus('chat_input');
      }, 0);
    } else {
      /* 编辑态取消/新建对话（prefill 被清空）→ 同步清空输入框与图片文件 */
      this.inputText = "";
      this.images = [];
      this.files = [];
    }
  }

  /* 联网搜索开关切换回调（@Event：点击切换按钮时上报新状态，由父级更新 VM 唯一真源） */
  @Event onWebSearchChange: (webSearch: boolean) => void = (webSearch: boolean) => {};
  /* 思考强度档位选择回调（@Event：底部面板点选时上报新档位，由父级更新 VM 唯一真源） */
  @Event onThinkingChange: (effort: ThinkingEffort) => void = (effort: ThinkingEffort) => {};
  /* 发送回调（@Event：上报文本、本次选图与本次文件；开关状态由父级 VM 读取） */
  @Event onChange: (text: string, images: ImageAttachment[], files: FileAttachment[]) => void = (text: string, images: ImageAttachment[], files: FileAttachment[]) => {};
  /* 暂停生成回调（生成中点击暂停键时触发，由 VM 中止流式请求） */
  @Event onPause: () => void = () => {};
  /* 取消编辑回调（编辑态点击顶部右侧 xmark 时触发，由 VM 退出编辑态并清空输入框） */
  @Event onCancelEdit: () => void = () => {};
  /* 输入框焦点变化回调（@Event：聚焦=键盘将弹出，失焦=可能收起；父级据此驱动全局键盘标志） */
  @Event onInputFocusChange: (hasFocus: boolean) => void = (hasFocus: boolean) => {};
  /**
   * 容器实际高度变化回调（@Event：TextArea 多行增高/键盘态变化时上报）：
   * 父级据此动态调整 List.contentEndOffset（"到底"判定位置）与 FAB 避让高度
   */
  @Event onHeightChange: (height: number) => void = (height: number) => {};
  /* 上次上报的容器高度（vp，onAreaChange 防抖用，-1 表示尚未上报） */
  private lastHeight: number = -1;

  /**
   * 从指定来源选图并追加到已选列表
   * 相册：PhotoViewPicker（无需读图权限）；拍照：系统 CameraPicker（无需 CAMERA 权限）
   * 图片经 ImageUtil 压缩编码（PNG/JPEG/WebP→JPEG，GIF 原样保留），附带 MIME 魔数检测
   * @param source 图片来源：gallery=相册 / camera=相机
   */
  private async pickImages(source: "gallery" | "camera"): Promise<void> {
    const remaining: number = MAX_IMAGES - this.images.length;
    if (remaining <= 0) {
      showToast(this.getUIContext(), $r("app.string.image_limit_reached"));
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (source === "gallery") {
      const picked = await ImageUtil.getInstance().pickFromGallery(context, remaining);
      this.images = this.images.concat(picked);
    } else {
      const photo = await ImageUtil.getInstance().capturePhoto(context);
      if (photo !== null) {
        this.images = this.images.concat(photo);
      }
    }
  }

  /* 删除某张已选图片（预览条右上角 x） */
  private removeImage(id: string): void {
    this.images = this.images.filter((img: ImageAttachment) => img.id !== id);
  }

  /**
   * 选择单个文件并解析为附件（系统文档选择器 DocumentViewPicker，免权限）
   * 单文件：再次选择直接替换已有文件；pdf 需视觉模型（选择即校验，避免白选）
   */
  private async pickFiles(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      /* 阶段1 延迟解析：选择时仅持久化源文件（pickAndSave），不解析内容。
         pdf 视觉模型校验与内容解析统一在发送阶段（ViewModel.parseForSend）完成，
         txt/md 走文本通道所有模型可用 */
      const file = await FileParser.getInstance().pickAndSave(context);
      if (file !== null) {
        this.files = [file]; // 单文件：新选替换旧文件
      }
    } catch (e) {
      showToast(this.getUIContext(), $r('app.string.file_parse_failed', (e as Error).message));
    }
  }

  /* 删除已选文件（预览条右上角 x） */
  private removeFile(id: string): void {
    this.files = this.files.filter((f: FileAttachment) => f.id !== id);
  }

  build() {
    Column() {
      /* 中间包裹层：图片预览条 + 输入区悬浮胶囊。
         onAreaChange 挂在本层上报总高（预览条 + 胶囊），父级据此计算 List "到底"判定位置，
         避免图片预览条展开时遮挡最后一条消息 */
      Column() {
        /* 附件预览条（已选图片/文件横向展示 + 右上角删除；发送成功后清空隐藏） */
        if (this.images.length > 0 || this.files.length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(
                this.images,
                (img: ImageAttachment) => {
                  /* 图片卡片：64×64 缩略图 + 右上角删除（样式见 ImageCard，与气泡共用） */
                  ImageCard({
                    img: img,
                    cardSize: 64,
                    cornerRadius: 12,
                    showRemove: true,
                    onRemove: () => {
                      this.removeImage(img.id);
                    },
                  })
                },
                (img: ImageAttachment) => img.id,
              )
              /* 文件卡片：与图片同位置混排，右侧同样带删除按钮（样式见 FileCard） */
              ForEach(
                this.files,
                (file: FileAttachment) => {
                  FileCard({
                    file: file,
                    showRemove: true,
                    onRemove: () => {
                      this.removeFile(file.id);
                    },
                  })
                },
                (file: FileAttachment) => file.id,
              )
            }
            .alignItems(VerticalAlign.Top)
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .align(Alignment.TopStart)
          .width("100%")
          .height(64)
          .alignSelf(ItemAlign.Start)
          .margin({
            left: $r('app.float.space_md'),
            right: $r('app.float.space_md'),
            bottom: $r('app.float.space_xs'),
          })
        }
        Column() {
        /* 1. 顶部信息行：左侧模型名称/编辑提示，右侧「取消编辑」按钮（仅编辑态显示） */
        Row() {
          Text(
            this.isEditing
              ? "正在编辑消息（发送后在该位置创建新分支）"
              : (this.modelName.length > 0 ? this.modelName : "未配置模型，请前往设置"),
          )
            .fontSize($r('app.float.font_model_name'))
            .fontColor($r('app.color.font_secondary'))
            .layoutWeight(1) // 占据剩余空间，把取消按钮推到最右
            .margin({ left: $r('app.float.space_xs') })

          /* 编辑态：右侧 xmark 取消编辑（清空输入框并退出编辑态） */
          if (this.isEditing) {
            Button() {
              SymbolGlyph($r("sys.symbol.xmark"))
                .fontSize($r('app.float.font_icon_lg'))
                .fontWeight(700)
                .fontColor([$r('app.color.font_primary')])
            }
            .width(26)
            .height(26)
            .type(ButtonType.Circle)
            .backgroundColor($r('app.color.toggle_bg_inactive'))
            .padding({
              left: $r('app.float.space_xs'),
              right: $r('app.float.space_xs'),
              top: $r('app.float.space_xs'),
              bottom: $r('app.float.space_xs'),
            })
            .margin({ right: $r('app.float.space_xs') })
            .onClick(() => {
              /* 取消编辑：先收起输入法键盘，再上报退出编辑态（VM 清空 prefillText → @Monitor 联动清空输入框） */
              inputMethod.getController().stopInput();
              this.onCancelEdit();
            })
          }
        }
        .width("100%")

        /* 2. 输入框 */
        TextArea({
          text: this.inputText,
          placeholder: "输入消息...",
        })
          .id('chat_input') // 供自动弹出输入法时请求焦点
          /**
           * TextArea 默认 stopBackPress(true)，会拦截返回键、不触发 NavDestination.onBackPressed，
           * 导致键盘收起后第二次返回键被 TextArea 消费并冒泡到 UIAbility 直接退出应用。
           * 置 false 让返回键正常传到 onBackPressed，由页面按「收键盘 > 取消编辑 > 退出」优先级处理。
           */
          .stopBackPress(false)
          .fontSize($r('app.float.font_input'))
          .fontColor($r('app.color.font_primary'))
          .width("100%")
          .lineHeight(this.inputLineHeight) // 显式行高
          .lineSpacing(LengthMetrics.px(this.inputLineSpacing)) // 行间距
          .constraintSize({ maxHeight: this.inputMaxHeight }) // 最大高度约束，触发滚动
          .placeholderColor($r('app.color.font_secondary'))
          .backgroundColor($r('app.color.chat_input_bg'))
          .borderWidth(0) // 去掉边框
          .padding({
            left: $r('app.float.space_xs'),
            right: $r('app.float.space_xs'),
            top: $r('app.float.space_xs'),
            bottom: $r('app.float.space_md'),
          })
          .margin({
            top: $r('app.float.space_xs'),
            bottom: $r('app.float.space_sm'),
          })
          /* 高度由 constraintSize(maxHeight) 约束，超出时滚动 */
          .onChange((value: string) => {
            this.inputText = value;
          })
          /**
           * 聚焦 → 键盘必然弹出（TextArea 默认 enableKeyboardOnFocus(true)）；失焦 → 可能收起。
           * 上报父级驱动全局键盘标志：该信号是同步可靠的，弥补 keyboardHeightChange
           * 「冷启动首次弹键盘事件丢失 / 键盘避让 NONE 模式下不派发」的被动事件缺陷
           */
          .onFocus(() => {
            this.onInputFocusChange(true);
          })
          .onBlur(() => {
            this.onInputFocusChange(false);
          })
          /**
           * 键盘判断事件（API 24+，HarmonyOS 6.1.1）：组件获焦时系统询问「是否需要软键盘」，
           * 回调无参数、返回 boolean：true=需要（保持键盘）/ false=不需要（收起）。
           * 本输入框始终需要软键盘（普通输入与编辑态都需弹键盘），故恒返回 true，
           * 确保编辑回填/焦点转移等场景下键盘不被误收起。
           * 注意：该回调是「获焦时是否保持键盘」的感知性接口，与 @Monitor 里 clearFocus+requestFocus
           * 「主动弹键盘」兜底互补，此处不改动兜底逻辑。
           */
          .onNeedSoftkeyboard(() => {
            return true;
          })

        /* 3. 底部操作栏 */
        Row() {
          /* 左侧：切换按钮组 */
          Row() {
            /* 思考强度：按钮文字显示当前档位；点击弹出下拉菜单选择（非 none 时高亮，表示思考已开启） */
            Row() {
              SymbolGlyph($r("sys.symbol.AI_deep_thinking"))
                .fontSize($r('app.float.font_icon_lg'))
                .fontWeight(600)
                .fontColor(
                  this.thinkingEffort !== "none"
                    ? [$r('app.color.toggle_text_active')]
                    : [$r('app.color.toggle_text_inactive')]
                )
                .margin({
                  left: $r('app.float.space_xxs'),
                  right: $r('app.float.space_xs')
                })
              Text(thinkingLevelLabel(this.thinkingEffort))
                .width(35)
                .fontSize($r('app.float.font_toggle'))
                .fontColor(
                  this.thinkingEffort !== "none"
                    ? $r('app.color.toggle_text_active')
                    : $r('app.color.toggle_text_inactive')
                )
              SymbolGlyph($r("sys.symbol.chevron_down"))
                .fontSize($r('app.float.font_icon_md'))
                .fontWeight(600)
                .fontColor(
                  this.thinkingEffort !== "none"
                    ? [$r('app.color.toggle_text_active')]
                    : [$r('app.color.toggle_text_inactive')]
                )
            }
            .padding({
              left: $r('app.float.space_sm'),
              right: $r('app.float.space_sm'),
              top: $r('app.float.space_xs'),
              bottom: $r('app.float.space_xs'),
            })
            .height(32)
            .borderRadius(16)
            .backgroundColor(
              this.thinkingEffort !== "none"
                ? $r('app.color.toggle_bg_active')
                : $r('app.color.toggle_bg_inactive')
            )
            .margin({ right: $r('app.float.space_sm') })
            /* 下拉菜单选择（bindMenu） */
            .bindMenu(this.thinkingMenuBuilder())

            /* 联网搜索 */
            Row() {
              SymbolGlyph($r("sys.symbol.pc_ic_tab_index"))
                .fontSize($r('app.float.font_icon_lg'))
                .fontWeight(600)
                .fontColor(
                  this.webSearch
                    ? [$r('app.color.toggle_text_active')]
                    : [$r('app.color.toggle_text_inactive')]
                )
                .margin({
                  right: $r('app.float.space_xxs')
                })
              Text("联网搜索")
                .fontSize($r('app.float.font_toggle'))
                .fontColor(
                  this.webSearch
                    ? $r('app.color.toggle_text_active')
                    : $r('app.color.toggle_text_inactive')
                )
            }
            .padding({
                  left: $r('app.float.space_sm'),
                  right: $r('app.float.space_sm'),
                  top: $r('app.float.space_xs'),
                  bottom: $r('app.float.space_xs'),
                })
            .height(32)
            .borderRadius(16)
            .backgroundColor(
              this.webSearch
                ? $r('app.color.toggle_bg_active')
                : $r('app.color.toggle_bg_inactive')
              )
            .onClick(() => {
              /* 上报新状态给父级（VM 更新唯一真源后回流刷新本组件） */
              this.onWebSearchChange(!this.webSearch);
            })
          }
          .layoutWeight(1) // 占据左侧空间，把发送按钮推到最右

          /* 右侧：添加附件按钮（所有模型显示；视觉模型菜单含 相册/拍照/文件，非视觉模型仅 文件）。
             普通态与编辑态均可点击，弹出附件来源菜单 */
          Button() {
            SymbolGlyph($r("sys.symbol.plus"))
              .fontSize($r('app.float.font_icon_lg'))
              .fontWeight(800)
              .fontColor([$r('app.color.operation_icon')])
          }
          .width(30)
          .height(30)
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.chat_input_bg')) // 背景与输入区一致
          .border({ width: 2, color: $r('app.color.operation_icon') })
          .margin({ right: $r('app.float.space_sm') })
          .bindMenu(this.imageMenuBuilder())

          /* 右侧：发送 / 暂停按钮（生成中显示暂停键，点击暂停；普通态显示发送键） */
          Button() {
            SymbolGlyph(
              this.streamState === "streaming"
                ? $r("sys.symbol.square_fill") // 生成中 → 暂停图标（实心方块）
                : $r("sys.symbol.arrowshape_up_fill"), // 普通态 → 发送图标
            )
            .fontSize(
              this.streamState === "streaming"
                ? $r('app.float.font_icon_md')
                : $r('app.float.font_icon_xl')
            )
            .fontColor([Color.White])
            .margin({ bottom: 1 })
          }
          .width(32)
          .height(32)
          .type(ButtonType.Circle)
          .backgroundColor(
            this.isSendButtonEnabled() ? $r('app.color.brand') : $r('app.color.send_btn_disabled'),
          )
          .enabled(this.isSendButtonEnabled()) // 生成中恒可点（暂停键）；否则有内容或有图或有文件才可点（发送键）
          .onClick(() => {
            if (this.streamState === "streaming") {
              /* 生成中：暂停（中止流式请求，保留已生成内容） */
              this.onPause();
            } else if ((this.inputText.trim().length > 0 || this.images.length > 0 || this.files.length > 0) && this.onChange) {
              /* 普通态：发送文本 + 已选图片 + 已选文件（开关状态由父级 VM 读取（唯一真源），这里仅上报） */
              inputMethod.getController().stopInput(); // 发送后自动收起输入法键盘
              const text = this.inputText.trim();
              const imgs = this.images;
              const files = this.files;
              this.inputText = ""; // 发送后清空输入框
              this.images = []; // 发送后清空已选图片
              this.files = []; // 发送后清空已选文件
              this.onChange(text, imgs, files);
            }
          })
        }
        .width("100%")
        .alignItems(VerticalAlign.Center)
        }
        /* 容器样式（圆角白底悬浮胶囊） */
        .width("96%")
        .padding({
          left: $r('app.float.space_md'),
          right: $r('app.float.space_md'),
          top: $r('app.float.space_md'),
          bottom: $r('app.float.space_md'),
        })
        .backgroundColor($r('app.color.chat_input_bg'))
        .borderRadius(32)
        .border({ width: 2, color: $r('app.color.divider') })
        .margin({
          left: "2%",
          right: "2%",
        })
      }
      /* 包裹层属性：铺满宽度 + 总高上报（预览条 + 胶囊），
         驱动 List.contentEndOffset 与 FAB 位置同步跟随（不含下方渐变遮罩区） */
      .width("100%")
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const h = Math.round(Number(newArea.height));
        if (h !== this.lastHeight) {
          this.lastHeight = h;
          this.onHeightChange(h);
        }
      })

      /* 底部渐变遮罩（导航条避让区）：shadow_up → shadow_down，
         气泡滑入导航条区域时被遮罩盖住/融入背景，不再显眼；
         键盘弹出时导航条已被键盘遮挡 → 仅保留 16 间距 */
      Column()
        .width("100%")
        .height(this.keyboardUp ? $r('app.float.space_sm') : (this.navBarHeightVp + 16))
        .linearGradient({
          angle: 180,
          colors: [[$r('app.color.shadow_up'), 0], [$r('app.color.shadow_down'), 1]]
        })
    }
    .width("100%")
  }

  /**
   * 附件来源选择菜单（添加按钮 bindMenu 内容）
   * 视觉模型：相册 / 拍照 / 文件；非视觉模型：仅 文件（txt/md 走文本通道，pdf 需视觉模型）
   */
  @Builder
  imageMenuBuilder() {
    Menu() {
      if (this.supportsVision) {
        MenuItem({ content: "相册" })
          .onChange(() => {
            this.pickImages("gallery");
          })
        MenuItem({ content: "拍照" })
          .onChange(() => {
            this.pickImages("camera");
          })
      }
      MenuItem({ content: "文件" })
        .onChange(() => {
          this.pickFiles();
        })
    }
  }

  /**
   * 思考强度下拉菜单（bindMenu 内容，样式同设置页 Select 模型选择）
   * 列出全部档位（关闭/轻量/深度/极限）
   * 选中某一项 → 上报父级 VM 更新唯一真源，菜单自动关闭。
   * 选中态由 @Param thinkingEffort（父级回流）驱动，菜单收起后按钮文字同步更新
   */
  @Builder
  thinkingMenuBuilder() {
    Menu() {
      ForEach(
        THINKING_LEVELS,
        (level: ThinkingLevel) => {
          MenuItem({ content: level.label })
            /* 选中档位背景高亮（与思考强度按钮高亮同色），未选中保持透明露出菜单底色 */
            .backgroundColor(
              this.thinkingEffort === level.value
                ? $r('app.color.toggle_bg_active')
                : Color.Transparent
            )
            .contentFontColor(
              this.thinkingEffort === level.value
                ? $r('app.color.toggle_text_active')
                : $r('app.color.font_primary')
            )
            .onChange(() => {
              /* 点选档位 → 上报父级（VM 更新唯一真源后回流刷新按钮文字与菜单选中态） */
              this.onThinkingChange(level.value);
            })
        },
        (level: ThinkingLevel) => level.value,
      )
    }
  }
}
