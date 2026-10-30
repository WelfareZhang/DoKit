import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { DokitThirdLibInfo } from './aop/DokitThirdLibInfo';
import { DoKitCallBack } from './DoKitCallBack';
import { DoKitReal } from './DoKitReal';
import { GlobalConfig } from './config/GlobalConfig';
import { DoKitConstants } from './constant/DoKitConstants';
import { WebDoorCallback } from './kit/webdoor/WebDoorCallback';
import { AbstractKit } from './kit/AbstractKit';
import { DoKitManager } from './core/DoKitManager';
import { DoKitViewManager, ViewConfig } from './core/DoKitViewManager';
import { DoKitBundle, SystemFragmentBuilder } from './core/FragmentRenderer';
import { DoKitViewLaunchMode } from './core/DoKitIntent';
import { SystemFragmentRegistry } from './core/SystemFragmentRigistry';
import { CustomFragmentRegistry } from './core/CustomFragmentRegistry';
import { DoKitLauncher } from './core/DoKitLauncher';
import { DoKitOverlayState } from './model/DoKitOverlayState';
import { CustomViewBuilder, CustomViewRegistry, DoKitParams } from './core/CustomViewRegistry';
import { DoKitMainOverlay } from './overlay/DoKitMainOverlay';
import { DoKitBack } from './overlay/DoKitBack';

export { DoKitConstants } from './constant/DoKitConstants';

export class DoKitBuilder {
  private context: common.UIAbilityContext;
  private mProductId: string = '';
  private mDebugMode: boolean = true;
  private mCustomKits: Map<string, AbstractKit[]> = new Map();
  private mCustomKitList: AbstractKit[] = [];
  private mDisableUpload: boolean = false;
  private mAlwaysShowMainIcon: boolean = true;
  private mFileManagerHttpPort: number = 8089;
  private mMcWsPort: number = 4444;
  private mDatabasePass: Map<string, string> = new Map();
  private mCallBack: DoKitCallBack | null = null;
  private mWebDoorCallback: WebDoorCallback | null = null;
  private mH5BaseUrl: string = '';
  private mThirdLibInfos: Map<string, string> = new Map();
  private mThirdLibRawFile: string = '';
  private mWindowStage: window.WindowStage | null = null;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  productId(id: string): DoKitBuilder {
    this.mProductId = id;
    return this;
  }

  debug(isDebug: boolean): DoKitBuilder {
    this.mDebugMode = isDebug;
    return this;
  }

  /** 绑定 WindowStage，build 时 attach SubWindow（需在 loadContent 后调用 DoKit.showOverlay） */
  windowStage(stage: window.WindowStage): DoKitBuilder {
    this.mWindowStage = stage;
    return this;
  }

  customKits(kits: Map<string, AbstractKit[]>): DoKitBuilder {
    this.mCustomKits = kits;
    return this;
  }

  customKitList(kits: AbstractKit[]): DoKitBuilder {
    this.mCustomKitList = kits;
    return this;
  }

  disableUpload(): DoKitBuilder {
    this.mDisableUpload = true;
    return this;
  }

  alwaysShowMainIcon(alwaysShow: boolean): DoKitBuilder {
    this.mAlwaysShowMainIcon = alwaysShow;
    return this;
  }

  fileManagerHttpPort(port: number): DoKitBuilder {
    this.mFileManagerHttpPort = port;
    return this;
  }

  mcWSPort(port: number): DoKitBuilder {
    this.mMcWsPort = port;
    return this;
  }

  databasePass(map: Map<string, string>): DoKitBuilder {
    this.mDatabasePass = map;
    return this;
  }

  callBack(callback: DoKitCallBack): DoKitBuilder {
    this.mCallBack = callback;
    return this;
  }

  webDoorCallback(callback: WebDoorCallback): DoKitBuilder {
    this.mWebDoorCallback = callback;
    return this;
  }

  h5BaseUrl(url: string): DoKitBuilder {
    this.mH5BaseUrl = url;
    return this;
  }

  thirdLibInfos(infos: Map<string, string>): DoKitBuilder {
    this.mThirdLibInfos = infos;
    return this;
  }

  thirdLibRawFile(fileName: string): DoKitBuilder {
    this.mThirdLibRawFile = fileName;
    return this;
  }

  build(): void {
    GlobalConfig.productId = this.mProductId;
    GlobalConfig.disableUpload = this.mDisableUpload;
    GlobalConfig.alwaysShowMainIcon = this.mAlwaysShowMainIcon;
    GlobalConfig.fileManagerHttpPort = this.mFileManagerHttpPort;
    GlobalConfig.mcWsPort = this.mMcWsPort;
    GlobalConfig.databasePass = this.mDatabasePass;
    GlobalConfig.debugMode = this.mDebugMode;
    GlobalConfig.h5BaseUrl = this.mH5BaseUrl;
    GlobalConfig.webDoorCallback = this.mWebDoorCallback;
    if (this.mThirdLibInfos.size > 0) {
      DokitThirdLibInfo.merge(this.mThirdLibInfos);
    }
    if (this.mThirdLibRawFile.length > 0) {
      DokitThirdLibInfo.loadFromRawFile(this.context, this.mThirdLibRawFile);
    }
    DoKitManager.setCallBack(this.mCallBack);
    DoKit.installInternal(this.context, this.mDebugMode, this.mCustomKits, this.mCustomKitList);
    if (this.mDebugMode && this.mWindowStage !== null) {
      DoKitMainOverlay.attach(this.mWindowStage);
    }
  }
}

