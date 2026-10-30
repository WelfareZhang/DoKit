import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { GlobalConfig } from '../config/GlobalConfig';
import { DoKitViewManager } from '../core/DoKitViewManager';
import { DoKitPageStack } from '../core/DoKitPageStack';
import { SystemFragmentRegistry } from '../core/SystemFragmentRigistry';
import { DoKitOverlayState } from '../model/DoKitOverlayState';
import { PerformanceDokitViewManager } from '../kit/performance/PerformanceDokitViewManager';
import { ColorPickManager } from '../kit/colorpick/ColorPickManager';
import { AlignRulerManager } from '../kit/alignruler/AlignRulerManager';
import { ViewCheckManager } from '../kit/viewcheck/ViewCheckManager';
import { LayoutBorderManager } from '../kit/layoutborder/LayoutBorderManager';
import { bindWindowStageToAppStorage, queryMainWindowRectPx } from './DoKitSubWindowUtil';
import { DoKitWindowSlot, WindowRectPx } from './DoKitWindowSlot';
import {
  DOKIT_BALL_ROUTE_NAME,
  DOKIT_BALL_WINDOW_NAME,
  DOKIT_FLOAT_NAME_KEY,
  DOKIT_FLOAT_ROUTE_NAME,
  DOKIT_MAX_FLOAT_WINDOWS,
  DOKIT_MODAL_ROUTE_NAME,
  DOKIT_MODAL_TICK,
  DOKIT_MODAL_WINDOW_NAME,
  DOKIT_PERF_ROUTE_NAME,
  DOKIT_PERF_TICK,
  DOKIT_PERF_WINDOW_NAME
} from './DoKitSubWindowRoute';

const DOMAIN = 0xD0F1;
const TAG = 'DoKitChrome';
const BALL_SIZE = 58;
const BALL_PAD = 8;
const BALL_MARGIN_RIGHT = 16;
const BALL_MARGIN_BOTTOM = 108;
const FLOAT_DEFAULT_W = 300;
const FLOAT_DEFAULT_H = 160;
const PERF_DEFAULT_Y = 88;
/** 悬浮球最高，自定义浮窗其次，功能页和面板在浮窗下面。 */
const BALL_Z = 3;
const FLOAT_Z = 2;
const PERF_Z = 1;
const MODAL_Z = 0;

class VpSize {
  widthVp: number = 0;
  heightVp: number = 0;
}

class VpPoint {
  x: number = 0;
  y: number = 0;
}

/**
 * 窗口调度：
 * Idle 只留球 / 每个自定义浮窗 / 性能条，窗口贴着内容，空白留给主窗。
 * 面板、全屏栈、取色、标尺、控件检查、布局边框共用一个模态窗。自定义浮窗始终盖在这些页面上，只低于悬浮球。
 */
export class DoKitChrome {
  private static stage?: window.WindowStage;
  private static started: boolean = false;
  private static inSync: boolean = false;
  private static listening: boolean = false;
  private static ballReady: boolean = false;
  private static ballX: number = 0;
  private static ballY: number = 0;
  private static ballDragX: number = 0;
  private static ballDragY: number = 0;
  private static ballFollowing: boolean = false;
  private static perfDragY: number = 0;
  private static perfFollowing: boolean = false;
  private static perfY: number = PERF_DEFAULT_Y;
  private static perfH: number = 120;
  private static lastModalSig: string = '';
  private static lastPerfSig: string = '';
  private static readonly ballSlot: DoKitWindowSlot = new DoKitWindowSlot(DOKIT_BALL_WINDOW_NAME);
  private static readonly perfSlot: DoKitWindowSlot = new DoKitWindowSlot(DOKIT_PERF_WINDOW_NAME);
  private static readonly modalSlot: DoKitWindowSlot = new DoKitWindowSlot(DOKIT_MODAL_WINDOW_NAME);
  private static readonly floatSlots: Map<string, DoKitWindowSlot> = new Map();
  private static readonly floatSizes: Map<string, VpSize> = new Map();
  private static readonly floatDragOrigin: Map<string, VpPoint> = new Map();
  private static readonly sizeCallback = (): void => {
    DoKitChrome.sync();
  };

