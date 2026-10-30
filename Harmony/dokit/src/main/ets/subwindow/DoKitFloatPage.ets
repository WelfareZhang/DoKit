import { window } from '@kit.ArkUI';
import { CustomViewRegistry } from '../core/CustomViewRegistry';
import { DoKitViewManager } from '../core/DoKitViewManager';
import { DoKitChrome } from './DoKitChrome';
import { DOKIT_FLOAT_NAME_KEY, DOKIT_FLOAT_ROUTE_NAME } from './DoKitSubWindowRoute';

/**
 * 自定义浮窗。窗口贴着内容，手指位移直接挪窗口。
 */
@Entry({ routeName: DOKIT_FLOAT_ROUTE_NAME, useSharedStorage: true })
@Component
struct DoKitFloatPage {
  @LocalStorageProp(DOKIT_FLOAT_NAME_KEY) floatName: string = '';
  private readonly dragThreshold: number = 3;
  private readonly edgeMargin: number = 16;
  private stageW: number = 0;
  private stageH: number = 0;
  private contentW: number = 280;
  private contentH: number = 72;
  private downX: number = 0;
  private downY: number = 0;
  private originX: number = 0;
  private originY: number = 0;
  private lastX: number = 0;
  private lastY: number = 0;
  private dragMoved: boolean = false;

  aboutToAppear(): void {
    this.stageW = DoKitChrome.stageWidthVp();
    this.stageH = DoKitChrome.stageHeightVp();
    try {
      window.findWindow(`DoKitFw_${this.floatName}`).setWindowBackgroundColor('#00000000');
    } catch (_e) {
    }
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max);
  }

  private maxX(): number {
    return Math.max(0, this.stageW - this.contentW);
  }

  private maxY(): number {
    return Math.max(0, this.stageH - this.contentH);
  }

  private pointOf(event: TouchEvent): TouchObject | undefined {
    if (event.touches.length > 0) {
      return event.touches[0];
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0];
    }
    return undefined;
  }

  private onFloatTouch(event: TouchEvent): void {
    const point = this.pointOf(event);
    if (point === undefined) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.stageW = DoKitChrome.stageWidthVp();
      this.stageH = DoKitChrome.stageHeightVp();
      this.downX = point.displayX;
      this.downY = point.displayY;
      this.originX = DoKitChrome.floatLeftVp(this.floatName);
      this.originY = DoKitChrome.floatTopVp(this.floatName);
      this.lastX = this.originX;
      this.lastY = this.originY;
      this.dragMoved = false;
      DoKitChrome.liftBall();
      return;
    }
    if (event.type === TouchType.Move) {
      const x = this.clamp(this.originX + point.displayX - this.downX, 0, this.maxX());
      const y = this.clamp(this.originY + point.displayY - this.downY, 0, this.maxY());
      if (Math.abs(x - this.originX) > this.dragThreshold || Math.abs(y - this.originY) > this.dragThreshold) {
        this.dragMoved = true;
      }
      this.lastX = x;
      this.lastY = y;
      DoKitChrome.moveFloat(this.floatName, x, y);
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (!this.dragMoved) {
        return;
      }
      const centerX = this.lastX + this.contentW / 2;
      const targetX = centerX < this.stageW / 2 ? Math.min(this.edgeMargin, this.maxX()) :
        Math.max(0, this.maxX() - this.edgeMargin);
      const targetY = this.clamp(this.lastY, 0, this.maxY());
      DoKitChrome.moveFloat(this.floatName, targetX, targetY);
      DoKitChrome.finishFloatDrag(this.floatName);
      setTimeout(() => {
        this.dragMoved = false;
      }, 260);
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack() {
        CustomViewRegistry.getBuilder(this.floatName)?.builder(
          DoKitViewManager.getViewConfigByName(this.floatName)?.params,
          DoKitViewManager.getViewConfigByName(this.floatName)?.closeHandler
        )
      }
      .onAreaChange((_oldValue: Area, area: Area) => {
        const width = Number(area.width);
        const height = Number(area.height);
        if (width <= 1 || height <= 1) {
          return;
        }
        this.contentW = width;
        this.contentH = height;
        DoKitChrome.resizeFloat(this.floatName, width, height);
      })
      .onTouch((event: TouchEvent) => {
        this.onFloatTouch(event);
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.Default)
  }
}
