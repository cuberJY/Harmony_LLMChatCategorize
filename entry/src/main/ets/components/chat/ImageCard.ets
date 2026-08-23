/**
 * 图片附件卡片组件（发送预览条与对话气泡共用，保持两处样式一致）
 * 布局：正方形缩略图（Base64 data URL 渲染）+ 可选右上角删除按钮 / 共享元素转场
 *
 * 参数化差异（两个使用场景）：
 *  - ChatInput 预览条：cardSize=64、圆角 12、showRemove=true（删除按钮）
 *  - MessageBubble 气泡：cardSize=72、圆角 12（bubble_radius）、geometryId='preview_'+img.id（与全屏预览共享元素转场）、onImageClick 预览
 *
 * showRemove=true：右上角显示删除按钮（黑色半透明圆底 + 白色 x），点击触发 onRemove
 */

import { ImageAttachment } from "../../model/Message";

@ComponentV2
export struct ImageCard {
  /* 图片附件数据（由父级传入，@Param 变化自动刷新） */
  @Param img: ImageAttachment = { id: "", mimeType: "", data: "", name: "" };
  /* 正方形缩略图边长（vp） */
  @Param cardSize: number = 64;
  /* 缩略图圆角（vp） */
  @Param cornerRadius: number = 12;
  /* 是否显示删除按钮（预览条 true / 气泡 false） */
  @Param showRemove: boolean = false;
  /* 共享元素转场 id（气泡场景传 'preview_'+img.id，与全屏预览页衔接；非空才挂 geometryTransition） */
  @Param geometryId: string = "";
  /* 点击回调（气泡场景触发全屏预览） */
  @Event onImageClick: () => void = () => {};
  /* 删除回调（showRemove=true 时点击触发） */
  @Event onRemove: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      /* 缩略图：几何 id 非空时挂共享元素转场（与 PreviewPage 全屏图同 id，Navigation 下用 geometryTransition） */
      if (this.geometryId.length > 0) {
        Image('data:' + this.img.mimeType + ';base64,' + this.img.data)
          .width(this.cardSize)
          .height(this.cardSize)
          .borderRadius(this.cornerRadius)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.divider'))
          .geometryTransition(this.geometryId)
          .onClick(() => {
            this.onImageClick();
          })
      } else {
        Image('data:' + this.img.mimeType + ';base64,' + this.img.data)
          .width(this.cardSize)
          .height(this.cardSize)
          .borderRadius(this.cornerRadius)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.divider'))
          .onClick(() => {
            this.onImageClick();
          })
      }

      /* 右上角删除按钮：深色半透明圆底 + 白色 x，点击删除该图 */
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
        .backgroundColor('#CC000000')
        .margin({ top: 2, right: 2 })
        .onClick(() => {
          this.onRemove();
        })
      }
    }
  }
}
