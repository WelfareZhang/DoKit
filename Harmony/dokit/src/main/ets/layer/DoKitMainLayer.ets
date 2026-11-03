import { ComponentContent, window } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';
import { DoKitViewManager } from '../core/DoKitViewManager';
import { DoKitPageStack } from '../core/DoKitPageStack';
import { SystemFragmentRegistry } from '../core/SystemFragmentRigistry';
import { CloseHandler, CustomViewBuilder, CustomViewRegistry, DoKitParams } from '../core/CustomViewRegistry';
import { DoKitOverlayState } from '../model/DoKitOverlayState';
import { DoKitLayerHost } from '../components/DoKitLayerHost';
import { ViewCheckTree } from '../kit/viewcheck/ViewCheckTree';
import { DoKitBack } from './DoKitBack';
import { DoKitLayerBuilder, DoKitLayerName, DoKitLayerSnap, DoKitLayers } from './DoKitLayers';
import { DOKIT_MODAL_TICK, DOKIT_NAV_INSET_PX, DOKIT_OVERLAY_TICK, DOKIT_TOP_RECT_HEIGHT, bindWindowStageToAppStorage, unbindWindowAvoidArea } from '../util/DoKitWindowUtil';

const DOKIT_BALL_X: string = 'dokitBallX';
const DOKIT_BALL_Y: string = 'dokitBallY';
const DOKIT_BALL_LAND_X: string = 'dokitBallLandX';
const DOKIT_BALL_LAND_Y: string = 'dokitBallLandY';

/**
 * 主窗口浮层。容器里只按 DoKitLayers 的顺序画，后挂上的盖住先挂上的。
 */
export class DoKitMainLayer {
  private static stage: window.WindowStage | undefined = undefined;
  private static content: ComponentContent<Object> | null = null;
  private static shown: boolean = false;
  private static inSync: boolean = false;
  private static pageWasOpen: boolean = false;
  private static lastModalKey: string = '';
  /** 当前全屏栈顶。变了才让全屏层重建，避免压栈后还画着旧页。 */
  private static lastPageKey: string = '';

  /** 记下主窗口，并开始监听状态栏、导航栏避让。 */
  static attach(stage: window.WindowStage): void {
    DoKitMainLayer.stage = stage;
    bindWindowStageToAppStorage(stage);
  }

  /** 把浮层挂到主窗口的 OverlayManager。已经挂过、或还没有窗口时直接返回。 */
  static show(): void {
    const stage = DoKitMainLayer.stage;
    if (DoKitMainLayer.shown || stage === undefined) {
      return;
    }
    DoKitMainLayer.bindHandlers();
    try {
      const uiContext = stage.getMainWindowSync().getUIContext();
      DoKitMainLayer.content = new ComponentContent<Object>(uiContext, wrapBuilder(buildDoKitOverlayHost));
      uiContext.getOverlayManager().addComponentContent(DoKitMainLayer.content);
      DoKitMainLayer.shown = true;
      DoKitMainLayer.syncFrame();
    } catch (_e) {
      DoKitMainLayer.unbindHandlers();
      DoKitMainLayer.content = null;
      DoKitMainLayer.shown = false;
    }
  }

  /** 浮层是否已经挂上。 */
  static isShown(): boolean {
    return DoKitMainLayer.shown;
  }

  /** 从 OverlayManager 卸下浮层。窗口和层表还留着。 */
  static hide(): void {
    DoKitMainLayer.removeContent();
  }

  /** 卸下浮层，停止避让监听，并清空层表和窗口。 */
  static detach(): void {
    DoKitMainLayer.removeContent();
    unbindWindowAvoidArea();
    DoKitLayers.clear();
    DoKitMainLayer.stage = undefined;
    DoKitMainLayer.pageWasOpen = false;
    DoKitMainLayer.lastModalKey = '';
    DoKitMainLayer.lastPageKey = '';
  }

  /** 移除 OverlayManager 上的那一块内容，并解掉刷新回调。 */
  private static removeContent(): void {
    DoKitMainLayer.unbindHandlers();
    const stage = DoKitMainLayer.stage;
    const content = DoKitMainLayer.content;
    if (stage !== undefined && content !== null) {
      try {
        stage.getMainWindowSync().getUIContext().getOverlayManager().removeComponentContent(content);
      } catch (_e) {
      }
    }
    DoKitMainLayer.content = null;
    DoKitMainLayer.shown = false;
  }

