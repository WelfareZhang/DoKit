import { ComponentContent, window } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';
import { DoKitViewManager } from '../core/DoKitViewManager';
import { DoKitPageStack } from '../core/DoKitPageStack';
import { SystemFragmentRegistry } from '../core/SystemFragmentRigistry';
import { CustomViewRegistry, DoKitParams } from '../core/CustomViewRegistry';
import { DoKitOverlayState } from '../model/DoKitOverlayState';
import { DoKitLayerHost } from '../components/DoKitLayerHost';
import { PerformanceDokitViewManager } from '../kit/performance/PerformanceDokitViewManager';
import { PerformanceDoKitView } from '../kit/performance/PerformanceDoKitView';
import { FpsFrameCollector } from '../kit/performance/FpsFrameCollector';
import { ColorPickManager } from '../kit/colorpick/ColorPickManager';
import { AlignRulerManager } from '../kit/alignruler/AlignRulerManager';
import { ViewCheckManager } from '../kit/viewcheck/ViewCheckManager';
import { LayoutBorderManager } from '../kit/layoutborder/LayoutBorderManager';
import { DokitMemoryConfig } from '../config/DokitMemoryConfig';
import { bindWindowStageToAppStorage } from '../subwindow/DoKitSubWindowUtil';
import { DOKIT_MODAL_TICK } from '../subwindow/DoKitSubWindowRoute';
import { ColorPickerDoKitView } from '../kit/colorpick/ColorPickerDoKitView';
import { AlignRulerDoKitView } from '../kit/alignruler/AlignRulerDoKitView';
import { ViewCheckDoKitView } from '../kit/viewcheck/ViewCheckDoKitView';
import { ViewCheckTree } from '../kit/viewcheck/ViewCheckTree';
import { LayoutBorderDoKitView } from '../kit/layoutborder/LayoutBorderDoKitView';
import { DoKitBack } from './DoKitBack';

const DOKIT_OVERLAY_TICK: string = 'dokitOverlayTick';
const DOKIT_NAV_INSET_PX: string = 'dokitNavInsetPx';
const DOKIT_BALL_X: string = 'dokitBallX';
const DOKIT_BALL_Y: string = 'dokitBallY';

/**
 * 主窗口浮层，对标 Android NormalDoKitViewManager 挂到 DecorView 的那一层。
 * 根节点不接触摸，球、浮标、曲线、面板都是同一窗口里的子组件。
 */
export class DoKitMainOverlay {
  private static stage: window.WindowStage | undefined = undefined;
  private static content: ComponentContent<Object> | null = null;
  private static shown: boolean = false;
  private static inSync: boolean = false;
  private static pageWasOpen: boolean = false;
  private static lastToolSig: string = '';
  /** 全屏页打开期间才拉起的浮标，才画在全屏页上面 */
  static colorDuringPage: boolean = false;
  static rulerDuringPage: boolean = false;
  static viewDuringPage: boolean = false;
  static layoutDuringPage: boolean = false;

  static attach(stage: window.WindowStage): void {
    DoKitMainOverlay.stage = stage;
    bindWindowStageToAppStorage(stage);
    DoKitMainOverlay.bindNavInset(stage);
  }

  static show(): void {
    const stage = DoKitMainOverlay.stage;
    if (DoKitMainOverlay.shown || stage === undefined) {
      return;
    }
    DoKitMainOverlay.bindHandlers();
    try {
      const uiContext = stage.getMainWindowSync().getUIContext();
      DoKitMainOverlay.content = new ComponentContent<Object>(uiContext, wrapBuilder(buildDoKitOverlayHost));
      uiContext.getOverlayManager().addComponentContent(DoKitMainOverlay.content);
      DoKitMainOverlay.shown = true;
      DoKitMainOverlay.syncState();
    } catch (_e) {
      DoKitMainOverlay.unbindHandlers();
      DoKitMainOverlay.content = null;
      DoKitMainOverlay.shown = false;
    }
  }

