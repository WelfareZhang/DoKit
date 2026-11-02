import { DoKitOverlayState } from '../model/DoKitOverlayState';
import { CustomViewBuilder, CustomViewRegistry, DoKitParams } from './CustomViewRegistry';
import { CustomDoKitViewRenderer, DoKitIntent, DoKitViewCloseHandler } from './DoKitIntent';
import { Callback } from '@kit.BasicServicesKit';

/**
 * 浮窗怎么摆。不传则是可拖的小卡片，盖住全屏页和工具面板。
 */
export class DoKitFloatOptions {
  draggable: boolean = true;
  abovePage: boolean = true;
  abovePanel: boolean = true;
  /** 铺满且不位移，空白处不吃点击。 */
  passThrough: boolean = false;

  /** 铺满、不拖，留在全屏页和工具面板下面。 */
  static underLayer(): DoKitFloatOptions {
    const options = new DoKitFloatOptions();
    options.draggable = false;
    options.abovePage = false;
    options.abovePanel = false;
    options.passThrough = true;
    return options;
  }

  /** 性能曲线：不拖，盖住全屏页，留在工具面板下面。 */
  static performance(): DoKitFloatOptions {
    const options = new DoKitFloatOptions();
    options.draggable = false;
    options.abovePage = true;
    options.abovePanel = false;
    options.passThrough = true;
    return options;
  }
}


/**
 * 视图配置信息
 */
export class ViewConfig {
  name: string = "";
  params?: DoKitParams;
  closeHandler?: Callback<void>;
  isFloat: boolean;
  viewPoint: Position;
  /** 竖屏位置，对标 Android LastDoKitViewPosInfo.portraitPoint */
  portraitX: number = 0;
  portraitY: number = 0;
  /** 横屏位置，对标 Android LastDoKitViewPosInfo.landscapePoint */
  landscapeX: number = 0;
  landscapeY: number = 0;
  /** 能拖。卡片浮窗默认能拖。 */
  draggable: boolean = true;
  /** 盖住全屏页。 */
  abovePage: boolean = true;
  /** 盖住工具面板。 */
  abovePanel: boolean = true;
  /** 铺满，空白点击穿透。 */
  passThrough: boolean = false;

  constructor(
    name: string,
    isFloat: boolean,
    params?: DoKitParams,
    viewPoint?: Position,
    closeHandler?: Callback<void>
  ) {
    this.name = name;
    this.isFloat = isFloat;
    this.params = params;
    this.viewPoint = viewPoint ?? { x: 0, y: 0 };
    this.closeHandler = closeHandler;
    const x = ViewConfig.readLen(this.viewPoint.x ?? 0);
    const y = ViewConfig.readLen(this.viewPoint.y ?? 0);
    this.portraitX = x;
    this.portraitY = y;
    this.landscapeX = x;
    this.landscapeY = y;
  }

  static readLen(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    const parsed = Number(value);
    if (Number.isNaN(parsed)) {
      return 0;
    }
    return parsed;
  }

  applyOptions(options?: DoKitFloatOptions): void {
    if (options === undefined) {
      return;
    }
    this.draggable = options.draggable;
    this.abovePage = options.abovePage;
    this.abovePanel = options.abovePanel;
    this.passThrough = options.passThrough;
  }
}

/**
 * 悬浮窗管理门面，对标 Android kit/core/DoKitViewManager
 */
export class DoKitViewManager {
  private static toolPanelChangeHandler: ((visible: boolean) => void) | null = null;
  private static floatingIntent: DoKitIntent | null = null;
  private static floatingAttachHandler: ((intent: DoKitIntent) => void) | null = null;
  private static floatingDetachHandler: (() => void) | null = null;
  private static windowRefreshHandler: (() => void) | null = null;
  private static panelVisible: boolean = false;
  private static viewMap: Map<string, ViewConfig> = new Map()

  static setToolPanelChangeHandler(handler: ((visible: boolean) => void) | null): void {
    DoKitViewManager.toolPanelChangeHandler = handler;
  }

  static setFloatingAttachHandler(handler: ((intent: DoKitIntent) => void) | null): void {
    DoKitViewManager.floatingAttachHandler = handler;
  }

  static setFloatingDetachHandler(handler: (() => void) | null): void {
    DoKitViewManager.floatingDetachHandler = handler;
  }

  static setWindowRefreshHandler(handler: (() => void) | null) {
    DoKitViewManager.windowRefreshHandler = handler;
  }

  static refreshWindow() {
    if (DoKitViewManager.windowRefreshHandler != null) {
      DoKitViewManager.windowRefreshHandler()
    }
  }

