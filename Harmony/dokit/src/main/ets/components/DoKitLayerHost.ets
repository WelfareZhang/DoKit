import { window } from '@kit.ArkUI';
import { GlobalConfig } from '../config/GlobalConfig';
import { DoKitViewManager } from '../core/DoKitViewManager';
import { buildUniversalFragment, SystemFragmentRegistry } from '../core/SystemFragmentRigistry';
import { buildCustomFragment, CustomFragmentRegistry } from '../core/CustomFragmentRegistry';
import { DoKitPageStack } from '../core/DoKitPageStack';
import { DoKitManager } from '../core/DoKitManager';
import { ToolPanelDoKitView } from '../core/toolpanel/ToolPanelDoKitView';
import { ColorPickManager } from '../kit/colorpick/ColorPickManager';
import { ColorPickerDoKitView } from '../kit/colorpick/ColorPickerDoKitView';
import { AlignRulerManager } from '../kit/alignruler/AlignRulerManager';
import { AlignRulerDoKitView } from '../kit/alignruler/AlignRulerDoKitView';
import { ViewCheckManager } from '../kit/viewcheck/ViewCheckManager';
import { ViewCheckDoKitView } from '../kit/viewcheck/ViewCheckDoKitView';
import { ViewCheckTree } from '../kit/viewcheck/ViewCheckTree';
import { LayoutBorderManager } from '../kit/layoutborder/LayoutBorderManager';
import { LayoutBorderDoKitView } from '../kit/layoutborder/LayoutBorderDoKitView';
import { KitGroup } from '../model/KitModels';
import { DOKIT_MODAL_TICK } from '../subwindow/DoKitSubWindowRoute';

/**
 * 只放在模态窗里：面板、全屏栈、取色 / 标尺 / 控件检查 / 布局边框。
 * 球、自定义浮窗、性能条不在这里，避免全屏窗口挡住业务页。
 */
@Component
export struct DoKitLayerHost {
  @State private containerWidth: number = 0;
  @State private containerHeight: number = 0;
  @State private showPanel: boolean = false;
  @State private hasFullscreen: boolean = false;
  @State private activeFragmentClass: string = '';
  @State private activeIsSystemFragment: boolean = false;
  @State private pageRevision: number = 0;
  @State private kitGroups: KitGroup[] = [];
  @State private showColorPicker: boolean = false;
  @State private showAlignRuler: boolean = false;
  @State private showViewCheck: boolean = false;
  @State private showLayoutBorder: boolean = false;

  @StorageLink(DOKIT_MODAL_TICK) @Watch('pull') modalTick: number = 0;
  @StorageProp('topRectHeight') private topRectHeightPx: number = 0;

  aboutToAppear(): void {
    this.pull();
  }

  pull(): void {
    if (this.modalTick < 0) {
      return;
    }
    this.kitGroups = DoKitManager.getKitGroups();
    this.syncFullscreenFromStack();
    this.showPanel = DoKitViewManager.isPanelVisible() && !this.hasFullscreen;
    this.showColorPicker = ColorPickManager.getInstance().isOverlayOpen();
    this.showAlignRuler = AlignRulerManager.getInstance().isOverlayOpen();
    this.showViewCheck = ViewCheckManager.getInstance().isOverlayOpen();
    this.showLayoutBorder = LayoutBorderManager.getInstance().isOverlayOpen();
  }

  private syncFullscreenFromStack(): void {
    const top = DoKitPageStack.peek();
    this.pageRevision = DoKitPageStack.getRevision();
    if (top === undefined) {
      this.hasFullscreen = false;
      this.activeFragmentClass = '';
      this.activeIsSystemFragment = false;
      return;
    }
    this.hasFullscreen = true;
    this.activeFragmentClass = top.name;
    this.activeIsSystemFragment = top.isSystem;
  }

  private onFullscreenClose(): void {
    SystemFragmentRegistry.popOrFinish();
  }

  private statusBarHeightVp(): number {
    if (!this.shouldAvoidStatusBar()) {
      return 0;
    }
    return this.topRectHeightPx > 0 ? px2vp(this.topRectHeightPx) : 0;
  }

  private shouldAvoidStatusBar(): boolean {
    if (this.topRectHeightPx > 0) {
      return true;
    }
    try {
      const stage = AppStorage.get<window.WindowStage>('windowStage');
      if (stage === undefined || stage === null) {
        return false;
      }
      return stage.getMainWindowSync().getWindowProperties().isLayoutFullScreen;
    } catch (_err) {
      return false;
    }
  }

  @Builder
  private buildFullscreenContent() {
    Column() {
      if (this.activeIsSystemFragment) {
        buildUniversalFragment(this.activeFragmentClass, SystemFragmentRegistry.getBundle(), () => {
          this.onFullscreenClose();
        });
      } else if (CustomFragmentRegistry.has(this.activeFragmentClass)) {
        buildCustomFragment(this.activeFragmentClass, SystemFragmentRegistry.getBundle(), () => {
          this.onFullscreenClose();
        });
      } else {
        Column() {
          Text(`未注册全屏页: ${this.activeFragmentClass}`)
            .fontSize(14)
            .fontColor('#666666')
            .margin(16)
          Button('关闭')
            .onClick(() => {
              SystemFragmentRegistry.finish();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeightVp() })
    .backgroundColor(Color.White)
    .hitTestBehavior(HitTestMode.Default)
    .key(`dokit_fs_${this.activeFragmentClass}_${this.pageRevision}`)
  }

  build() {
    Stack() {
      if (GlobalConfig.debugMode) {
        if (!this.showPanel && !this.hasFullscreen && this.showColorPicker) {
          ColorPickerDoKitView({
            containerWidth: this.containerWidth,
            containerHeight: this.containerHeight
          })
        }
        if (!this.showPanel && !this.hasFullscreen && this.showAlignRuler) {
          AlignRulerDoKitView({
            containerWidth: this.containerWidth,
            containerHeight: this.containerHeight
          })
        }
        if (!this.showPanel && !this.hasFullscreen && this.showLayoutBorder) {
          LayoutBorderDoKitView()
        }
        if (!this.showPanel && !this.hasFullscreen && this.showViewCheck) {
          ViewCheckDoKitView({
            containerWidth: this.containerWidth,
            containerHeight: this.containerHeight
          })
        }
        if (this.showPanel && !this.hasFullscreen) {
          Column() {
            ToolPanelDoKitView({
              kitGroups: this.kitGroups,
              onClose: () => {
                DoKitViewManager.detachToolPanel();
              }
            })
          }
          .width('100%')
          .height('100%')
          .padding({ top: this.statusBarHeightVp() })
          .backgroundColor(Color.White)
          .hitTestBehavior(HitTestMode.Default)
        }
        if (this.hasFullscreen && this.activeFragmentClass.length > 0) {
          this.buildFullscreenContent()
        }
      }
    }
    .id(ViewCheckTree.FLOATING_ID)
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.None)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.containerWidth = Number(newValue.width);
      this.containerHeight = Number(newValue.height);
    })
  }
}
