import { window } from '@kit.ArkUI';
import { GlobalConfig } from '../config/GlobalConfig';
import { DoKitViewManager } from '../core/DoKitViewManager';
import { buildUniversalFragment, SystemFragmentRegistry } from '../core/SystemFragmentRigistry';
import { buildCustomFragment, CustomFragmentRegistry } from '../core/CustomFragmentRegistry';
import { DoKitPageStack } from '../core/DoKitPageStack';
import { DoKitManager } from '../core/DoKitManager';
import { ToolPanelDoKitView } from '../core/toolpanel/ToolPanelDoKitView';
import { KitGroup } from '../model/KitModels';
import { DOKIT_MODAL_TICK, DOKIT_NAV_INSET_PX, DOKIT_TOP_RECT_HEIGHT, DOKIT_WINDOW_STAGE } from '../util/DoKitWindowUtil';

/**
 * 全屏层：工具面板和全屏功能页。
 * 悬浮球和自定义浮窗不在这里画。
 * 层表里挂两个本组件。role 为 panel 的只画工具面板，role 为 page 的只画栈顶全屏页。
 */
@Component
export struct DoKitModalContent {
  /** page：只画全屏功能页。panel：只画工具面板。两个实例各管一块。 */
  @Prop role: string = 'page';
  /** 宿主量到的宽。onAreaChange 写入，当前布局不读它。 */
  @State private containerWidth: number = 0;
  /** 宿主量到的高。onAreaChange 写入，当前布局不读它。 */
  @State private containerHeight: number = 0;
  /** 工具面板是否该画出来。全屏页开着时为 false，面板让开全屏页。 */
  @State private showPanel: boolean = false;
  /** 页面栈里还有全屏页。 */
  @State private hasFullscreen: boolean = false;
  /** 栈顶全屏页的注册名。用它选出要画的 Builder。 */
  @State private activeFragmentClass: string = '';
  /** 栈顶是系统页还是宿主注册的自定义页。两边 Builder 不在同一张表。 */
  @State private activeIsSystemFragment: boolean = false;
  /** 页面栈版本。和页名一起放进 key，换页时拆掉旧内容重建。 */
  @State private pageRevision: number = 0;
  /** 工具面板要展示的 kit 分组。每次 pull 从 DoKitManager 重新取。 */
  @State private kitGroups: KitGroup[] = [];

  /**
   * 全屏页或工具面板变化时，DoKitMainOverlay 把这个计数加一。
   * @Watch 调 pull，从页面栈和面板状态重新取一次要画的内容。
   */
  @StorageLink(DOKIT_MODAL_TICK) @Watch('pull') modalTick: number = 0;
  /** 状态栏高度，单位 px。需要避让时再换成 vp。 */
  @StorageProp(DOKIT_TOP_RECT_HEIGHT) private topRectHeightPx: number = 0;
  /** 底部导航栏高度，单位 px。 */
  @StorageProp(DOKIT_NAV_INSET_PX) private navInsetPx: number = 0;

  /** 第一次出现时按当前栈和面板画一次。这时计数可能还没变，不能只等 @Watch。 */
  aboutToAppear(): void {
    this.pull();
  }

  /**
   * 按页面栈和工具面板状态刷新本实例要画的内容。
   * 计数小于 0 时直接返回。当前写入方只做加一，这个分支是防御。
   * 全屏页开着时关掉面板标记，避免面板和全屏页叠在一起抢点击。
   */
  pull(): void {
    if (this.modalTick < 0) {
      return;
    }
    this.kitGroups = DoKitManager.getKitGroups();
    this.syncFullscreenFromStack();
    this.showPanel = DoKitViewManager.isPanelVisible() && !this.hasFullscreen;
  }

  /**
   * 从页面栈顶抄出当前全屏页。
   * 页名决定画哪一页，系统标记决定查哪张注册表，栈版本放进 key 用来换页重建。
   * 栈空时清掉这些状态，build 里的全屏分支就不会进。
   */
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

