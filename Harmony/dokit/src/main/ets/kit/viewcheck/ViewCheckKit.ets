import { common } from '@kit.AbilityKit';
import { ViewCheckConfig } from '../../config/ViewCheckConfig';
import { CloseHandler, CustomViewBuilder, DoKitParams } from '../../core/CustomViewRegistry';
import { DoKitFloatOptions, DoKitViewManager } from '../../core/DoKitViewManager';
import { AbstractKit } from '../AbstractKit';
import { ViewCheckDoKitView } from './ViewCheckDoKitView';
import { ViewCheckManager } from './ViewCheckManager';

@Builder
function renderViewCheckFloat(_params: DoKitParams, _close: CloseHandler) {
  ViewCheckDoKitView()
}

const VIEW_CHECK_FLOAT: CustomViewBuilder = wrapBuilder(renderViewCheckFloat);

/**
 * 控件检查 Kit，对标 Android ViewCheckerKit
 */
export class ViewCheckKit extends AbstractKit {
  get isInnerKit(): boolean {
    return true;
  }

  innerKitId(): string {
    return 'dokit_sdk_ui_ck_widget';
  }

  getName(): string {
    return '控件检查';
  }

  getIcon(): Resource {
    return $r('app.media.dk_view_check');
  }

  onAppInit(_context: common.UIAbilityContext): void {
    ViewCheckConfig.setViewCheckOpen(false);
  }

  onClickWithReturn(_context: common.UIAbilityContext): boolean {
    ViewCheckManager.getInstance().open();
    DoKitViewManager.launchFloatingView(
      ViewCheckManager.FLOAT_NAME,
      VIEW_CHECK_FLOAT,
      undefined,
      DoKitFloatOptions.underLayer()
    );
    return true;
  }
}
