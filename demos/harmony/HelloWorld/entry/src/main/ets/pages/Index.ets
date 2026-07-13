// Index.ets — 首页
@Entry
@Component
struct Index {

  @State count: number = 0

  build() {
    Column() {
      Text('Hello, 鸿蒙!')
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 120 })

      Text('ArkUI Hello World Demo')
        .fontSize(16)
        .fontColor('#999999')
        .margin({ top: 8 })

      Button('点我计数')
        .fontSize(18)
        .width(160)
        .height(48)
        .margin({ top: 40 })
        .onClick(() => {
          this.count++
        })

      if (this.count > 0) {
        Text(`点击了 ${this.count} 次`)
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 20 })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
