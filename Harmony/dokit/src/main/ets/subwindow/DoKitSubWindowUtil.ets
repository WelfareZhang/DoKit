import { window } from '@kit.ArkUI';
import display from '@ohos.display';

export interface MainWindowRectPx {
  leftPx: number;
  topPx: number;
  widthPx: number;
  heightPx: number;
}

export function bindWindowStageToAppStorage(windowStage: window.WindowStage): void {
  AppStorage.setOrCreate('windowStage', windowStage);
  try {
    const mainWin = windowStage.getMainWindowSync();
    const avoidArea = mainWin.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    AppStorage.setOrCreate('topRectHeight', avoidArea.topRect.height);
    mainWin.on('avoidAreaChange', (data) => {
      if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
        AppStorage.setOrCreate('topRectHeight', data.area.topRect.height);
      }
    });
  } catch (_e) {
  }
}

export function queryMainWindowRectPx(): MainWindowRectPx {
  try {
    const stage = AppStorage.get<window.WindowStage>('windowStage');
    if (stage !== undefined && stage !== null) {
      const rect = stage.getMainWindowSync().getWindowProperties().windowRect;
      return {
        leftPx: rect.left,
        topPx: rect.top,
        widthPx: rect.width,
        heightPx: rect.height
      };
    }
  } catch (_e) {
  }
  try {
    const displayInfo = display.getDefaultDisplaySync();
    return {
      leftPx: 0,
      topPx: 0,
      widthPx: displayInfo.width,
      heightPx: displayInfo.height
    };
  } catch (_e2) {
    return { leftPx: 0, topPx: 0, widthPx: 1, heightPx: 1 };
  }
}

export function setSubWindowTransparent(subWindow: window.Window): void {
  try {
    subWindow.setWindowBackgroundColor('#00000000');
  } catch (_e) {
  }
}

export function layoutSubWindowToMainBounds(subWindow: window.Window): void {
  const bound = queryMainWindowRectPx();
  try {
    subWindow.setWindowLayoutFullScreen(true);
  } catch (_e) {
  }
  try {
    subWindow.resize(Math.max(1, bound.widthPx), Math.max(1, bound.heightPx));
    subWindow.moveWindowTo(bound.leftPx, bound.topPx);
  } catch (_e2) {
  }
}