  static detach(): void {
    DoKitMainOverlay.unbindHandlers();
    const stage = DoKitMainOverlay.stage;
    const content = DoKitMainOverlay.content;
    if (stage !== undefined && content !== null) {
      try {
        stage.getMainWindowSync().getUIContext().getOverlayManager().removeComponentContent(content);
      } catch (_e) {
      }
    }
    DoKitMainOverlay.content = null;
    DoKitMainOverlay.shown = false;
    DoKitMainOverlay.stage = undefined;
  }

  private static bindNavInset(stage: window.WindowStage): void {
    try {
      const mainWin = stage.getMainWindowSync();
      const nav = mainWin.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      AppStorage.setOrCreate(DOKIT_NAV_INSET_PX, nav.bottomRect.height);
      mainWin.on('avoidAreaChange', (data) => {
        if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          AppStorage.setOrCreate(DOKIT_NAV_INSET_PX, data.area.bottomRect.height);
        }
      });
    } catch (_e) {
    }
  }

  private static toolSignature(): string {
    const color = ColorPickManager.getInstance().isOverlayOpen() ? '1' : '0';
    const ruler = AlignRulerManager.getInstance().isOverlayOpen() ? '1' : '0';
    const view = ViewCheckManager.getInstance().isOverlayOpen() ? '1' : '0';
    const layout = LayoutBorderManager.getInstance().isOverlayOpen() ? '1' : '0';
    return `${color}${ruler}${view}${layout}`;
  }

  private static syncState(): void {
    if (DoKitMainOverlay.inSync) {
      return;
    }
    DoKitMainOverlay.inSync = true;
    const page = !DoKitPageStack.isEmpty();
    const sig = DoKitMainOverlay.toolSignature();
    if (page && !DoKitMainOverlay.pageWasOpen) {
      DoKitMainOverlay.colorDuringPage = false;
      DoKitMainOverlay.rulerDuringPage = false;
      DoKitMainOverlay.viewDuringPage = false;
      DoKitMainOverlay.layoutDuringPage = false;
      if (ColorPickManager.getInstance().isOverlayOpen()) {
        ColorPickManager.getInstance().close();
      }
    } else if (page && sig !== DoKitMainOverlay.lastToolSig) {
      DoKitMainOverlay.colorDuringPage = ColorPickManager.getInstance().isOverlayOpen();
      DoKitMainOverlay.rulerDuringPage = AlignRulerManager.getInstance().isOverlayOpen();
      DoKitMainOverlay.viewDuringPage = ViewCheckManager.getInstance().isOverlayOpen();
      DoKitMainOverlay.layoutDuringPage = LayoutBorderManager.getInstance().isOverlayOpen();
    } else if (!page && DoKitMainOverlay.pageWasOpen) {
      DoKitMainOverlay.colorDuringPage = false;
      DoKitMainOverlay.rulerDuringPage = false;
      DoKitMainOverlay.viewDuringPage = false;
      DoKitMainOverlay.layoutDuringPage = false;
      if (ColorPickManager.getInstance().isOverlayOpen()) {
        ColorPickManager.getInstance().close();
      }
    }
    DoKitMainOverlay.pageWasOpen = !DoKitPageStack.isEmpty();
    DoKitMainOverlay.lastToolSig = DoKitMainOverlay.toolSignature();
    if (!DoKitPageStack.isEmpty() && DoKitViewManager.isPanelVisible()) {
      DoKitViewManager.detachToolPanel();
    }
    DoKitMainOverlay.bump();
    DoKitMainOverlay.inSync = false;
  }

  private static bump(): void {
    const overlay = (AppStorage.get<number>(DOKIT_OVERLAY_TICK) ?? 0) + 1;
    AppStorage.setOrCreate(DOKIT_OVERLAY_TICK, overlay);
    const modal = (AppStorage.get<number>(DOKIT_MODAL_TICK) ?? 0) + 1;
    AppStorage.setOrCreate(DOKIT_MODAL_TICK, modal);
  }

  private static bindHandlers(): void {
    DoKitViewManager.setToolPanelChangeHandler((_visible: boolean) => {
      DoKitMainOverlay.syncState();
    });
    DoKitViewManager.setWindowRefreshHandler(() => {
      DoKitMainOverlay.syncState();
    });
    DoKitPageStack.setChangeHandler(() => {
      DoKitMainOverlay.syncState();
    });
    SystemFragmentRegistry.setOpenHandler((_name: string, _system: boolean) => {
      DoKitMainOverlay.syncState();
    });
    SystemFragmentRegistry.setCloseHandler(() => {
      DoKitMainOverlay.syncState();
    });
    PerformanceDokitViewManager.setOverlayChangeHandler(() => {
      DoKitMainOverlay.syncState();
    });
    ColorPickManager.getInstance().setOverlayChangeHandler(() => {
      DoKitMainOverlay.syncState();
    });
    AlignRulerManager.getInstance().setOverlayChangeHandler(() => {
      DoKitMainOverlay.syncState();
    });
    ViewCheckManager.getInstance().setOverlayChangeHandler(() => {
      DoKitMainOverlay.syncState();
    });
    LayoutBorderManager.getInstance().setOverlayChangeHandler(() => {
      DoKitMainOverlay.syncState();
    });
    DoKitOverlayState.setIconListener(() => {
      DoKitMainOverlay.syncState();
    });
  }

  private static unbindHandlers(): void {
    DoKitViewManager.setToolPanelChangeHandler(null);
    DoKitViewManager.setWindowRefreshHandler(null);
    DoKitPageStack.setChangeHandler(null);
    SystemFragmentRegistry.setOpenHandler(null);
    SystemFragmentRegistry.setCloseHandler(null);
    PerformanceDokitViewManager.setOverlayChangeHandler(null);
    ColorPickManager.getInstance().setOverlayChangeHandler(null);
    AlignRulerManager.getInstance().setOverlayChangeHandler(null);
    ViewCheckManager.getInstance().setOverlayChangeHandler(null);
    LayoutBorderManager.getInstance().setOverlayChangeHandler(null);
    DoKitOverlayState.setIconListener(null);
  }
}