  /** 按当前状态重排悬浮球、工具面板、全屏页和浮窗。重入时直接返回。 */
  private static syncFrame(): void {
    if (DoKitMainLayer.inSync) {
      return;
    }
    DoKitMainLayer.inSync = true;
    // 页面栈里现在有没有全屏页
    const page = !DoKitPageStack.isEmpty();
    // 上次没有、这次有：全屏页刚打开
    const entered = page && !DoKitMainLayer.pageWasOpen;
    // 上次有、这次没有：全屏页刚关掉
    const left = !page && DoKitMainLayer.pageWasOpen;
    // 记下这次的状态，下次才能看出是不是刚进出
    DoKitMainLayer.pageWasOpen = page;
    // 连续改层表，结束时只提交一次
    DoKitLayers.batch(() => {
      // 只在刚打开或刚关掉全屏页时通知。取色器据此关掉自己
      if (entered || left) {
        DoKitLayers.notifyPageEdge(entered, left);
      }
      // 有全屏页时先关掉工具面板，两者不同时存在
      if (page && DoKitViewManager.isPanelVisible()) {
        DoKitViewManager.detachToolPanel();
      }
      // 先记下全屏层是不是本来就在。栈顶更换时要靠它决定要不要重建。
      const hadPage = DoKitLayers.has(DoKitLayerName.PAGE);
      // 先卸掉不该出现的层，再挂上该出现的，避免新层插到即将卸掉的层下面
      if (!page) {
        DoKitLayers.detach(DoKitLayerName.PAGE);
      }
      if (page || !DoKitViewManager.isPanelVisible()) {
        DoKitLayers.detach(DoKitLayerName.PANEL);
      }
      if (page || !DoKitOverlayState.isIconVisible()) {
        DoKitLayers.detach(DoKitLayerName.BALL);
      }
      // 有全屏页只挂页面。没有页面时，面板开着才挂面板
      if (page) {
        DoKitLayers.ensure(DoKitLayerName.PAGE, PAGE_LAYER_BUILDER, false, false);
      } else if (DoKitViewManager.isPanelVisible()) {
        DoKitLayers.ensure(DoKitLayerName.PANEL, PANEL_LAYER_BUILDER, false, false);
      }
      // 没有全屏页且悬浮球可见时才挂球
      if (!page && DoKitOverlayState.isIconVisible()) {
        DoKitLayers.ensure(DoKitLayerName.BALL, BALL_LAYER_BUILDER, false, false);
      }
      // 栈顶换了但全屏层还在。版本不加的话界面不重建，打开 B 会看起来没反应。
      DoKitMainLayer.syncPageLayer(page, hadPage);
      // 球、面板、全屏页之外的浮窗，按浮窗表对齐
      DoKitMainLayer.syncFloatLayers();
    });
    DoKitMainLayer.publishModal();
    DoKitMainLayer.inSync = false;
  }

  /**
   * 全屏层还在、栈顶变了，就让这一层版本加一。
   * 关掉最后一页会把整层卸掉，所以关闭看得到；只压栈不会增减层，必须在这里补一次重建。
   */
  private static syncPageLayer(pageOpen: boolean, hadPage: boolean): void {
    if (!pageOpen) {
      DoKitMainLayer.lastPageKey = '';
      return;
    }
    const top = DoKitPageStack.peek();
    const pageKey = top === undefined ? '' : `${top.name}|${DoKitPageStack.getRevision()}`;
    if (hadPage && pageKey !== DoKitMainLayer.lastPageKey) {
      DoKitLayers.touch(DoKitLayerName.PAGE);
    }
    DoKitMainLayer.lastPageKey = pageKey;
  }

  /** 浮窗表里有的挂上，没有的从层表去掉。球、面板、全屏页不动。 */
  private static syncFloatLayers(): void {
    const names: string[] = [];
    const configs = DoKitViewManager.getViewConfigList();
    for (let i = 0; i < configs.length; i++) {
      const config = configs[i];
      if (config === undefined) {
        continue;
      }
      names.push(config.name);
      DoKitLayers.ensure(config.name, FLOAT_LAYER_BUILDER, config.abovePage, config.abovePanel);
    }
    DoKitLayers.retainFloats(names);
  }

