/**
 * 导出加载层（页面级全屏覆盖）
 *
 * 背景：图片/PDF 分享点击后有一段等待期 —— ExportCardLayer 渲染隐藏分段卡片
 * （Markdown 异步渲染最长 15s）+ 页面级逐段截图 + 图片拼接（ImageMerger）/
 * PDF 多页生成（PdfExporter），期间用户无任何反馈。本组件在等待期显示
 * LoadingProgress 加载动画 + 半透明遮罩，导出完成由宿主页面置 exportShow=false 卸载。
 *
 * 使用：
 *  页面根 Column 内：
 *    if (this.exportShow) {
 *      ExportLoading()
 *    }
 *
 * 交互：
 *  - 遮罩撑满全屏并 Block 命中测试：点击/滑动不穿透到下层页面；
 *  - 返回键拦截由宿主页面 onBackPressed 处理（见各页面 exportShow 判断）。
 */

@ComponentV2
export struct ExportLoading {
  build() {
    Stack() {
      /* 半透明遮罩：撑满全屏，挡住下层页面交互 */
      Column()
        .width("100%")
        .height("100%")
        .backgroundColor('#66000000')

      /* 居中加载动画 + 提示文案 */
      Column() {
        LoadingProgress()
          .width(60)
          .height(60)
          .color($r('app.color.primary'))
        Text("正在生成分享内容…")
          .fontSize($r('app.float.font_remind'))
          .fontColor(Color.White)
          .margin({ top: $r('app.float.space_md') })
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width("100%")
    .height("100%")
    /* position 定位脱离布局流：无论 ExportCardLayer 隐藏卡片占位如何，都从页面左上角全屏覆盖 */
    .position({ x: 0, y: 0 })
    /* 拦截所有命中测试：加载期间点击不穿透到下层页面 */
    .hitTestBehavior(HitTestMode.Block)
  }
}
