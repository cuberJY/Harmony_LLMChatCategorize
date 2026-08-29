/**
 * 编辑文件夹对话框（状态管理 V2）
 * 可重命名文件夹 + 切换图标颜色
 * 颜色选择：一排色块，点击高亮边框，确认后回调
 * 用于：SideBarPage 收藏 Tab、FolderPage 子文件夹
 *
 * 打开方式：父页面通过 getPromptAction().openCustomDialog 打开；
 * 关闭方式：组件通过 onRequestClose 回调通知父页面 closeCustomDialog(dialogId)
 */

import { FOLDER_COLORS, DEFAULT_FOLDER_COLOR } from "../../common/AppConstants";
import { showToast } from "../../common/Utils";

@ComponentV2
export struct EditFolderDialog {
  @Param title: string = "编辑文件夹";
  @Param oldName: string = ""; // 原文件夹名（预填）
  @Param oldColor: string = DEFAULT_FOLDER_COLOR; // 原图标颜色（高亮选中）
  @Event onConfirm: (name: string, color: string) => void = (name: string, color: string) => {};
  @Event onRequestClose: () => void = () => {}; // 关闭回调（父页面负责关闭弹窗）
  @Event onHeightChange: (heightVp: number) => void = () => {}; // 弹窗渲染高度上报（vp，父页面键盘避让用）
  @Local inputValue: string = ""; // 名称输入内容
  @Local selectedColor: string = DEFAULT_FOLDER_COLOR; // 当前选中的颜色

  aboutToAppear(): void {
    this.inputValue = this.oldName;
    this.selectedColor = this.oldColor;
  }

  @Builder
  private colorChip(color: string) {
    /* 单个颜色块：选中时圆环 */
    Column() {
      /* 色块本体 */
      if (this.selectedColor === color) {
        Row()
          .width(28)
          .height(28)
          .backgroundColor(Color.Transparent)
          .borderRadius(14)
          .borderWidth(8)
          .borderColor(color)
      } else {
        Row()
          .width(24)
          .height(24)
          .borderRadius(12)
          .backgroundColor(color)
      }
    }
    .width(36)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.selectedColor = color;
    });
  }

  build() {
    Column({ space: $r('app.float.space_md') }) {
      /* 标题 */
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

      /* 颜色选择区，8个色块横向排列 */
      Row() {
        ForEach(FOLDER_COLORS, (color: string) => {
          this.colorChip(color)
        }, (color: string) => color)
      }
      .padding({ top: $r('app.float.space_xs'), bottom: $r('app.float.space_xs') })
      .width("100%")
      .justifyContent(FlexAlign.Center)
    
      /* 名称输入 */
      TextInput({ placeholder: "请输入文件夹名称", text: this.inputValue })
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

      /* 按钮区 */
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
              this.onConfirm(this.inputValue.trim(), this.selectedColor);
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
    .backgroundColor($r('app.color.dialog_bg'))
    /* 上报渲染高度（vp）：父页面据此计算键盘弹出时的最小避让位移 */
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.onHeightChange(Math.round(Number(newArea.height)));
    });
  }
}

/**
 * 编辑文件夹弹窗的开放参数（ComponentContent 方式）
 * 用于将弹窗内容与调用方组件解耦：初始值 + 回调均通过 params 传入
 * 配合全局 @Builder buildEditFolderContent 使用
 */
export class EditFolderDialogParams {
  title: string = "编辑文件夹";
  oldName: string = ""; // 原文件夹名（预填）
  oldColor: string = DEFAULT_FOLDER_COLOR; // 原图标颜色（高亮选中）
  onConfirm: (name: string, color: string) => void = (name: string, color: string) => {}; // 确认回调
  onRequestClose: () => void = () => {}; // 关闭回调（父页面负责关闭弹窗）
  onHeightChange: (heightVp: number) => void = () => {}; // 弹窗渲染高度上报（vp，父页面键盘避让用）
}

/**
 * 全局 @Builder：包装 EditFolderDialog，供 openCustomDialog(ComponentContent) 使用。
 * 注意：必须用全局函数而非组件成员 @Builder，才能规避成员 Builder 在弹窗场景的绑定/刷新问题
 */
@Builder
export function buildEditFolderContent(params: EditFolderDialogParams) {
  EditFolderDialog({
    title: params.title,
    oldName: params.oldName,
    oldColor: params.oldColor,
    onConfirm: (name: string, color: string) => {
      params.onConfirm(name, color);
    },
    onRequestClose: () => {
      params.onRequestClose();
    },
    onHeightChange: (heightVp: number) => {
      params.onHeightChange(heightVp);
    },
  })
}