  static attachMainIcon(): void {
    DoKitOverlayState.setIconVisible(true);
  }

  static detachMainIcon(): void {
    DoKitOverlayState.setIconVisible(false);
  }

  static isPanelVisible(): boolean {
    return DoKitViewManager.panelVisible;
  }

  static getViewConfigByName(name: string): ViewConfig | undefined {
    return DoKitViewManager.viewMap.get(name);
  }

  static attachToolPanel(): void {
    DoKitViewManager.panelVisible = true;
    DoKitOverlayState.requestOpenPanel();
    if (DoKitViewManager.toolPanelChangeHandler !== null) {
      DoKitViewManager.toolPanelChangeHandler(true);
    }
  }

  static detachToolPanel(): void {
    if (!DoKitViewManager.panelVisible) {
      return;
    }
    DoKitViewManager.panelVisible = false;
    DoKitOverlayState.clearPanelOpenRequest();
    if (DoKitViewManager.toolPanelChangeHandler !== null) {
      DoKitViewManager.toolPanelChangeHandler(false);
    }
  }

  static attachView(name: string, viewConfig: ViewConfig) {
    DoKitViewManager.viewMap.set(name, viewConfig)
    DoKitViewManager.refreshWindow();
  }

  /**
   * 挂上浮窗。同名已经在时只更新画法和摆放，不先卸再挂。
   * 对标 Android 同一个 tag 已存在就只更新位置。
   */
  static launchFloatingView(
    targetName: string,
    builder: CustomViewBuilder,
    params?: DoKitParams,
    options?: DoKitFloatOptions
  ): void {
    CustomViewRegistry.registerBuilder(targetName, builder);
    const existing = DoKitViewManager.viewMap.get(targetName);
    if (existing !== undefined) {
      existing.params = params;
      existing.applyOptions(options);
      DoKitViewManager.refreshWindow();
      return;
    }
    const config = new ViewConfig(targetName, true, params, { x: 20, y: 200 }, () => {
      DoKitViewManager.detachView(targetName);
    });
    config.applyOptions(options);
    DoKitViewManager.attachView(targetName, config);
  }

  static detachView(name: string) {
    DoKitViewManager.viewMap.delete(name);
    DoKitViewManager.refreshWindow();
  }

  static getViewConfig(): Map<string, ViewConfig> {
    return DoKitViewManager.viewMap;
  }

  static getViewConfigList(): ViewConfig[] {
    const list: ViewConfig[] = [];

    DoKitViewManager.viewMap.forEach((config, key) => {
      list.push(config);
    });
    return list;
  }

  static updateViewPoint(name: string, x: number, y: number): void {
    const config = DoKitViewManager.viewMap.get(name);
    if (config === undefined) {
      return;
    }
    config.viewPoint = { x: x, y: y };
  }

  /** 对标 Android DoKitViewManager.attach(DoKitIntent)。已注册 Builder 的类名会画进主窗口浮层。 */
  static attach(doKitIntent: DoKitIntent): void {
    DoKitViewManager.floatingIntent = doKitIntent;
    DoKitViewManager.detachToolPanel();
    if (CustomViewRegistry.getBuilder(doKitIntent.targetClass) !== undefined) {
      const name = doKitIntent.tag;
      if (DoKitViewManager.viewMap.get(name) === undefined) {
        const config = new ViewConfig(name, true, undefined, { x: 20, y: 200 }, () => {
          DoKitViewManager.detachView(name);
        });
        DoKitViewManager.attachView(name, config);
      } else {
        DoKitViewManager.refreshWindow();
      }
    }
    if (DoKitViewManager.floatingAttachHandler !== null) {
      DoKitViewManager.floatingAttachHandler(doKitIntent);
    }
  }

  /** 对标 Android DoKitViewManager.detach(tag) */
  static detach(tag: string): void {
    const matched = DoKitViewManager.floatingIntent !== null && DoKitViewManager.floatingIntent.tag === tag;
    DoKitViewManager.detachView(tag);
    if (!matched) {
      return;
    }
    DoKitViewManager.floatingIntent = null;
    if (DoKitViewManager.floatingDetachHandler !== null) {
      DoKitViewManager.floatingDetachHandler();
    }
  }

  static getFloatingIntent(): DoKitIntent | null {
    return DoKitViewManager.floatingIntent;
  }

  static hasFloating(): boolean {
    return DoKitViewManager.floatingIntent !== null;
  }
}

export { DoKitViewCloseHandler as CustomKitCloseHandler };

export type { CustomDoKitViewRenderer as CustomKitPageRenderer };
