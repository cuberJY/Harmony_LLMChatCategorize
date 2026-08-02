/**
 * 文件夹选择器（共享组件）
 * 用于：移动对话到文件夹、移动文件夹到其他文件夹
 * 显示：标题 + 「不分类」选项 + 候选文件夹列表
 * 注意：folders 需由调用方过滤后传入（移动文件夹时排除自身及子孙，防止成环）
 */

import { Category } from "../model/Category";
import { COLORS, FONT_SIZES, SPACING } from "../common/AppConstants";

@CustomDialog
export struct FolderPickerDialog {
  controller?: CustomDialogController;
  title: string = "移动到"; // 对话框标题（可传入覆盖）
  folders: Category[] = []; // 候选文件夹列表（含各级，扁平展示）
  onSelect: (folderId: string) => void = (folderId: string) => {};

  build() {
    Column({ space: SPACING.XS }) {
      Text(this.title)
        .fontSize(FONT_SIZES.NAME)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width("100%")
        .textAlign(TextAlign.Start)
        .padding({ bottom: SPACING.SM })

      // 「默认」选项：清空分类 / 移到顶级
      Row() {
        Text("默认")
          .fontSize(FONT_SIZES.NAME)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width("100%")
      .height(40)
      .padding({ left: SPACING.MD, right: SPACING.MD })
      .onClick(() => {
        this.onSelect("");
        this.controller?.close();
      })
      Divider()
        .strokeWidth(0.5)
        .color(COLORS.DIVIDER)

      // 全部文件夹列表（可滚动）
      List() {
        ForEach(
          this.folders,
          (cat: Category) => {
            ListItem() {
              Row() {
                Text("📁")
                  .fontSize(FONT_SIZES.ICON_MD)
                  .margin({ right: SPACING.SM })
                Text(cat.name)
                  .fontSize(FONT_SIZES.NAME)
                  .fontColor(COLORS.TEXT_PRIMARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width("100%")
              .height(40)
              .padding({ left: SPACING.MD, right: SPACING.MD })
              .onClick(() => {
                this.onSelect(cat.id);
                this.controller?.close();
              })
            };
          },
          (cat: Category) => cat.id,
        )
      }
      .width("100%")
      .height(280)
    }
    // 固定高度，超出可滚动
    .padding(SPACING.LG)
    .width("85%")
    .borderRadius(16)
    .backgroundColor(Color.White);
  }
}
