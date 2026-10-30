import { window } from '@kit.ArkUI';
import { PerformanceDokitViewManager } from '../kit/performance/PerformanceDokitViewManager';
import { PerformanceDoKitView } from '../kit/performance/PerformanceDoKitView';
import { DOKIT_PERF_ROUTE_NAME, DOKIT_PERF_TICK, DOKIT_PERF_WINDOW_NAME } from './DoKitSubWindowRoute';

/**
 * 性能条。窗口高度跟图表走，上下拖动只移动窗口。
 */
@Entry({ routeName: DOKIT_PERF_ROUTE_NAME })
@Component
struct DoKitPerfPage {
  @StorageLink(DOKIT_PERF_TICK) @Watch('pull') tick: number = 0;
  @State showFps: boolean = false;
  @State showCpu: boolean = false;
  @State showRam: boolean = false;
  @State showNetwork: boolean = false;

  aboutToAppear(): void {
    try {
      window.findWindow(DOKIT_PERF_WINDOW_NAME).setWindowBackgroundColor('#00000000');
    } catch (_e) {
    }
    this.pull();
  }

  pull(): void {
    if (this.tick < 0) {
      return;
    }
    this.showFps = PerformanceDokitViewManager.isFpsOverlayOpen();
    this.showCpu = PerformanceDokitViewManager.isCpuOverlayOpen();
    this.showRam = PerformanceDokitViewManager.isRamOverlayOpen();
    this.showNetwork = PerformanceDokitViewManager.isNetworkOverlayOpen();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PerformanceDoKitView({
        windowMode: true,
        showFps: this.showFps,
        showCpu: this.showCpu,
        showRam: this.showRam,
        showNetwork: this.showNetwork,
        topOffset: 0,
        onClose: () => {
          PerformanceDokitViewManager.closeAllOverlaysFromView();
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.None)
  }
}
