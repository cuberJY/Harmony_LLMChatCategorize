/**
 * 文件夹选择器（共享组件，状态管理 V2）
 * 用于：移动对话到文件夹、移动文件夹到其他文件夹
 * 显示：标题 + 「不分类」选项 + 候选文件夹列表
 * 注意：folders 需由调用方过滤后传入（移动文件夹时排除自身及子孙，防止成环）
 *
 * 打开方式：父页面通过 getPromptAction().openCustomDialog 打开；
 * 关闭方式：组件通过 onRequestClose 回调通知父页面 closeCustomDialog(dialogId)
 */

import { Category } from "../model/Category";

@ComponentV2
export struct FolderPickerDialog {
  @Param title: string = "移动到"; // 对话框标题（可传入覆盖）
  @Param folders: Category[] = []; // 候选文件夹列表（含各级，扁平展示）
  @Event onSelect: (folderId: string) => void = (folderId: string) => {};
  @Event onRequestClose: () => void = () => {}; // 关闭回调（父页面负责关闭弹窗）

  build() {
    Column({ space: $r('app.float.space_xs') }) {
      Text(this.title)
        .fontSize($r('app.float.font_name'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width("100%")
        .textAlign(TextAlign.Start)
        .padding({ bottom: $r('app.float.space_sm') })

      // 「默认」选项：清空分类 / 移到顶级
      Row() {
        Text("默认")
          .fontSize($r('app.float.font_name'))
          .fontColor($r('app.color.text_primary'))
      }
      .width("100%")
      .height(40)
      .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md') })
      .onClick(() => {
        this.onSelect("");
        this.onRequestClose();
      })
      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.divider'))

      // 全部文件夹列表（可滚动）
      List() {
        ForEach(
          this.folders,
          (cat: Category) => {
            ListItem() {
              Row() {
                SymbolGlyph($r("sys.symbol.folder"))
                  .fontSize($r('app.float.font_icon_md'))
                  .fontColor([cat.color])
                  .margin({ right: $r('app.float.space_sm') })
                Text(cat.name)
                  .fontSize($r('app.float.font_name'))
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width("100%")
              .height(40)
              .padding({ left: $r('app.float.space_md'), right: $r('app.float.space_md') })
              .onClick(() => {
                this.onSelect(cat.id);
                this.onRequestClose();
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
    .padding($r('app.float.space_lg'))
    .width("85%")
    .borderRadius(16)
    .backgroundColor($r('app.color.dialog_bg'));
  }
}
