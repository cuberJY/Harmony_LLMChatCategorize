@Entry
@Component
struct Index {
  @State message: string = 'Hello World';
  @State fontColor: string = '#000000';

  build() {
    RelativeContainer() {
      Text(this.message)
        .id('TestText')
        .fontSize($r('app.float.page_text_font_size'))
        .fontWeight(FontWeight.Normal)
        .fontColor(this.fontColor)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .onClick(() => {
          if (this.message === 'Hello World') {
            this.message = 'Welcome';
            this.fontColor = '#FF0000';
          } else if (this.message === 'Welcome') {
            this.message = 'To';
            this.fontColor = '#FF0000';
          } else if (this.message === 'To') {
            this.message = 'Harmony OS';
            this.fontColor = '#0099DE';
          }  else {
            this.message = 'Hello World';
            this.fontColor = '#000000';
          }
        })
    }
    .height('100%')
    .width('100%')
  }
}