  /** 全屏页或工具面板变了，才让 dokitModalTick 加一，驱动这两块重画。 */
  private static publishModal(): void {
    const panel = DoKitViewManager.isPanelVisible() ? '1' : '0';
    const page = DoKitPageStack.peek();
    const pagePart = page === undefined ? '' : `${page.name}|${page.isSystem ? '1' : '0'}|${DoKitPageStack.getRevision()}`;
    const modalKey = `${pagePart}|${panel}`;
    if (modalKey === DoKitMainLayer.lastModalKey) {
      return;
    }
    DoKitMainLayer.lastModalKey = modalKey;
    const modal = (AppStorage.get<number>(DOKIT_MODAL_TICK) ?? 0) + 1;
    AppStorage.setOrCreate(DOKIT_MODAL_TICK, modal);
  }

  /** 面板、浮窗、页面栈、悬浮球变化时，重新对齐层。 */
  private static bindHandlers(): void {
    // 工具面板打开或关闭
    DoKitViewManager.setToolPanelChangeHandler((_visible: boolean) => {
      DoKitMainLayer.syncFrame();
    });
    // 浮窗挂上、卸下，或同名浮窗更新了摆放说明
    DoKitViewManager.setWindowRefreshHandler(() => {
      DoKitMainLayer.syncFrame();
    });
    // 全屏栈清栈、压栈或弹出
    DoKitPageStack.setChangeHandler(() => {
      DoKitMainLayer.syncFrame();
    });
    // 系统全屏页打开
    SystemFragmentRegistry.setOpenHandler((_name: string, _system: boolean) => {
      DoKitMainLayer.syncFrame();
    });
    // 系统全屏页关闭
    SystemFragmentRegistry.setCloseHandler(() => {
      DoKitMainLayer.syncFrame();
    });
    // 悬浮球显示或隐藏
    DoKitOverlayState.setIconListener(() => {
      DoKitMainLayer.syncFrame();
    });
  }

  /** 卸下 bindHandlers 注册的回调。 */
  private static unbindHandlers(): void {
    DoKitViewManager.setToolPanelChangeHandler(null);
    DoKitViewManager.setWindowRefreshHandler(null);
    DoKitPageStack.setChangeHandler(null);
    SystemFragmentRegistry.setOpenHandler(null);
    SystemFragmentRegistry.setCloseHandler(null);
    DoKitOverlayState.setIconListener(null);
  }
}


/** 浮窗还没有注册画法时用的空内容。 */
@Builder
function emptyOverlayFloat(_params: DoKitParams, _close: CloseHandler) {
  Row()
    .width(0)
    .height(0)
}

const EMPTY_OVERLAY_FLOAT: CustomViewBuilder = wrapBuilder(emptyOverlayFloat);

/** 层记录没有画法时用的空节点，不接收点击。 */
@Builder
function renderEmptyLayer(_name: string, _stageW: number, _stageH: number, _top: number, _bottom: number) {
  Row()
    .width(0)
    .height(0)
    .hitTestBehavior(HitTestMode.None)
}

const EMPTY_LAYER_BUILDER: DoKitLayerBuilder = wrapBuilder(renderEmptyLayer);

/** 悬浮球这一层。 */
@Builder
function renderBallLayer(_name: string, stageW: number, stageH: number, top: number, bottom: number) {
  DoKitOverlayBall({
    stageW: stageW,
    stageH: stageH,
    topInset: top,
    bottomInset: bottom
  })
}

/** 工具面板这一层。 */
@Builder
function renderPanelLayer(_name: string, _stageW: number, _stageH: number, _top: number, _bottom: number) {
  DoKitLayerHost({ role: 'panel' })
}

/** 全屏页这一层。 */
@Builder
function renderPageLayer(_name: string, _stageW: number, _stageH: number, _top: number, _bottom: number) {
  DoKitLayerHost({ role: 'page' })
}

/** 一条浮窗。画法按名字从注册表里取。 */
@Builder
function renderFloatLayer(name: string, stageW: number, stageH: number, top: number, bottom: number) {
  DoKitOverlayFloat({
    name: name,
    contentBuilder: floatBuilderOf(name),
    stageW: stageW,
    stageH: stageH,
    topInset: top,
    bottomInset: bottom
  })
}

/** 按浮窗名字取出已注册的画法。没有则返回空内容。 */
function floatBuilderOf(name: string): CustomViewBuilder {
  const found = CustomViewRegistry.getBuilder(name);
  if (found !== undefined) {
    return found;
  }
  return EMPTY_OVERLAY_FLOAT;
}

const BALL_LAYER_BUILDER: DoKitLayerBuilder = wrapBuilder(renderBallLayer);
const PANEL_LAYER_BUILDER: DoKitLayerBuilder = wrapBuilder(renderPanelLayer);
const PAGE_LAYER_BUILDER: DoKitLayerBuilder = wrapBuilder(renderPageLayer);
const FLOAT_LAYER_BUILDER: DoKitLayerBuilder = wrapBuilder(renderFloatLayer);

