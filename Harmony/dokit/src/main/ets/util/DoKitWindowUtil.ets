import { window } from '@kit.ArkUI';

/** 导航条高度，单位 px。主窗口浮层和工具底栏都读这一份。 */
export const DOKIT_NAV_INSET_PX: string = 'dokitNavInsetPx';

/** 状态栏高度，单位 px。避免和业务自己的 topRectHeight 撞名。 */
export const DOKIT_TOP_RECT_HEIGHT: string = 'dokitTopRectHeight';

/** 主窗口。避免和业务自己的 windowStage 撞名。 */
export const DOKIT_WINDOW_STAGE: string = 'dokitWindowStage';

/** 全屏层刷新记号。面板和全屏页监听它重画。 */
export const DOKIT_MODAL_TICK: string = 'dokitModalTick';

/** 浮层列表刷新记号。顺序或成员变了才加一。 */
export const DOKIT_OVERLAY_TICK: string = 'dokitOverlayTick';

class DoKitWindowBinding {
  static mainWin: window.Window | null = null;
  static onSystem: ((data: window.AvoidAreaOptions) => void) | null = null;
  static onNav: ((data: window.AvoidAreaOptions) => void) | null = null;
}

export function bindWindowStageToAppStorage(windowStage: window.WindowStage): void {
  unbindWindowAvoidArea();
  AppStorage.setOrCreate(DOKIT_WINDOW_STAGE, windowStage);
  try {
    const mainWin = windowStage.getMainWindowSync();
    DoKitWindowBinding.mainWin = mainWin;
    const avoidArea = mainWin.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    AppStorage.setOrCreate(DOKIT_TOP_RECT_HEIGHT, avoidArea.topRect.height);
    const nav = mainWin.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    AppStorage.setOrCreate(DOKIT_NAV_INSET_PX, nav.bottomRect.height);
    DoKitWindowBinding.onSystem = (data: window.AvoidAreaOptions): void => {
      if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
        AppStorage.setOrCreate(DOKIT_TOP_RECT_HEIGHT, data.area.topRect.height);
      }
    };
    DoKitWindowBinding.onNav = (data: window.AvoidAreaOptions): void => {
      if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
        AppStorage.setOrCreate(DOKIT_NAV_INSET_PX, data.area.bottomRect.height);
      }
    };
    mainWin.on('avoidAreaChange', DoKitWindowBinding.onSystem);
    mainWin.on('avoidAreaChange', DoKitWindowBinding.onNav);
  } catch (_e) {
  }
}

export function unbindWindowAvoidArea(): void {
  const mainWin = DoKitWindowBinding.mainWin;
  if (mainWin !== null) {
    try {
      if (DoKitWindowBinding.onSystem !== null) {
        mainWin.off('avoidAreaChange', DoKitWindowBinding.onSystem);
      }
      if (DoKitWindowBinding.onNav !== null) {
        mainWin.off('avoidAreaChange', DoKitWindowBinding.onNav);
      }
    } catch (_e) {
    }
  }
  DoKitWindowBinding.onSystem = null;
  DoKitWindowBinding.onNav = null;
  DoKitWindowBinding.mainWin = null;
}
