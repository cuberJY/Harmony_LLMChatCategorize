/**
 * 文件附件卡片组件（发送预览条与对话气泡共用，保持两处样式一致）
 * 布局：类型图标（30×40）| 文件名+后缀 / 文件大小（小字）
 *
 * 图标样式（按扩展名硬编码，便于调试）：
 *  - PDF：红底白字 "PDF"
 *  - TXT：浅灰底深灰字 "TXT"
 *  - MD：深灰底白字 "MD"
 *  - XLSX/XLS：绿底白字 "XLSX"
 *  - DOCX/DOC：蓝底白字 "DOCX"
 *  - PPTX/PPT：橙红底白字 "PPTX"
 *
 * showRemove=true（预览条场景）：卡片右上角显示删除按钮，点击触发 onRemove
 */

import { FileAttachment } from "../../model/Message";
import { formatFileSize } from "../../common/Utils";

/* 文件类型图标样式（背景色 + 显示文字 + 文字颜色） */
interface FileIconStyle {
  bg: string;
  text: string;
  color: ResourceColor;
}

@ComponentV2
export struct FileCard {
  /* 文件附件数据（由父级传入，@Param 变化自动刷新） */
  @Param file: FileAttachment = { id: "", name: "", ext: "", size: 0, localPath: "", textContent: "", pageImages: [] };
  /* 是否显示删除按钮（预览条 true / 气泡 false） */
  @Param showRemove: boolean = false;
  /* 删除回调（showRemove=true 时点击触发） */
  @Event onRemove: () => void = () => {};
  /* 预览回调（气泡场景由调用方传入：点击文件卡片 → 调起系统预览；预览条不传 → 无动作） */
  @Event onPreview: () => void = () => {};

  /* 类型图标样式：背景色 + 显示文字 + 文字颜色（按扩展名硬编码） */
  private iconStyle(ext: string): FileIconStyle {
    if (ext === "pdf") {
      return { bg: "#E5484D", text: "PDF", color: Color.White }; // 红底白字
    }
    if (ext === "md") {
      return { bg: "#4A4A52", text: "MD", color: Color.White }; // 深灰底白字
    }
    if (ext === "xlsx" || ext === "xls") {
      return { bg: "#3FA067", text: "XLSX", color: Color.White }; // 绿底白字
    }
    if (ext === "docx" || ext === "doc") {
      return { bg: "#2B7DE9", text: "DOCX", color: Color.White }; // 蓝底白字
    }
    if (ext === "pptx" || ext === "ppt") {
      return { bg: "#D24726", text: "PPTX", color: Color.White }; // 橙红底白字
    }
    return { bg: "#E9E9EC", text: "TXT", color: "#3A3A40" }; // 浅灰底深灰字（默认 txt）
  }

  build() {
    /* 外层 Stack：删除按钮叠加于整个卡片右上角（同图片缩略图删除样式），不遮挡文件名 */
    Stack({ alignContent: Alignment.TopEnd }) {
      Row() {
        /* 左：类型图标（30×40 圆角色块 + 居中类型文字） */
        Text(this.iconStyle(this.file.ext).text)
          .width(36)
          .height(48)
          .fontSize($r('app.float.font_icon_sm'))
          .fontWeight(600)
          .fontColor(this.iconStyle(this.file.ext).color)
          .textAlign(TextAlign.Center)
          .borderRadius(4)
          .backgroundColor(this.iconStyle(this.file.ext).bg)

        /* 右：文件名（单行截断）+ 大小（小字） */
        Column() {
          Text(this.file.name)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontSize($r('app.float.font_file_name'))
            .fontColor($r('app.color.font_primary'))
            .margin({ bottom: $r('app.float.space_xxs') })
          Text(formatFileSize(this.file.size))
            .fontSize($r('app.float.font_file_size'))
            .fontColor($r('app.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({
          left: $r('app.float.space_sm'),
          right: $r('app.float.space_xs'),
          top: $r('app.float.space_md'),
          bottom: $r('app.float.space_md')
        })
      }
      .width(196)
      .height(64)
      .padding({
        left: $r('app.float.space_sm'),
        right: $r('app.float.space_xs')
      })
      .alignItems(VerticalAlign.Center)
      .borderRadius($r('app.float.bubble_radius'))
      .backgroundColor($r('app.color.chat_input_bg')) // 与输入区底色一致的白卡，浅边框区分
      .border({ width: 1, color: $r('app.color.divider') })

      /* 预览条删除按钮（同图片删除样式：黑色半透明圆底 + 白色 x），悬浮于卡片右上角 */
      if (this.showRemove) {
        Button() {
          SymbolGlyph($r("sys.symbol.xmark"))
            .fontSize(10)
            .fontWeight(700)
            .fontColor([Color.White])
        }
        .width(18)
        .height(18)
        .type(ButtonType.Circle)
        .backgroundColor(Color.Transparent)
        .margin({ top: 2, right: 2 })
        .onClick(() => {
          this.onRemove();
        })
      }
    }
    .onClick(() => {
      /* 点击文件卡片 → 预览（气泡场景接入 onPreview；md 跳应用内预览页、其余走系统预览）。
         删除按钮独立于本点击，不冲突 */
      this.onPreview();
    })
  }
}