  static attach(stage: window.WindowStage): void {
    DoKitChrome.stage = stage;
    bindWindowStageToAppStorage(stage);
  }

  static show(): void {
    if (!GlobalConfig.debugMode || DoKitChrome.stage === undefined) {
      return;
    }
    DoKitChrome.started = true;
    DoKitChrome.bindHandlers();
    DoKitChrome.listenMainWindow();
    DoKitChrome.sync();
  }

  static detach(): void {
    DoKitChrome.started = false;
    DoKitChrome.unbindHandlers();
    DoKitChrome.unlistenMainWindow();
    DoKitChrome.closeWidgets();
    DoKitChrome.modalSlot.close();
    DoKitChrome.stage = undefined;
    DoKitChrome.ballReady = false;
    DoKitChrome.lastModalSig = '';
    DoKitChrome.lastPerfSig = '';
  }

  static isActive(): boolean {
    return DoKitChrome.started;
  }

  static hide(): void {
    DoKitChrome.started = false;
    DoKitChrome.closeWidgets();
    DoKitChrome.modalSlot.close();
  }

  static isShowing(): boolean {
    return DoKitChrome.ballSlot.hasWindow() || DoKitChrome.modalSlot.hasWindow() || DoKitChrome.perfSlot.hasWindow() ||
      DoKitChrome.floatSlots.size > 0;
  }

  static stageWidthVp(): number {
    return DoKitChrome.mainVp().widthVp;
  }

  static stageHeightVp(): number {
    return DoKitChrome.mainVp().heightVp;
  }

  static ballLeftVp(): number {
    return DoKitChrome.ballX;
  }

  static ballTopVp(): number {
    return DoKitChrome.ballY;
  }

  /** 拖动过程中直接挪窗口，不分配掩码、不等窗口服务回调。 */
  static moveBall(x: number, y: number): void {
    DoKitChrome.ballX = x;
    DoKitChrome.ballY = y;
    DoKitChrome.placeBall();
  }

  static floatLeftVp(name: string): number {
    const config = DoKitViewManager.getViewConfigByName(name);
    return config === undefined ? 20 : DoKitChrome.toNum(config.viewPoint.x);
  }

  static floatTopVp(name: string): number {
    const config = DoKitViewManager.getViewConfigByName(name);
    return config === undefined ? 200 : DoKitChrome.toNum(config.viewPoint.y);
  }

  static moveFloat(name: string, x: number, y: number): void {
    DoKitViewManager.updateViewPoint(name, x, y);
    const slot = DoKitChrome.floatSlots.get(name);
    if (slot !== undefined) {
      slot.place(DoKitChrome.floatRect(name));
      if (!slot.isLayerPinned()) {
        DoKitChrome.keepBallOnTop();
      }
    }
  }

  static liftBall(): void {
    DoKitChrome.keepBallOnTop();
  }

  static finishFloatDrag(name: string): void {
    const slot = DoKitChrome.floatSlots.get(name);
    if (slot === undefined) {
      return;
    }
    slot.whenSettled(() => {
      DoKitChrome.keepBallOnTop();
    });
  }

  static perfTopVp(): number {
    return DoKitChrome.perfY;
  }

  static movePerf(y: number): void {
    DoKitChrome.perfY = y;
    DoKitChrome.placePerf(false);
    if (!DoKitChrome.perfSlot.isLayerPinned()) {
      DoKitChrome.keepBallOnTop();
    }
  }

  static finishPerfDrag(): void {
    DoKitChrome.perfSlot.whenSettled(() => {
      DoKitChrome.keepBallOnTop();
    });
  }

