import { ErrorCategory, errorMessageResource, errorTitleResource, LLMError } from "../../service/LLMError";

/**
 * 生成终止错误卡片（默认收起详情）
 * - 标题行：⚠ + 分类词（生成中断/生成失败/生成异常）+ 右对齐错误码（排查报错用）
 * - 说明行：统一文案（error_* 资源，与 Toast 同源）
 * - 详情区（默认收起）：供应商原始错误信息 + HTTP 状态码
 * 「继续生成」按钮由 MessageBubble 的 actionBar 按 message.isPaused 统一控制（output/network 分类才可续写）
 */
@ComponentV2
export struct MessageErrorCard {
  /* 生成终止时的结构化错误（由 MessageBubble 传入 message.error） */
  @Param error: LLMError | undefined = undefined;
  /**
   * 错误详情展开状态：按"错误身份签名"（code|httpStatus|rawMessage）记录而非 boolean——
   * 组件实例可能被列表复用、同一气泡先后出现多个不同错误，用签名可保证每次新错误默认收起，仅同一错误保持展开
   */
  @Local expandedErrorSignature: string = "";

  build() {
    Column() {
      /* 标题行 */
      Row() {
        /* 警告图标（错误三角标） */
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize($r('app.float.font_icon_xl'))
          .fontWeight(600)
          .fontColor([this.errorAccentColor()])
          .margin({ right: $r('app.float.space_xs') })
        Text(errorTitleResource(this.errCategory()))
          .fontSize($r('app.float.font_body'))
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.errCode())
          .fontSize($r('app.float.font_thinking'))
          .fontColor($r('app.color.text_secondary'))
      }
      .width("100%")
      .margin({
        top: $r('app.float.space_xs'),
        bottom: $r('app.float.space_xs'),
      })

      /* 说明行：与 Toast 相同的简短文案 */
      Text(errorMessageResource(this.errCode()))
        .fontSize($r('app.float.font_body'))
        .fontColor($r('app.color.text_primary'))
        .width("100%")
        .margin({
          top: $r('app.float.space_sm'),
          bottom: $r('app.float.space_sm'),
        })

      /* 详情折叠开关（默认收起）：chevron 图标 + 文案（与思考内容折叠风格一致） */
      Row() {
        SymbolGlyph(
          this.isErrorExpanded() ? $r("sys.symbol.chevron_down") : $r("sys.symbol.chevron_right"),
        )
          .fontSize($r('app.float.font_icon_md'))
          .fontWeight(600)
          .fontColor([$r('app.color.text_secondary')])
          .margin({
            left: this.isErrorExpanded() ? 1 : $r('app.float.space_xs'),
            right: this.isErrorExpanded() ? $r('app.float.space_xs') : $r('app.float.space_sm'),
          })
        Text(this.isErrorExpanded() ? "收起详情" : "查看详情")
          .fontSize($r('app.float.font_thinking'))
          .fontColor($r('app.color.text_secondary'))
      }
      .width("100%")
      .margin({ left: $r('app.float.space_xxs'), })
      .onClick(() => {
        this.expandedErrorSignature = this.isErrorExpanded() ? "" : this.errorSignature();
      })

      /* 展开后的详情区：供应商原始错误信息 + HTTP 状态码 */
      if (this.isErrorExpanded()) {
        Column() {
          Row() {
            Text("原始信息：")
              .fontSize($r('app.float.font_thinking'))
              .fontColor($r('app.color.text_secondary'))
            Text(this.errRawMessage())
              .fontSize($r('app.float.font_thinking'))
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
          }
          .width("100%")
          .alignItems(VerticalAlign.Top)
          .margin({
            left: $r('app.float.space_lg'),
            right: $r('app.float.space_sm'),
            top: $r('app.float.space_xs'),
            bottom: $r('app.float.space_xs'),
          })
          if (this.errHttpStatus() !== undefined) {
            Row() {
              Text("HTTP 状态码：")
                .fontSize($r('app.float.font_thinking'))
                .fontColor($r('app.color.text_secondary'))
              Text(`${this.errHttpStatus()}`)
                .fontSize($r('app.float.font_thinking'))
                .fontColor($r('app.color.text_secondary'))
            }
            .width("100%")
            .margin({
              left: $r('app.float.space_lg'),
              right: $r('app.float.space_sm'),
              top: $r('app.float.space_xs'),
              bottom: $r('app.float.space_xs'),
            })
          }
        }
      }
    }
    .width("100%")
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: $r('app.float.bubble_padding_h'),
      right: $r('app.float.bubble_padding_h'),
      top: $r('app.float.bubble_padding_v'),
      bottom: $r('app.float.bubble_padding_v'),
    })
    .backgroundColor($r('app.color.bubble_bg_thinking'))
    .borderRadius($r('app.float.bubble_radius'))
    /* 左侧强调色条：红色 = 需用户处理（失败）；橙色 = 可重试（异常）；黄色 = 可继续生成（中断） */
    .border({
      width: { left: 6 },
      color: { left: this.errorAccentColor() },
    })
    .margin({ bottom: $r('app.float.space_xs') });
  }

  /* 错误卡片字段安全访问（错误卡片仅在 error 非空时渲染，此处兜底防编译期空检查） */
  private errCategory(): ErrorCategory {
    return this.error !== undefined ? this.error.category : "unknown";
  }

  private errCode(): string {
    return this.error !== undefined ? this.error.code : "";
  }

  private errRawMessage(): string {
    return this.error !== undefined && this.error.rawMessage.length > 0
      ? this.error.rawMessage
      : "无";
  }

  private errHttpStatus(): number | undefined {
    return this.error !== undefined ? this.error.httpStatus : undefined;
  }

  /* 当前错误的身份签名（code|httpStatus|rawMessage）：新错误（签名变化）自动回到收起状态 */
  private errorSignature(): string {
    if (this.error === undefined) {
      return "";
    }
    return `${this.error.code}|${this.error.httpStatus}|${this.error.rawMessage}`;
  }

  /* 详情是否展开：仅当记录的签名与当前错误一致（同一错误保持展开，新错误默认收起） */
  private isErrorExpanded(): boolean {
    const sig = this.errorSignature();
    return sig.length > 0 && this.expandedErrorSignature === sig;
  }

  /* 错误分类 → 强调色（红 = 需用户处理（失败）；橙 = 可重试（异常）；黄 = 可继续生成（中断）） */
  private errorAccentColor(): ResourceColor {
    switch (this.errCategory()) {
      case "auth":
      case "payment":
      case "rate_limit":
      case "context":
      case "config":
        return $r('app.color.text_danger');
      case "server":
      case "unknown":
        return $r('app.color.text_error_2');
      default:
        return $r('app.color.text_error_1');
    }
  }
}