  /** 全屏页里的返回。退一层；退完最后一层就关掉整个全屏。 */
  private onFullscreenClose(): void {
    SystemFragmentRegistry.popOrFinish();
  }

  /** 顶部要留出的状态栏高度，单位 vp。不需要避让时为 0，内容顶到屏幕上沿。 */
  private statusBarHeightVp(): number {
    if (!this.shouldAvoidStatusBar()) {
      return 0;
    }
    return this.topRectHeightPx > 0 ? px2vp(this.topRectHeightPx) : 0;
  }

  /** 底部要留出的导航栏高度，单位 vp。没有导航栏高度时不留白。 */
  private navInsetVp(): number {
    if (this.navInsetPx <= 0) {
      return 0;
    }
    return px2vp(this.navInsetPx);
  }

  /**
   * 要不要避开状态栏。
   * 已经量到状态栏高度就避开。还没量到时看主窗口是不是全屏布局，
   * 全屏布局的内容会伸进状态栏，需要留出顶部。
   */
  private shouldAvoidStatusBar(): boolean {
    if (this.topRectHeightPx > 0) {
      return true;
    }
    try {
      const stage = AppStorage.get<window.WindowStage>(DOKIT_WINDOW_STAGE);
      if (stage === undefined || stage === null) {
        return false;
      }
      return stage.getMainWindowSync().getWindowProperties().isLayoutFullScreen;
    } catch (_err) {
      return false;
    }
  }

  build() {
    Stack() {
      // 非调试包不画面板和全屏页。
      if (GlobalConfig.debugMode) {
        // 只有面板实例画工具面板。全屏页开着时 showPanel 已是 false，这里再挡一次。
        if (this.role === 'panel' && this.showPanel && !this.hasFullscreen) {
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
          .padding({ top: this.statusBarHeightVp(), bottom: this.navInsetVp() })
          .backgroundColor(Color.White)
          // Default：面板自己接收点击，并挡住下面的业务页。
          .hitTestBehavior(HitTestMode.Default)
        }
        // 全屏内容必须直接写在 build 里，不能抽成 @Builder。
        // 写进 @Builder 时，关闭和页内按钮收不到点击。工具面板直接写在这里，所以它的按钮能点。
        // 页名或栈版本变了就换 key。@Builder 的参数变了不会就地刷新，不换 key 的话压栈后仍停在旧页。
        if (this.role === 'page' && this.hasFullscreen && this.activeFragmentClass.length > 0) {
          Column() {
            // 系统页和宿主自定义页各有一张注册表，按栈顶标记选一张。
            if (this.activeIsSystemFragment) {
              buildUniversalFragment(this.activeFragmentClass, SystemFragmentRegistry.getBundle(), () => {
                this.onFullscreenClose();
              });
            } else if (CustomFragmentRegistry.has(this.activeFragmentClass)) {
              buildCustomFragment(this.activeFragmentClass, SystemFragmentRegistry.getBundle(), () => {
                this.onFullscreenClose();
              });
            } else {
              // 名字不在任何注册表里。给出提示和关闭，避免白屏又退不出去。
              // 这里直接清栈。正常页走 onFullscreenClose，只退一层。
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
          .padding({ top: this.statusBarHeightVp(), bottom: this.navInsetVp() })
          .backgroundColor(Color.White)
          // Default：页内按钮能点，空白处也不把点击漏给底下的业务页。
          .hitTestBehavior(HitTestMode.Default)
          .key(`dokit_fs_${this.activeFragmentClass}_${this.pageRevision}`)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    // 正在显示全屏页或面板时用 Default，点击留在这一层。
    // 都没显示时用 None，这一层不挡业务页。
    .hitTestBehavior(this.hasFullscreen || this.showPanel ? HitTestMode.Default : HitTestMode.None)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.containerWidth = Number(newValue.width);
      this.containerHeight = Number(newValue.height);
    })
  }
}