  static resizeFloat(name: string, widthVp: number, heightVp: number): void {
    if (widthVp <= 1 || heightVp <= 1) {
      return;
    }
    const prev = DoKitChrome.floatSizes.get(name);
    if (prev !== undefined && Math.abs(prev.widthVp - widthVp) < 1 && Math.abs(prev.heightVp - heightVp) < 1) {
      return;
    }
    const size = new VpSize();
    size.widthVp = widthVp;
    size.heightVp = heightVp;
    DoKitChrome.floatSizes.set(name, size);
    const slot = DoKitChrome.floatSlots.get(name);
    if (slot !== undefined) {
      DoKitChrome.placeFloat(name, slot, true);
    }
  }

  static resizePerf(heightVp: number): void {
    if (heightVp <= 1) {
      return;
    }
    if (Math.abs(DoKitChrome.perfH - heightVp) < 1) {
      return;
    }
    DoKitChrome.perfH = heightVp;
    DoKitChrome.placePerf(true);
  }

  private static sync(): void {
    if (!DoKitChrome.started || DoKitChrome.stage === undefined || DoKitChrome.inSync) {
      return;
    }
    DoKitChrome.inSync = true;
    if (!DoKitPageStack.isEmpty() && DoKitViewManager.isPanelVisible()) {
      DoKitViewManager.detachToolPanel();
    }
    if (DoKitChrome.wantsModal()) {
      DoKitChrome.closeBallAndPerf();
      DoKitChrome.ensureFloats();
      DoKitChrome.ensureModal(() => {
        DoKitChrome.modalSlot.pinLayer(MODAL_Z, false);
        DoKitChrome.liftFloats();
      });
    } else {
      DoKitChrome.modalSlot.close();
      DoKitChrome.ensureFloats();
      DoKitChrome.ensurePerf();
      DoKitChrome.ensureBall();
      DoKitChrome.liftFloats();
    }
    DoKitChrome.publishTicks();
    DoKitChrome.inSync = false;
  }

  private static wantsModal(): boolean {
    if (!DoKitPageStack.isEmpty() || DoKitViewManager.isPanelVisible()) {
      return true;
    }
    if (ColorPickManager.getInstance().isOverlayOpen() || AlignRulerManager.getInstance().isOverlayOpen()) {
      return true;
    }
    if (ViewCheckManager.getInstance().isOverlayOpen() || LayoutBorderManager.getInstance().isOverlayOpen()) {
      return true;
    }
    return false;
  }

  private static ensureModal(onShown: (() => void) | null): void {
    const stage = DoKitChrome.stage;
    if (stage === undefined) {
      return;
    }
    const bound = queryMainWindowRectPx();
    const rect = new WindowRectPx(0, 0, Math.max(1, bound.widthPx), Math.max(1, bound.heightPx));
    DoKitChrome.modalSlot.open(stage, DOKIT_MODAL_ROUTE_NAME, null, true, true, rect, onShown);
  }

  /** 浮窗盖住功能页和面板，然后再把悬浮球抬到浮窗上面。 */
  private static liftFloats(): void {
    DoKitChrome.floatSlots.forEach((slot: DoKitWindowSlot) => {
      slot.pinLayer(FLOAT_Z, true);
      slot.bringToFront();
    });
    DoKitChrome.keepBallOnTop();
  }

  private static ensureBall(): void {
    const stage = DoKitChrome.stage;
    if (stage === undefined || !DoKitOverlayState.isIconVisible()) {
      DoKitChrome.ballSlot.close();
      return;
    }
    DoKitChrome.ensureBallPosition();
    if (DoKitChrome.ballSlot.hasWindow()) {
      return;
    }
    DoKitChrome.ballSlot.open(stage, DOKIT_BALL_ROUTE_NAME, null, false, false, DoKitChrome.ballRect(), () => {
      DoKitChrome.ballSlot.pinLayer(BALL_Z, false);
      DoKitChrome.keepBallOnTop();
    });
  }