@Builder
function buildDoKitOverlayHost() {
  DoKitOverlayHost()
}

@Component
struct DoKitOverlayHost {
  @StorageLink(DOKIT_OVERLAY_TICK) @Watch('reload') tick: number = 0;
  @StorageProp('topRectHeight') topRectHeightPx: number = 0;
  @StorageProp(DOKIT_NAV_INSET_PX) navInsetPx: number = 0;
  @State private floatNames: string[] = [];
  @State private stageW: number = 0;
  @State private stageH: number = 0;
  @State private hasPage: boolean = false;
  @State private showLayer: boolean = false;
  @State private showPerf: boolean = false;
  @State private showFps: boolean = false;
  @State private showCpu: boolean = false;
  @State private showRam: boolean = false;
  @State private showNetwork: boolean = false;
  @State private showBall: boolean = true;
  @State private showColor: boolean = false;
  @State private showRuler: boolean = false;
  @State private showViewCheck: boolean = false;
  @State private showLayout: boolean = false;
  @State private needBack: boolean = false;

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    if (this.tick < 0) {
      return;
    }
    const names: string[] = [];
    const configs = DoKitViewManager.getViewConfigList();
    for (let i = 0; i < configs.length; i++) {
      const config = configs[i];
      if (config === undefined) {
        continue;
      }
      names.push(config.name);
    }
    this.floatNames = names;
    this.hasPage = !DoKitPageStack.isEmpty();
    const showPanel = DoKitViewManager.isPanelVisible() && !this.hasPage;
    this.showLayer = showPanel || this.hasPage;
    this.showFps = PerformanceDokitViewManager.isFpsOverlayOpen();
    this.showCpu = PerformanceDokitViewManager.isCpuOverlayOpen();
    this.showRam = PerformanceDokitViewManager.isRamOverlayOpen();
    this.showNetwork = PerformanceDokitViewManager.isNetworkOverlayOpen();
    this.showPerf = this.showFps || this.showCpu || this.showRam || this.showNetwork;
    this.showBall = DoKitOverlayState.isIconVisible() && !this.hasPage;
    this.showColor = ColorPickManager.getInstance().isOverlayOpen() &&
      (!this.hasPage || DoKitMainOverlay.colorDuringPage);
    this.showRuler = AlignRulerManager.getInstance().isOverlayOpen() &&
      (!this.hasPage || DoKitMainOverlay.rulerDuringPage);
    this.showViewCheck = ViewCheckManager.getInstance().isOverlayOpen() &&
      (!this.hasPage || DoKitMainOverlay.viewDuringPage);
    this.showLayout = LayoutBorderManager.getInstance().isOverlayOpen() &&
      (!this.hasPage || DoKitMainOverlay.layoutDuringPage);
    this.needBack = this.hasPage || DoKitViewManager.isPanelVisible();
    if (this.needBack) {
      try {
        focusControl.requestFocus(ViewCheckTree.FLOATING_ID);
      } catch (_e) {
      }
    }
  }

  private topInsetVp(): number {
    if (this.topRectHeightPx <= 0) {
      return 0;
    }
    return px2vp(this.topRectHeightPx);
  }

  private bottomInsetVp(): number {
    if (this.navInsetPx <= 0) {
      return 0;
    }
    return px2vp(this.navInsetPx);
  }

  @Builder
  private PerfChart() {
    PerformanceDoKitView({
      canDrag: false,
      showFps: this.showFps,
      showCpu: this.showCpu,
      showRam: this.showRam,
      showNetwork: this.showNetwork,
      topOffset: this.topInsetVp(),
      containerHeight: this.stageH,
      onClose: (): void => {
        PerformanceDokitViewManager.closeAllOverlaysFromView();
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.showFps || DokitMemoryConfig.FPS_STATUS) {
        FpsFrameCollector()
      }
      if (!this.hasPage) {
        ForEach(this.floatNames, (name: string) => {
          DoKitOverlayFloat({
            name: name,
            stageW: this.stageW,
            stageH: this.stageH,
            topInset: this.topInsetVp(),
            bottomInset: this.bottomInsetVp()
          })
        }, (name: string) => name)
        if (this.showPerf) {
          this.PerfChart()
        }
      }
      if (this.showLayer) {
        DoKitLayerHost()
      }
      if (this.showLayout) {
        LayoutBorderDoKitView()
      }
      if (this.showViewCheck) {
        ViewCheckDoKitView({
          containerWidth: this.stageW,
          containerHeight: this.stageH
        })
      }
      if (this.showRuler) {
        AlignRulerDoKitView({
          containerWidth: this.stageW,
          containerHeight: this.stageH
        })
      }
      if (this.showColor) {
        ColorPickerDoKitView({
          containerWidth: this.stageW,
          containerHeight: this.stageH
        })
      }
      if (this.hasPage && this.showPerf) {
        this.PerfChart()
      }
      if (this.showBall) {
        DoKitOverlayBall({
          stageW: this.stageW,
          stageH: this.stageH,
          topInset: this.topInsetVp(),
          bottomInset: this.bottomInsetVp()
        })
      }
    }
    .id(ViewCheckTree.FLOATING_ID)
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.None)
    .focusable(this.needBack)
    .onKeyPreIme((event: KeyEvent): boolean => {
      if (!this.needBack || event.type !== KeyType.Down || event.keyCode !== KeyCode.KEYCODE_BACK) {
        return false;
      }
      return DoKitBack.consume();
    })
    .onAreaChange((_oldValue: Area, area: Area) => {
      const width = Number(area.width);
      const height = Number(area.height);
      if (width > 1) {
        this.stageW = width;
      }
      if (height > 1) {
        this.stageH = height;
      }
    })
  }
}

