/**
 * 编辑文件夹对话框
 * 可重命名文件夹 + 切换图标颜色
 * 颜色选择：一排色块，点击高亮边框，确认后回调
 * 用于：SideBarPage 收藏 Tab、FolderPage 子文件夹
 */

import { COLORS, FONT_SIZES, SPACING, FOLDER_COLORS, MESSAGES } from "../common/AppConstants";
import { showToast } from "../common/Utils";

@CustomDialog
export struct EditFolderDialog {
  controller?: CustomDialogController;
  title: string = "编辑文件夹";
  oldName: string = ""; // 原文件夹名（预填）
  oldColor: string = "#FF9F0A"; // 原图标颜色（高亮选中）
  onConfirm: (name: string, color: string) => void = (name: string, color: string) => {};
  @State inputValue: string = ""; // 名称输入内容
  @State selectedColor: string = "#FF9F0A"; // 当前选中的颜色

  aboutToAppear(): void {
    this.inputValue = this.oldName;
    this.selectedColor = this.oldColor;
  }

  @Builder
  private colorChip(color: string) {
    // 单个颜色块：选中时带边框高亮
    Column() {
      // 色块本体
      Row()
        .width(28)
        .height(28)
        .borderRadius(14)
        .backgroundColor(color)
    }
    .width(36)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .border({
      // 选中 → 主色边框；未选中 → 透明
      width: this.selectedColor === color ? 2 : 0,
      color: COLORS.PRIMARY,
      radius: 18,
    })
    .onClick(() => {
      this.selectedColor = color;
    });
  }

  build() {
    Column({ space: SPACING.MD }) {
      // 标题
      Text(this.title)
        .fontSize(FONT_SIZES.BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width("100%")
        .textAlign(TextAlign.Start)

      // 名称输入
      TextInput({ placeholder: "请输入文件夹名称", text: this.inputValue })
        .defaultFocus(true)
        .fontSize(FONT_SIZES.INPUT)
        .fontColor(COLORS.TEXT_PRIMARY)
        .backgroundColor(COLORS.PAGE_BG)
        .borderRadius(8)
        .borderWidth(1)
        .borderColor(COLORS.INPUT_BORDER)
        .padding({ left: SPACING.MD, right: SPACING.MD, top: SPACING.XS, bottom: SPACING.XS })
        .width("100%")
        .onChange((value: string) => {
          this.inputValue = value;
        })

      // 颜色选择区
      Text("图标颜色")
        .fontSize(FONT_SIZES.BODY)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width("100%")
        .textAlign(TextAlign.Start)

      // 8 个色块横向排列（超出可横向滚动）
      Scroll() {
        Row({ space: SPACING.XS }) {
          ForEach(FOLDER_COLORS, (color: string) => {
            this.colorChip(color)
          }, (color: string) => color)
        }
        .padding({ top: SPACING.XS, bottom: SPACING.XS })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width("100%")

      // 按钮区
      Row() {
        Text("取消")
          .fontSize(FONT_SIZES.BUTTON)
          .fontColor(COLORS.TEXT_SECONDARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: SPACING.MD, bottom: SPACING.XS })
          .onClick(() => {
            this.controller?.close();
          })
        Text("确定")
          .fontSize(FONT_SIZES.BUTTON)
          .fontColor(COLORS.PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: SPACING.MD, bottom: SPACING.XS })
          .onClick(() => {
            if (this.inputValue.trim().length > 0) {
              this.onConfirm(this.inputValue.trim(), this.selectedColor);
            } else {
              showToast(MESSAGES.NAME_EMPTY);
            }
            this.controller?.close();
          })
      }.width("100%")
    }
    .padding(SPACING.LG)
    .width("85%")
    .borderRadius(16)
    .backgroundColor(Color.White);
  }
}