  private static ensureFloats(): void {
    const stage = DoKitChrome.stage;
    if (stage === undefined) {
      return;
    }
    const configs = DoKitViewManager.getViewConfigList();
    const alive: string[] = [];
    const limit = Math.min(configs.length, DOKIT_MAX_FLOAT_WINDOWS);
    if (configs.length > DOKIT_MAX_FLOAT_WINDOWS) {
      hilog.error(DOMAIN, TAG, '自定义浮窗超过 %{public}d 个，多出的未创建窗口', DOKIT_MAX_FLOAT_WINDOWS);
    }
    for (let i = 0; i < limit; i++) {
      const config = configs[i];
      if (config === undefined) {
        continue;
      }
      const name = config.name;
      alive.push(name);
      let slot = DoKitChrome.floatSlots.get(name);
      if (slot === undefined) {
        slot = new DoKitWindowSlot(`DoKitFw_${name}`);
        DoKitChrome.floatSlots.set(name, slot);
      }
      if (slot === undefined || slot.hasWindow()) {
        continue;
      }
      const opened = slot;
      const storage = new LocalStorage();
      storage.setOrCreate(DOKIT_FLOAT_NAME_KEY, name);
      opened.open(stage, DOKIT_FLOAT_ROUTE_NAME, storage, false, false, DoKitChrome.floatRect(name), () => {
        opened.pinLayer(FLOAT_Z, true);
        opened.bringToFront();
        DoKitChrome.keepBallOnTop();
      });
    }
    const stale: string[] = [];
    DoKitChrome.floatSlots.forEach((_slot: DoKitWindowSlot, name: string) => {
      if (alive.indexOf(name) < 0) {
        stale.push(name);
      }
    });
    for (let i = 0; i < stale.length; i++) {
      const name = stale[i];
      const staleSlot = DoKitChrome.floatSlots.get(name);
      if (staleSlot !== undefined) {
        staleSlot.close();
      }
      DoKitChrome.floatSlots.delete(name);
      DoKitChrome.floatSizes.delete(name);
    }
  }

  private static ensurePerf(): void {
    const stage = DoKitChrome.stage;
    if (stage === undefined || !DoKitChrome.perfWanted()) {
      DoKitChrome.perfSlot.close();
      return;
    }
    if (DoKitChrome.perfH <= 1) {
      DoKitChrome.perfH = DoKitChrome.estimatePerfHeight();
    }
    if (DoKitChrome.perfSlot.hasWindow()) {
      return;
    }
    DoKitChrome.perfSlot.open(stage, DOKIT_PERF_ROUTE_NAME, null, false, false, DoKitChrome.perfRect(), () => {
      DoKitChrome.perfSlot.pinLayer(PERF_Z, true);
      DoKitChrome.keepBallOnTop();
    });
  }

  private static closeBallAndPerf(): void {
    DoKitChrome.ballSlot.close();
    DoKitChrome.perfSlot.close();
    DoKitChrome.ballFollowing = false;
    DoKitChrome.perfFollowing = false;
  }

  private static closeFloats(): void {
    DoKitChrome.floatSlots.forEach((slot: DoKitWindowSlot) => {
      slot.close();
    });
    DoKitChrome.floatSlots.clear();
    DoKitChrome.floatSizes.clear();
    DoKitChrome.floatDragOrigin.clear();
  }

  private static closeWidgets(): void {
    DoKitChrome.closeBallAndPerf();
    DoKitChrome.closeFloats();
  }

  private static perfWanted(): boolean {
    return PerformanceDokitViewManager.isFpsOverlayOpen() || PerformanceDokitViewManager.isCpuOverlayOpen() ||
      PerformanceDokitViewManager.isRamOverlayOpen() || PerformanceDokitViewManager.isNetworkOverlayOpen();
  }

  private static placeBall(): void {
    if (!DoKitChrome.ballSlot.hasWindow()) {
      return;
    }
    DoKitChrome.ballSlot.place(DoKitChrome.ballRect());
  }

  private static placeFloat(name: string, slot: DoKitWindowSlot, liftBall: boolean): void {
    const rect = DoKitChrome.floatRect(name);
    if (!liftBall) {
      slot.place(rect);
      return;
    }
    slot.place(rect, () => {
      DoKitChrome.keepBallOnTop();
    });
  }