/** OverlayManager 上的根节点。透明命中写在这里，空白点击才能落到业务页。 */
@Builder
function buildDoKitOverlayHost() {
  // 命中模式必须写在 WrappedBuilder 的根节点上。写在内部 Stack 时，
  // 自定义组件自己仍是 Default，整屏挡住页面。
  DoKitOverlayHost()
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
}

@Component
struct DoKitLayerItem {
  @Prop layerName: string = '';
  @Prop stageW: number = 0;
  @Prop stageH: number = 0;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  layerBuilder: DoKitLayerBuilder = EMPTY_LAYER_BUILDER;

  /** 用这条层自己的画法画出内容。 */
  build() {
    this.layerBuilder.builder(this.layerName, this.stageW, this.stageH, this.topInset, this.bottomInset)
  }
}

@Component
struct DoKitOverlayHost {
  @StorageLink(DOKIT_OVERLAY_TICK) @Watch('reload') tick: number = 0;
  @StorageProp(DOKIT_TOP_RECT_HEIGHT) topRectHeightPx: number = 0;
  @StorageProp(DOKIT_NAV_INSET_PX) navInsetPx: number = 0;
  /** 按叠放序号从小到大。后画的盖住先画的。 */
  @State private layers: DoKitLayerSnap[] = [];
  @State private stageW: number = 0;
  @State private stageH: number = 0;
  @State private needBack: boolean = false;
  private backFocused: boolean = false;

  /** 出现时按当前层表画一次。 */
  aboutToAppear(): void {
    this.reload();
  }

  /** 层表变了就按序号重画。刚出现页面或面板时要一次焦点，用来接返回键。 */
  reload(): void {
    if (this.tick < 0) {
      return;
    }
    this.layers = DoKitLayers.snapshot();
    const need = DoKitLayers.has(DoKitLayerName.PAGE) || DoKitLayers.has(DoKitLayerName.PANEL);
    if (need && !this.backFocused) {
      try {
        focusControl.requestFocus(ViewCheckTree.FLOATING_ID);
      } catch (_e) {
      }
      this.backFocused = true;
    } else if (!need) {
      this.backFocused = false;
    }
    this.needBack = need;
  }

  /** 状态栏高度，单位 vp。 */
  private topInsetVp(): number {
    if (this.topRectHeightPx <= 0) {
      return 0;
    }
    return px2vp(this.topRectHeightPx);
  }

  /** 导航栏高度，单位 vp。 */
  private bottomInsetVp(): number {
    if (this.navInsetPx <= 0) {
      return 0;
    }
    return px2vp(this.navInsetPx);
  }

  /** 包一层铺满的透明容器，这一层的空白处不挡住业务页。 */
  @Builder
  private layerNode(item: DoKitLayerSnap) {
    Stack() {
      DoKitLayerItem({
        layerName: item.name,
        stageW: this.stageW,
        stageH: this.stageH,
        topInset: this.topInsetVp(),
        bottomInset: this.bottomInsetVp(),
        layerBuilder: item.builder ?? EMPTY_LAYER_BUILDER
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /**
   * 按序号从下往上画。身份不含序号：只换叠放时不拆组件，性能曲线的点才能留住。
   * 版本仍在身份里，全屏栈换页会重建。
   */
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.layers, (item: DoKitLayerSnap) => {
        this.layerNode(item)
      }, (item: DoKitLayerSnap) => `${item.name}#${item.revision}`)
    }
    .id(ViewCheckTree.FLOATING_ID)
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.Transparent)
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
  @Prop @Watch('onFrameChange') stageW: number = 0;
  @Prop @Watch('onFrameChange') stageH: number = 0;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State private x: number = 0;
  @State private y: number = 0;
  private placed: boolean = false;
  private land: boolean = false;
  private downX: number = 0;
  private downY: number = 0;
  private originX: number = 0;
  private originY: number = 0;
  private downTime: number = 0;
  private dragMoved: boolean = false;

  /** 出现时按窗口大小摆一次位置。 */
  aboutToAppear(): void {
    this.onFrameChange();
  }

  /** 尺寸就绪后恢复位置。横竖屏切换时先存当前方向，再读另一个方向。 */
  private onFrameChange(): void {
    if (this.stageW <= 1 || this.stageH <= 1) {
      return;
    }
    const land = this.stageW > this.stageH;
    if (!this.placed) {
      this.land = land;
      if (!this.restore(land)) {
        this.placeDefault();
      }
      this.placed = true;
      return;
    }
    if (land === this.land) {
      return;
    }
    this.write(this.land);
    this.land = land;
    if (!this.restore(land)) {
      this.placeDefault();
    }
  }

  /** 读出这个方向上次放下的位置。没有存过则返回 false。 */
  private restore(land: boolean): boolean {
    const savedX = AppStorage.get<number>(land ? DOKIT_BALL_LAND_X : DOKIT_BALL_X);
    const savedY = AppStorage.get<number>(land ? DOKIT_BALL_LAND_Y : DOKIT_BALL_Y);
    if (savedX === undefined || savedY === undefined) {
      return false;
    }
    this.x = savedX;
    this.y = savedY;
    return true;
  }

  /** 把当前位置记到这个方向。 */
  private write(land: boolean): void {
    if (land) {
      AppStorage.setOrCreate(DOKIT_BALL_LAND_X, this.x);
      AppStorage.setOrCreate(DOKIT_BALL_LAND_Y, this.y);
      return;
    }
    AppStorage.setOrCreate(DOKIT_BALL_X, this.x);
    AppStorage.setOrCreate(DOKIT_BALL_Y, this.y);
  }

  /** 按当前横竖屏保存位置。 */
  private save(): void {
    this.write(this.land);
  }

  /** 把数值限制在最小值和最大值之间。 */
  private clamp(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max);
  }