/**
 * DoKit 鸿蒙版入口，对标 Android DoKit / DoKit.Builder
 */
export class DoKit {
  static Builder(context: common.UIAbilityContext): DoKitBuilder {
    return new DoKitBuilder(context);
  }

  /** @deprecated 请使用 DoKit.Builder(context).windowStage(stage).build() + DoKit.showOverlay() */
  static install(context: common.UIAbilityContext, _windowStage?: window.WindowStage): void {
    DoKit.installInternal(context, true, new Map(), []);
    if (_windowStage !== undefined) {
      DoKitMainOverlay.attach(_windowStage);
    }
  }

  static installInternal(
    context: common.UIAbilityContext,
    debugMode: boolean,
    customKits: Map<string, AbstractKit[]>,
    customKitList: AbstractKit[]
  ): void {
    if (!debugMode) {
      return;
    }
    DoKitReal.install(context, customKits, customKitList);
    DoKitOverlayState.init(GlobalConfig.alwaysShowMainIcon);
  }

  /** 主窗 loadContent 成功后，把 DoKit 挂到主窗口 OverlayManager */
  static showOverlay(): void {
    if (!GlobalConfig.debugMode) {
      return;
    }
    DoKitMainOverlay.show();
  }

  /** Ability 销毁时卸下主窗口浮层 */
  static detach(): void {
    DoKitMainOverlay.detach();
  }

  /**
   * 业务页 onBackPress 里调用。
   * API 12 的浮层接不到系统返回手势，返回 true 表示 DoKit 已消费。
   */
  static consumeBackPress(): boolean {
    return DoKitBack.consume();
  }

  static registerCustomKits(groupName: string, kits: AbstractKit[]) {
    DoKitManager.addCustomKits(groupName, kits);
  }

  /** 启动类名悬浮（旧通道）；业务扩展请优先 launchFloatingView */
  static launchFloating(
    targetName: string,
    mode: DoKitViewLaunchMode = DoKitViewLaunchMode.SINGLE_INSTANCE,
    bundle?: DoKitBundle
  ): void {
    DoKitLauncher.launchFloating(targetName, mode, bundle);
  }

  /** 自定义浮窗：同名只留一个，挂进主窗口浮层，和悬浮球共存 */
  static launchFloatingView(
    targetName: string,
    builder: CustomViewBuilder,
    params?: DoKitParams
  ): void {
    CustomViewRegistry.registerBuilder(targetName, builder);
    DoKitViewManager.detachView(targetName);
    const config = new ViewConfig(targetName, true, params, { x: 20, y: 200 }, () => {
      DoKitViewManager.detachView(targetName);
    });
    DoKitViewManager.attachView(targetName, config);
  }

  static removeFloatingView(targetName: string): void {
    DoKitViewManager.detachView(targetName);
  }

  static removeFloating(targetClass: string): void {
    DoKitLauncher.removeFloating(targetClass);
  }

  /** 打开全屏工具根页（清栈） */
  static launchFullScreen(
    targetClass: string,
    bundle?: DoKitBundle,
    isSystemFragment: boolean = false
  ): void {
    DoKitLauncher.launchFullScreen(targetClass, bundle, isSystemFragment);
  }

  /** 全屏内打开下级页（压栈，支持 A→B→回 A） */
  static pushFullScreen(
    targetClass: string,
    bundle?: DoKitBundle,
    isSystemFragment: boolean = false
  ): void {
    DoKitLauncher.pushFullScreen(targetClass, bundle, isSystemFragment);
  }

  static registerSystemFragment(fragmentClass: string, builder: SystemFragmentBuilder): void {
    SystemFragmentRegistry.registerSystemFragment(fragmentClass, builder);
  }

  /** 注册宿主自定义全屏页 Builder */
  static registerCustomFragment(fragmentClass: string, builder: SystemFragmentBuilder): void {
    CustomFragmentRegistry.register(fragmentClass, builder);
  }

  static closeFullScreen(): void {
    DoKitLauncher.finishFullScreen();
  }

  static popFullScreen(): void {
    DoKitLauncher.popFullScreen();
  }

  static show(): void {
    DoKitViewManager.attachMainIcon();
  }

  static hide(): void {
    DoKitViewManager.detachMainIcon();
  }

  static showToolPanel(): void {
    DoKitViewManager.attachToolPanel();
  }

  static get isMainIconShow(): boolean {
    return DoKitOverlayState.isIconVisible();
  }

  static isInstalled(): boolean {
    return DoKitReal.isInit;
  }
}
