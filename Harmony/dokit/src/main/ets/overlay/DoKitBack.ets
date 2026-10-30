import { DoKitViewManager } from '../core/DoKitViewManager';
import { DoKitPageStack } from '../core/DoKitPageStack';
import { SystemFragmentRegistry } from '../core/SystemFragmentRigistry';

/**
 * 对标 Android DoKit 根布局的返回键。
 * 只处理全屏栈和工具面板。取色、标尺、控件检查、布局边框在安卓里 shouldDealBackKey 为 false。
 */
export class DoKitBack {
  static consume(): boolean {
    if (!DoKitPageStack.isEmpty() || SystemFragmentRegistry.hasActiveFragment()) {
      SystemFragmentRegistry.popOrFinish();
      return true;
    }
    if (DoKitViewManager.isPanelVisible()) {
      DoKitViewManager.detachToolPanel();
      return true;
    }
    return false;
  }
}