  /** 球的最上沿，停在状态栏下面。 */
  private minY(): number {
    return Math.max(0, this.topInset);
  }

  /** 球的最右沿，给球本身留出宽度。 */
  private maxX(): number {
    return Math.max(0, this.stageW - this.ballSize);
  }

  /** 球的最下沿，避开导航栏。 */
  private maxY(): number {
    return Math.max(this.minY(), this.stageH - this.ballSize - Math.max(0, this.bottomInset));
  }

  /** 没有存过位置时，放在右下角并记住。 */
  private placeDefault(): void {
    if (this.stageW <= 1 || this.stageH <= 1) {
      return;
    }
    this.x = Math.max(0, this.maxX() - this.edgeMargin);
    this.y = Math.max(this.minY(), this.maxY() - this.edgeMargin);
    this.placed = true;
    this.save();
  }

  /** 取出这次触摸的触点。 */
  private pointOf(event: TouchEvent): TouchObject | undefined {
    if (event.touches.length > 0) {
      return event.touches[0];
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0];
    }
    return undefined;
  }

  /** 移动超过 4vp 才算拖。松手后贴到左右边缘。短按打开工具面板。 */
  private onBallTouch(event: TouchEvent): void {
    this.onFrameChange();
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
      const dx = point.displayX - this.downX;
      const dy = point.displayY - this.downY;
      if (!this.dragMoved) {
        if (Math.abs(dx) <= this.dragThreshold && Math.abs(dy) <= this.dragThreshold) {
          return;
        }
        this.dragMoved = true;
      }
      this.x = this.clamp(this.originX + dx, 0, this.maxX());
      this.y = this.clamp(this.originY + dy, this.minY(), this.maxY());
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
        this.save();
      });
    }
  }

  /** 悬浮球图片。只有图片这块接收点击。 */
  build() {
    Image($r('app.media.dk_doraemon'))
      .width(this.ballSize)
      .height(this.ballSize)
      .objectFit(ImageFit.Contain)
      .position({ x: this.x, y: this.y })
      .hitTestBehavior(HitTestMode.Default)
      .monopolizeEvents(true)
      .onAppear(() => {
        this.onFrameChange();
      })
      .onTouch((event: TouchEvent) => {
        this.onBallTouch(event);
      })
  }
}

@Component
struct DoKitOverlayFloat {
  private readonly dragThreshold: number = 4;
  @Prop name: string = '';
  contentBuilder: CustomViewBuilder = EMPTY_OVERLAY_FLOAT;
  @Prop @Watch('onFrameChange') stageW: number = 0;
  @Prop @Watch('onFrameChange') stageH: number = 0;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State private x: number = 20;
  @State private y: number = 200;
  @State private contentW: number = 0;
  @State private contentH: number = 0;
  private placed: boolean = false;
  private land: boolean = false;
  private originX: number = 0;
  private originY: number = 0;
  private boundParams: DoKitParams = {};
  /** 关闭这条浮窗。 */
  private readonly onClose: CloseHandler = (): void => {
    DoKitViewManager.detachView(this.name);
  };

