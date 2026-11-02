import { common } from '@kit.AbilityKit';
import { ColorPickConfig } from '../../config/ColorPickConfig';
import { CloseHandler, CustomViewBuilder, DoKitParams } from '../../core/CustomViewRegistry';
import { DoKitFloatOptions, DoKitViewManager } from '../../core/DoKitViewManager';
import { AbstractKit } from '../AbstractKit';
import { ColorPickManager } from './ColorPickManager';
import { ColorPickerDoKitView } from './ColorPickerDoKitView';

@Builder
function renderColorPickerFloat(_params: DoKitParams, _close: CloseHandler) {
  ColorPickerDoKitView()
}

const COLOR_PICKER_FLOAT: CustomViewBuilder = wrapBuilder(renderColorPickerFloat);

/**
 * 取色器 Kit，对标 Android ColorPickerKit
 */
export class ColorPickerKit extends AbstractKit {
  get isInnerKit(): boolean {
    return true;
  }

  innerKitId(): string {
    return 'dokit_sdk_ui_ck_color_pick';
  }

  getName(): string {
    return '取色器';
  }

  getIcon(): Resource {
    return $r('app.media.dk_color_picker');
  }

  onAppInit(_context: common.UIAbilityContext): void {
    ColorPickConfig.setColorPickOpen(false);
  }

  onClickWithReturn(_context: common.UIAbilityContext): boolean {
    ColorPickManager.getInstance().open();
    DoKitViewManager.launchFloatingView(
      ColorPickManager.FLOAT_NAME,
      COLOR_PICKER_FLOAT,
      undefined,
      DoKitFloatOptions.underLayer()
    );
    return true;
  }
}
