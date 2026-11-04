import { CloseHandler, DoKitParams } from '@didi-hummer/dokit';

/** 浮窗1 的悬浮卡片 */
export class FloatWindow1View {
  static readonly CLASS_NAME: string = 'FloatWindow1';
}

@Builder
export function FloatWindow1Builder(_params: DoKitParams, handler: CloseHandler) {
  Stack({ alignContent: Alignment.TopEnd }) {
    Column() {
      Text('浮窗1')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111111')
      Text('这是一个悬浮窗')
        .fontSize(13)
        .fontColor('#666666')
        .margin({ top: 6 })
    }
    .width(220)
    .height(88)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.White)
    .borderRadius(8)
    .shadow({ radius: 8, color: '#33000000', offsetX: 0, offsetY: 2 })

    Text('✕')
      .fontSize(18)
      .fontColor('#666666')
      .width(40)
      .height(40)
      .textAlign(TextAlign.Center)
      .hitTestBehavior(HitTestMode.Default)
      .monopolizeEvents(true)
      .onClick(() => {
        handler();
      })
  }
}