  /** 记下打开时传入的参数，并按窗口大小恢复位置。 */
  aboutToAppear(): void {
    this.boundParams = this.paramsOf();
    this.onFrameChange();
  }

  /** 尺寸就绪后读出位置。横竖屏切换时先存当前方向，再读另一个方向。 */
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

  /** 读出这个方向存过的位置。 */
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

  /** 把当前位置写回这个方向。 */
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

  /** 把数值限制在最小值和最大值之间。 */
  private clamp(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max);
  }

  /** 浮窗的最上沿，停在状态栏下面。 */
  private minY(): number {
    return Math.max(0, this.topInset);
  }

  /** 浮窗的最右沿，按内容宽度留空。 */
  private maxX(): number {
    return Math.max(0, this.stageW - this.contentW);
  }

  /** 浮窗的最下沿，避开导航栏。 */
  private maxY(): number {
    return Math.max(this.minY(), this.stageH - this.contentH - Math.max(0, this.bottomInset));
  }

  /** 取出打开浮窗时传入的参数。 */
  private paramsOf(): DoKitParams {
    const config = DoKitViewManager.getViewConfigByName(this.name);
    if (config === undefined || config.params === undefined) {
      return {};
    }
    return config.params;
  }

  /** 热区等于量到的内容宽高。还没量到时是 0，不挡页面。 */
  private hitRegion(): Rectangle {
    const region: Rectangle = {
      x: 0,
      y: 0,
      width: this.contentW,
      height: this.contentH
    };
    return region;
  }

  /** 是否铺满窗口，空白点击穿透。 */
  private fills(): boolean {
    const config = DoKitViewManager.getViewConfigByName(this.name);
    return config !== undefined && config.passThrough;
  }

  /** 卡片浮窗且允许拖动。铺满的不拖。 */
  private dragEnabled(): boolean {
    const config = DoKitViewManager.getViewConfigByName(this.name);
    if (config === undefined) {
      return true;
    }
    return config.draggable && !config.passThrough;
  }

  /** 卡片内容。量到宽高后，把位置收进屏幕里。 */
  @Builder
  private CardContent() {
    Column() {
      this.contentBuilder.builder(this.boundParams, this.onClose)
    }
    .onAreaChange((_oldValue: Area, area: Area) => {
      const width = Number(area.width);
      const height = Number(area.height);
      if (width <= 1 || height <= 1) {
        return;
      }
      if (width === this.contentW && height === this.contentH) {
        return;
      }
      this.contentW = width;
      this.contentH = height;
      this.x = this.clamp(this.x, 0, this.maxX());
      this.y = this.clamp(this.y, this.minY(), this.maxY());
    })
  }

  /** 铺满窗口。空白处不吃点击，点击交给浮窗内容自己。 */
  @Builder
  private FillFloat() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.contentBuilder.builder(this.boundParams, this.onClose)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /** 可拖的小卡片。热区只包住内容，松手后记住位置。 */
  @Builder
  private CardFloat() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.CardContent()
    }
    .position({ x: this.x, y: this.y })
    .hitTestBehavior(HitTestMode.Default)
    .monopolizeEvents(true)
    .responseRegion(this.hitRegion())
    .parallelGesture(
      PanGesture({ direction: PanDirection.All, fingers: 1, distance: this.dragThreshold })
        .onActionStart(() => {
          this.originX = this.x;
          this.originY = this.y;
        })
        .onActionUpdate((event?: GestureEvent) => {
          if (event === undefined) {
            return;
          }
          this.x = this.clamp(this.originX + event.offsetX, 0, this.maxX());
          this.y = this.clamp(this.originY + event.offsetY, this.minY(), this.maxY());
        })
        .onActionEnd(() => {
          this.writeSaved(this.land);
        })
    )
  }

  /** 不拖的小卡片。热区同样只包住内容。 */
  @Builder
  private PinnedCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.CardContent()
    }
    .position({ x: this.x, y: this.y })
    .hitTestBehavior(HitTestMode.Default)
    .monopolizeEvents(true)
    .responseRegion(this.hitRegion())
  }

  /** 按浮窗说明选择铺满、可拖卡片或不拖卡片。 */
  build() {
    if (this.fills()) {
      this.FillFloat()
    } else if (this.dragEnabled()) {
      this.CardFloat()
    } else {
      this.PinnedCard()
    }
  }
}