  private static placePerf(liftBall: boolean): void {
    if (!DoKitChrome.perfSlot.hasWindow()) {
      return;
    }
    const rect = DoKitChrome.perfRect();
    if (!liftBall) {
      DoKitChrome.perfSlot.place(rect);
      return;
    }
    DoKitChrome.perfSlot.place(rect, () => {
      DoKitChrome.keepBallOnTop();
    });
  }

  private static keepBallOnTop(): void {
    DoKitChrome.ballSlot.bringToFront();
  }

  private static ballRect(): WindowRectPx {
    const size = BALL_SIZE + BALL_PAD * 2;
    return DoKitChrome.rectFromVp(DoKitChrome.ballX - BALL_PAD, DoKitChrome.ballY - BALL_PAD, size, size);
  }

  private static floatRect(name: string): WindowRectPx {
    const config = DoKitViewManager.getViewConfigByName(name);
    const size = DoKitChrome.floatSize(name);
    const x = config === undefined ? 20 : DoKitChrome.toNum(config.viewPoint.x);
    const y = config === undefined ? 200 : DoKitChrome.toNum(config.viewPoint.y);
    return DoKitChrome.rectFromVp(x, y, size.widthVp, size.heightVp);
  }

  private static perfRect(): WindowRectPx {
    const main = DoKitChrome.mainVp();
    return DoKitChrome.rectFromVp(0, DoKitChrome.perfY, Math.max(1, main.widthVp), DoKitChrome.perfH);
  }

  private static floatSize(name: string): VpSize {
    const size = DoKitChrome.floatSizes.get(name);
    if (size !== undefined) {
      return size;
    }
    const created = new VpSize();
    created.widthVp = FLOAT_DEFAULT_W;
    created.heightVp = FLOAT_DEFAULT_H;
    return created;
  }

  private static ensureBallPosition(): void {
    const main = DoKitChrome.mainVp();
    const maxX = Math.max(0, main.widthVp - BALL_SIZE);
    const maxY = Math.max(0, main.heightVp - BALL_SIZE);
    if (!DoKitChrome.ballReady) {
      DoKitChrome.ballX = DoKitChrome.clamp(maxX - BALL_MARGIN_RIGHT, 0, maxX);
      DoKitChrome.ballY = DoKitChrome.clamp(maxY - BALL_MARGIN_BOTTOM, 0, maxY);
      DoKitChrome.ballReady = true;
      return;
    }
    DoKitChrome.ballX = DoKitChrome.clamp(DoKitChrome.ballX, 0, maxX);
    DoKitChrome.ballY = DoKitChrome.clamp(DoKitChrome.ballY, 0, maxY);
  }

  private static estimatePerfHeight(): number {
    let n = 0;
    if (PerformanceDokitViewManager.isFpsOverlayOpen()) {
      n++;
    }
    if (PerformanceDokitViewManager.isCpuOverlayOpen()) {
      n++;
    }
    if (PerformanceDokitViewManager.isRamOverlayOpen()) {
      n++;
    }
    if (PerformanceDokitViewManager.isNetworkOverlayOpen()) {
      n++;
    }
    if (n < 1) {
      n = 1;
    }
    return 22 + 14 + n * 80;
  }

  private static publishTicks(): void {
    const modalSig = DoKitChrome.modalSignature();
    if (modalSig !== DoKitChrome.lastModalSig) {
      DoKitChrome.lastModalSig = modalSig;
      DoKitChrome.bump(DOKIT_MODAL_TICK);
    }
    const perfSig = DoKitChrome.perfSignature();
    if (perfSig !== DoKitChrome.lastPerfSig) {
      DoKitChrome.lastPerfSig = perfSig;
      DoKitChrome.bump(DOKIT_PERF_TICK);
    }
  }

