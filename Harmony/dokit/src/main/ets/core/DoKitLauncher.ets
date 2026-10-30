import { DoKitBundle } from './FragmentRenderer';
import { DoKitIntent, DoKitViewLaunchMode } from './DoKitIntent';
import { DoKitViewManager } from './DoKitViewManager';
import { SystemFragmentRegistry } from './SystemFragmentRigistry';

/**
 * 悬浮窗和全屏启动器，对标 Android kit/core/SimpleDoKitLauncher
 */
export class DoKitLauncher {
  static launchFloating(
    targetClass: string,
    mode: DoKitViewLaunchMode = DoKitViewLaunchMode.SINGLE_INSTANCE,
    bundle?: DoKitBundle
  ): void {
    const doKitIntent = new DoKitIntent(targetClass);
    doKitIntent.mode = mode;
    doKitIntent.bundle = bundle ?? {};
    DoKitViewManager.attach(doKitIntent);
  }

  static removeFloating(targetClass: string): void {
    DoKitViewManager.detach(targetClass);
  }

  /** 打开全屏工具根页（清栈） */
  static launchFullScreen(
    targetClass: string,
    bundle?: DoKitBundle,
    isSystemFragment: boolean = false
  ): void {
    SystemFragmentRegistry.showContent(targetClass, bundle, isSystemFragment);
  }

  /** 全屏内再打开下级页（压栈） */
  static pushFullScreen(
    targetClass: string,
    bundle?: DoKitBundle,
    isSystemFragment: boolean = false
  ): void {
    SystemFragmentRegistry.pushContent(targetClass, bundle, isSystemFragment);
  }

  static finishFullScreen(): void {
    SystemFragmentRegistry.finish();
  }

  /** 全屏返回：有栈 pop，空则关闭 */
  static popFullScreen(): void {
    SystemFragmentRegistry.popOrFinish();
  }
}
