import { window } from '@kit.ArkUI';
import { DokitMemoryConfig } from '../config/DokitMemoryConfig';
import { DoKitViewManager } from '../core/DoKitViewManager';
import { FpsFrameCollector } from '../kit/performance/FpsFrameCollector';
import { DoKitChrome } from './DoKitChrome';
import { DOKIT_BALL_ROUTE_NAME, DOKIT_BALL_WINDOW_NAME } from './DoKitSubWindowRoute';

/**
 * 悬浮球。窗口只有球这么大，手指位移直接挪窗口，按下时不做别的事。
 */
@Entry({ routeName: DOKIT_BALL_ROUTE_NAME })
@Component
struct DoKitBallPage {
  private readonly ballSize: number = 58;
  private readonly pad: number = 8;
  private readonly dragThreshold: number = 3;
  private stageW: number = 0;
  private stageH: number = 0;
  private downX: number = 0;
  private downY: number = 0;
  private originX: number = 0;
  private originY: number = 0;
  private lastX: number = 0;
  private lastY: number = 0;
  private dragMoved: boolean = false;

  @StorageLink(DokitMemoryConfig.STORE_FPS) fpsOn: boolean = false;

  aboutToAppear(): void {
    this.stageW = DoKitChrome.stageWidthVp();
    this.stageH = DoKitChrome.stageHeightVp();
    try {
      window.findWindow(DOKIT_BALL_WINDOW_NAME).setWindowBackgroundColor('#00000000');
    } catch (_e) {
    }
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max);
  }

  private maxX(): number {
    return Math.max(0, this.stageW - this.ballSize);
  }

  private maxY(): number {
    return Math.max(0, this.stageH - this.ballSize);
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

  private onBallTouch(event: TouchEvent): void {
    const point = this.pointOf(event);
    if (point === undefined) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.stageW = DoKitChrome.stageWidthVp();
      this.stageH = DoKitChrome.stageHeightVp();
      this.downX = point.displayX;
      this.downY = point.displayY;
      this.originX = DoKitChrome.ballLeftVp();
      this.originY = DoKitChrome.ballTopVp();
      this.lastX = this.originX;
      this.lastY = this.originY;
      this.dragMoved = false;
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
      DoKitChrome.moveBall(x, y);
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (!this.dragMoved) {
        return;
      }
      const centerX = this.lastX + this.ballSize / 2;
      const targetX = centerX < this.stageW / 2 ? Math.min(16, this.maxX()) : Math.max(0, this.maxX() - 16);
      const targetY = this.clamp(this.lastY, 0, this.maxY());
      this.lastX = targetX;
      this.lastY = targetY;
      DoKitChrome.moveBall(targetX, targetY);
      setTimeout(() => {
        this.dragMoved = false;
      }, 260);
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.fpsOn) {
        FpsFrameCollector()
      }
      Image($r('app.media.dk_doraemon'))
        .width(this.ballSize)
        .height(this.ballSize)
        .objectFit(ImageFit.Contain)
        .position({ x: this.pad, y: this.pad })
        .onTouch((event: TouchEvent) => {
          this.onBallTouch(event);
        })
        .onClick(() => {
          if (this.dragMoved) {
            return;
          }
          DoKitViewManager.attachToolPanel();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.Default)
  }
}
