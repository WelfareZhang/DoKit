import { window } from '@kit.ArkUI';
import { DoKitChrome } from './DoKitChrome';

/**
 * 对外仍叫 SubWindow。内部按控件小窗 + 模态窗调度，不再铺全屏透明层。
 */
export class DoKitSubWindow {
  static attach(windowStage: window.WindowStage): void {
    DoKitChrome.attach(windowStage);
  }

  static detach(): void {
    DoKitChrome.detach();
  }

  static show(): void {
    DoKitChrome.show();
  }

  static hide(): void {
    DoKitChrome.hide();
  }

  static isShowing(): boolean {
    return DoKitChrome.isShowing();
  }
}