@Component
struct DoKitOverlayBall {
  private readonly ballSize: number = 58;
  private readonly edgeMargin: number = 16;
  private readonly dragThreshold: number = 4;
  private readonly tapLimitMs: number = 1000;
  @Prop stageW: number = 0;
  @Prop stageH: number = 0;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State private x: number = 0;
  @State private y: number = 0;
  private placed: boolean = false;
  private downX: number = 0;
  private downY: number = 0;
  private originX: number = 0;
  private originY: number = 0;
  private downTime: number = 0;
  private dragMoved: boolean = false;

  aboutToAppear(): void {
    this.restore();
  }

  private restore(): void {
    const savedX = AppStorage.get<number>(DOKIT_BALL_X);
    const savedY = AppStorage.get<number>(DOKIT_BALL_Y);
    if (savedX === undefined || savedY === undefined) {
      return;
    }
    this.x = savedX;
    this.y = savedY;
    this.placed = true;
  }

  private save(): void {
    AppStorage.setOrCreate(DOKIT_BALL_X, this.x);
    AppStorage.setOrCreate(DOKIT_BALL_Y, this.y);
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max);
  }

  private minY(): number {
    return Math.max(0, this.topInset);
  }

  private maxX(): number {
    return Math.max(0, this.stageW - this.ballSize);
  }

  private maxY(): number {
    return Math.max(this.minY(), this.stageH - this.ballSize - Math.max(0, this.bottomInset));
  }

  private placeDefault(): void {
    if (this.placed || this.stageW <= 1 || this.stageH <= 1) {
      return;
    }
    this.x = Math.max(0, this.maxX() - this.edgeMargin);
    this.y = Math.max(this.minY(), this.maxY() - this.edgeMargin);
    this.placed = true;
    this.save();
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
    this.placeDefault();
    const point = this.pointOf(event);
    if (point === undefined) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.downX = point.displayX;
      this.downY = point.displayY;
      this.originX = this.x;
      this.originY = this.y;
      this.downTime = Date.now();
      this.dragMoved = false;
      return;
    }
    if (event.type === TouchType.Move) {
      const x = this.clamp(this.originX + point.displayX - this.downX, 0, this.maxX());
      const y = this.clamp(this.originY + point.displayY - this.downY, this.minY(), this.maxY());
      if (Math.abs(x - this.originX) > this.dragThreshold || Math.abs(y - this.originY) > this.dragThreshold) {
        this.dragMoved = true;
      }
      this.x = x;
      this.y = y;
      this.save();
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      const quick = Date.now() - this.downTime < this.tapLimitMs;
      if (!this.dragMoved && quick && event.type === TouchType.Up) {
        DoKitViewManager.attachToolPanel();
        return;
      }
      if (!this.dragMoved) {
        return;
      }
      const centerX = this.x + this.ballSize / 2;
      const targetX = centerX < this.stageW / 2 ? Math.min(this.edgeMargin, this.maxX()) :
        Math.max(0, this.maxX() - this.edgeMargin);
      const targetY = this.clamp(this.y, this.minY(), this.maxY());
      animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
        this.x = targetX;
        this.y = targetY;
      });
      this.save();
    }
  }

  build() {
    Image($r('app.media.dk_doraemon'))
      .width(this.ballSize)
      .height(this.ballSize)
      .objectFit(ImageFit.Contain)
      .position({ x: this.x, y: this.y })
      .hitTestBehavior(HitTestMode.Default)
      .onAppear(() => {
        this.placeDefault();
      })
      .onTouch((event: TouchEvent) => {
        this.onBallTouch(event);
      })
  }
}