  private static modalSignature(): string {
    const top = DoKitPageStack.peek();
    const name = top === undefined ? '' : top.name;
    return `${DoKitPageStack.getRevision()}|${name}|${DoKitViewManager.isPanelVisible() ? 1 : 0}|${ColorPickManager.getInstance().isOverlayOpen() ? 1 : 0}|${AlignRulerManager.getInstance().isOverlayOpen() ? 1 : 0}|${ViewCheckManager.getInstance().isOverlayOpen() ? 1 : 0}|${LayoutBorderManager.getInstance().isOverlayOpen() ? 1 : 0}`;
  }

  private static perfSignature(): string {
    return `${PerformanceDokitViewManager.isFpsOverlayOpen() ? 1 : 0}${PerformanceDokitViewManager.isCpuOverlayOpen() ? 1 : 0}${PerformanceDokitViewManager.isRamOverlayOpen() ? 1 : 0}${PerformanceDokitViewManager.isNetworkOverlayOpen() ? 1 : 0}`;
  }

  private static bump(key: string): void {
    const next = (AppStorage.get<number>(key) ?? 0) + 1;
    AppStorage.setOrCreate(key, next);
  }

  private static bindHandlers(): void {
    DoKitViewManager.setToolPanelChangeHandler((_visible: boolean) => {
      DoKitChrome.sync();
    });
    DoKitViewManager.setWindowRefreshHandler(() => {
      DoKitChrome.sync();
    });
    DoKitPageStack.setChangeHandler(() => {
      DoKitChrome.sync();
    });
    SystemFragmentRegistry.setOpenHandler((_name: string, _system: boolean) => {
      DoKitChrome.sync();
    });
    SystemFragmentRegistry.setCloseHandler(() => {
      DoKitChrome.sync();
    });
    PerformanceDokitViewManager.setOverlayChangeHandler(() => {
      DoKitChrome.sync();
    });
    ColorPickManager.getInstance().setOverlayChangeHandler(() => {
      DoKitChrome.sync();
    });
    AlignRulerManager.getInstance().setOverlayChangeHandler(() => {
      DoKitChrome.sync();
    });
    ViewCheckManager.getInstance().setOverlayChangeHandler(() => {
      DoKitChrome.sync();
    });
    LayoutBorderManager.getInstance().setOverlayChangeHandler(() => {
      DoKitChrome.sync();
    });
    DoKitOverlayState.setIconListener(() => {
      DoKitChrome.sync();
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

  private static listenMainWindow(): void {
    DoKitChrome.unlistenMainWindow();
    const stage = DoKitChrome.stage;
    if (stage === undefined) {
      return;
    }
    try {
      stage.getMainWindowSync().on('windowSizeChange', DoKitChrome.sizeCallback);
      DoKitChrome.listening = true;
    } catch (_e) {
    }
  }

  private static unlistenMainWindow(): void {
    if (!DoKitChrome.listening) {
      return;
    }
    try {
      const stage = DoKitChrome.stage;
      if (stage !== undefined) {
        stage.getMainWindowSync().off('windowSizeChange', DoKitChrome.sizeCallback);
      }
    } catch (_e) {
    }
    DoKitChrome.listening = false;
  }

  private static rectFromVp(xVp: number, yVp: number, widthVp: number, heightVp: number): WindowRectPx {
    return new WindowRectPx(DoKitChrome.vpToPx(xVp), DoKitChrome.vpToPx(yVp), Math.max(1, DoKitChrome.vpToPx(widthVp)),
      Math.max(1, DoKitChrome.vpToPx(heightVp)));
  }

  private static mainVp(): VpSize {
    const px = queryMainWindowRectPx();
    const size = new VpSize();
    size.widthVp = px2vp(px.widthPx);
    size.heightVp = px2vp(px.heightPx);
    return size;
  }

  private static vpToPx(vp: number): number {
    return Math.round(vp2px(vp));
  }

  private static toNum(value: Length | undefined): number {
    if (value === undefined) {
      return 0;
    }
    const n = Number(value);
    if (Number.isNaN(n)) {
      return 0;
    }
    return n;
  }

  private static clamp(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max);
  }
}
