/**
 * 通用文本输入确认对话框
 * 用于：重命名对话、新建/重命名文件夹
 * 由 SideBarPage、FolderPage 复用，替代各自重复的 RenameDialog / NewFolderDialog
 */

import { COLORS, FONT_SIZES, SPACING, MESSAGES } from "../common/AppConstants";
import { showToast } from "../common/Utils";

@CustomDialog
export struct RenameInputDialog {
  controller?: CustomDialogController;
  title: string = "重命名"; // 对话框标题（可传入覆盖）
  placeholder: string = "请输入内容"; // 输入框占位
  oldValue: string = ""; // 预填值（重命名时使用）
  onConfirm: (value: string) => void = (value: string) => {}; // 确认回调
  @State inputValue: string = ""; // 输入框内容

  aboutToAppear(): void {
    this.inputValue = this.oldValue; // 预填旧值，方便直接修改
  }

  build() {
    Column({ space: SPACING.MD }) {
      Text(this.title)
        .fontSize(FONT_SIZES.BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width("100%")
        .textAlign(TextAlign.Start)
      TextInput({ placeholder: this.placeholder, text: this.inputValue })
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
              this.onConfirm(this.inputValue.trim());
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