@Component
struct DoKitOverlayFloat {
  private readonly dragThreshold: number = 4;
  private readonly tapLimitMs: number = 1000;
  @Prop name: string = '';
  @Prop @Watch('onFrameChange') stageW: number = 0;
  @Prop @Watch('onFrameChange') stageH: number = 0;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State private x: number = 20;
  @State private y: number = 200;
  private contentW: number = 1;
  private contentH: number = 1;
  private placed: boolean = false;
  private land: boolean = false;
  private downX: number = 0;
  private downY: number = 0;
  private originX: number = 0;
  private originY: number = 0;
  private downTime: number = 0;
  private dragMoved: boolean = false;

  aboutToAppear(): void {
    this.onFrameChange();
  }

  private onFrameChange(): void {
    if (this.stageW <= 1 || this.stageH <= 1) {
      return;
    }
    const land = this.stageW > this.stageH;
    if (!this.placed) {
      this.land = land;
      this.applySaved(land);
      this.placed = true;
      return;
    }
    if (land === this.land) {
      return;
    }
    this.writeSaved(this.land);
    this.land = land;
    this.applySaved(land);
  }

  private applySaved(land: boolean): void {
    const config = DoKitViewManager.getViewConfigByName(this.name);
    if (config === undefined) {
      return;
    }
    if (land) {
      this.x = config.landscapeX;
      this.y = config.landscapeY;
      return;
    }
    this.x = config.portraitX;
    this.y = config.portraitY;
  }

