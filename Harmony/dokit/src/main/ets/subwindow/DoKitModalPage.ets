import { window } from '@kit.ArkUI';
import { DoKitViewManager } from '../core/DoKitViewManager';
import { SystemFragmentRegistry } from '../core/SystemFragmentRigistry';
import { AlignRulerManager } from '../kit/alignruler/AlignRulerManager';
import { ColorPickManager } from '../kit/colorpick/ColorPickManager';
import { LayoutBorderManager } from '../kit/layoutborder/LayoutBorderManager';
import { ViewCheckManager } from '../kit/viewcheck/ViewCheckManager';
import { DoKitLayerHost } from '../components/DoKitLayerHost';
import { DOKIT_MODAL_ROUTE_NAME, DOKIT_MODAL_WINDOW_NAME } from './DoKitSubWindowRoute';

/**
 * 模态窗：工具面板、全屏栈、取色 / 标尺 / 控件检查 / 布局边框。
 * 只有这些界面打开时窗口才存在。
 */
@Entry({ routeName: DOKIT_MODAL_ROUTE_NAME })
@Component
struct DoKitModalPage {
  aboutToAppear(): void {
    try {
      window.findWindow(DOKIT_MODAL_WINDOW_NAME).setWindowBackgroundColor('#00000000');
    } catch (_e) {
    }
  }

  onBackPress(): boolean | void {
    if (SystemFragmentRegistry.hasActiveFragment()) {
      SystemFragmentRegistry.popOrFinish();
      return true;
    }
    if (DoKitViewManager.isPanelVisible()) {
      DoKitViewManager.detachToolPanel();
      return true;
    }
    if (ViewCheckManager.getInstance().isOverlayOpen()) {
      ViewCheckManager.getInstance().close();
      return true;
    }
    if (LayoutBorderManager.getInstance().isOverlayOpen()) {
      LayoutBorderManager.getInstance().close();
      return true;
    }
    if (AlignRulerManager.getInstance().isOverlayOpen()) {
      AlignRulerManager.getInstance().close();
      return true;
    }
    if (ColorPickManager.getInstance().isOverlayOpen()) {
      ColorPickManager.getInstance().close();
      return true;
    }
    return false;
  }

  build() {
    Stack() {
      DoKitLayerHost()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
