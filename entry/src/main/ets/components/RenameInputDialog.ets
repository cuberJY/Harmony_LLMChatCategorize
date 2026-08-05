/**
 * 通用文本输入确认对话框（状态管理 V2）
 * 用于：重命名对话、新建/重命名文件夹
 * 由 SideBarPage、FolderPage 复用，替代各自重复的 RenameDialog / NewFolderDialog
 *
 * 打开方式：父页面通过 getPromptAction().openCustomDialog 打开；
 * 关闭方式：组件通过 onRequestClose 回调通知父页面 closeCustomDialog(dialogId)
 */

import { showToast } from "../common/Utils";

@ComponentV2
export struct RenameInputDialog {
  @Param title: string = "重命名"; // 对话框标题（可传入覆盖）
  @Param placeholder: string = "请输入内容"; // 输入框占位
  @Param oldValue: string = ""; // 预填值（重命名时使用）
  @Event onConfirm: (value: string) => void = (value: string) => {}; // 确认回调
  @Event onRequestClose: () => void = () => {}; // 关闭回调（父页面负责关闭弹窗）
  @Local inputValue: string = ""; // 输入框内容

  aboutToAppear(): void {
    this.inputValue = this.oldValue; // 预填旧值，方便直接修改
  }

  build() {
    Column({ space: $r('app.float.space_md') }) {
      Text(this.title)
        .fontSize($r('app.float.font_body'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width("100%")
        .textAlign(TextAlign.Start)
      TextInput({ placeholder: this.placeholder, text: this.inputValue })
        .defaultFocus(true)
        .fontSize($r('app.float.font_input'))
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.page_bg'))
        .borderRadius(8)
        .borderWidth(1)
        .borderColor($r('app.color.input_border'))
        .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md'), top: $r('app.float.space_xs'), bottom: $r('app.float.space_xs') })
        .width("100%")
        .onChange((value: string) => {
          this.inputValue = value;
        })
      Row() {
        Text("取消")
          .fontSize($r('app.float.font_button'))
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: $r('app.float.space_md'), bottom: $r('app.float.space_xs') })
          .onClick(() => {
            this.onRequestClose();
          })
        Text("确定")
          .fontSize($r('app.float.font_button'))
          .fontColor($r('app.color.primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: $r('app.float.space_md'), bottom: $r('app.float.space_xs') })
          .onClick(() => {
            if (this.inputValue.trim().length > 0) {
              this.onConfirm(this.inputValue.trim());
            } else {
              showToast($r('app.string.name_empty'));
            }
            this.onRequestClose();
          })
      }.width("100%")
    }
    .padding($r('app.float.space_lg'))
    .width("85%")
    .borderRadius(16)
    .backgroundColor($r('app.color.dialog_bg'));
  }
}