  private writeSaved(land: boolean): void {
    const config = DoKitViewManager.getViewConfigByName(this.name);
    if (config === undefined) {
      return;
    }
    config.viewPoint = { x: this.x, y: this.y };
    if (land) {
      config.landscapeX = this.x;
      config.landscapeY = this.y;
      return;
    }
    config.portraitX = this.x;
    config.portraitY = this.y;
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max);
  }

  private minY(): number {
    return Math.max(0, this.topInset);
  }

  private maxX(): number {
    return Math.max(0, this.stageW - this.contentW);
  }

  private maxY(): number {
    return Math.max(this.minY(), this.stageH - this.contentH - Math.max(0, this.bottomInset));
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

  private paramsOf(): DoKitParams {
    const config = DoKitViewManager.getViewConfigByName(this.name);
    if (config === undefined || config.params === undefined) {
      return {};
    }
    return config.params;
  }

  private closeOf(): () => void {
    const config = DoKitViewManager.getViewConfigByName(this.name);
    if (config === undefined || config.closeHandler === undefined) {
      return (): void => {
      };
    }
    return config.closeHandler;
  }

  private onFloatTouch(event: TouchEvent): void {
    const point = this.pointOf(event);
    if (point === undefined) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.downX = point.displayX;
      this.downY = point.displayY;
      this.originX = this.x;
      this.originY = this.y;
      this.downTime = Date.now();
      this.dragMoved = false;
      return;
    }
    if (event.type === TouchType.Move) {
      const x = this.clamp(this.originX + point.displayX - this.downX, 0, this.maxX());
      const y = this.clamp(this.originY + point.displayY - this.downY, this.minY(), this.maxY());
      if (Math.abs(x - this.originX) > this.dragThreshold || Math.abs(y - this.originY) > this.dragThreshold) {
        this.dragMoved = true;
      }
      this.x = x;
      this.y = y;
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (!this.dragMoved) {
        return;
      }
      if (Date.now() - this.downTime < this.tapLimitMs && event.type === TouchType.Cancel) {
        return;
      }
      this.writeSaved(this.land);
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      CustomViewRegistry.getBuilder(this.name)?.builder(this.paramsOf(), this.closeOf())
    }
    .position({ x: this.x, y: this.y })
    .hitTestBehavior(HitTestMode.Default)
    .onAreaChange((_oldValue: Area, area: Area) => {
      const width = Number(area.width);
      const height = Number(area.height);
      if (width <= 1 || height <= 1) {
        return;
      }
      this.contentW = width;
      this.contentH = height;
      this.x = this.clamp(this.x, 0, this.maxX());
      this.y = this.clamp(this.y, this.minY(), this.maxY());
    })
    .onTouch((event: TouchEvent) => {
      this.onFloatTouch(event);
    })
  }
}
