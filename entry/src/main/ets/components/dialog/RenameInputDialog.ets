/**
 * 通用文本输入确认对话框（状态管理 V2）
 * 用于：重命名对话、新建/重命名文件夹
 * 由 SideBarPage、FolderPage 复用，替代各自重复的 RenameDialog / NewFolderDialog
 *
 * 打开方式：父页面通过 getPromptAction().openCustomDialog 打开；
 * 关闭方式：组件通过 onRequestClose 回调通知父页面 closeCustomDialog(dialogId)
 */

import { showToast } from "../../common/Utils";

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
        .fontSize($r('app.float.font_title'))
        .fontWeight(800)
        .fontColor($r('app.color.font_primary'))
        .width("100%")
        .margin({ 
          top: $r('app.float.space_sm'),
          bottom: $r('app.float.space_xs'),
        })
        .textAlign(TextAlign.Center)
      TextInput({ placeholder: this.placeholder, text: this.inputValue })
        .defaultFocus(true)
        .fontSize($r('app.float.font_input'))
        .fontColor($r('app.color.font_primary'))
        .placeholderColor($r('app.color.font_secondary'))
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(20)
        .padding({
          top: $r('app.float.space_sm'),
          bottom: $r('app.float.space_sm'),
        })
        .width("95%")
        .height(40)
        .onChange((value: string) => {
          this.inputValue = value;
        })
      Row() {
        Text("取消")
          .fontSize($r('app.float.font_button'))
          .fontColor($r('app.color.font_emphasize'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: $r('app.float.space_md'), bottom: $r('app.float.space_xs') })
          .onClick(() => {
            this.onRequestClose();
          })
        Text("确定")
          .fontSize($r('app.float.font_button'))
          .fontColor($r('app.color.font_emphasize'))
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
    .width("92%")
    /* 弹出框按官方规范用超大圆角（32vp） */
    .borderRadius($r('app.float.dialog_radius'))
    .backgroundColor($r('app.color.dialog_bg'));
  }
}

/**
 * 重命名弹窗的开放参数（ComponentContent 方式）
 * 用于将弹窗内容与调用方组件解耦：初始值 + 回调均通过 params 传入
 * 配合全局 @Builder buildRenameDialog 使用
 */
export class RenameDialogParams {
  title: string = "重命名"; // 弹窗标题
  placeholder: string = "请输入内容"; // 输入框占位
  oldValue: string = ""; // 预填值（重命名时使用）
  onConfirm: (value: string) => void = (value: string) => {}; // 确认回调
  onRequestClose: () => void = () => {}; // 关闭回调（父页面负责关闭弹窗）
}

/**
 * 全局 @Builder：包装 RenameInputDialog，供 openCustomDialog(ComponentContent) 使用。
 * 注意：必须用全局函数而非组件成员 @Builder，才能规避成员 Builder 在弹窗场景的绑定/刷新问题
 */
@Builder
export function buildRenameDialog(params: RenameDialogParams) {
  RenameInputDialog({
    title: params.title,
    placeholder: params.placeholder,
    oldValue: params.oldValue,
    onConfirm: (value: string) => {
      params.onConfirm(value);
    },
    onRequestClose: () => {
      params.onRequestClose();
    },
  })
}
