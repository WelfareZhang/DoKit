import { CustomFragmentRenderer } from '../core/DoKitIntent';
import { DoKitBundle } from '../core/FragmentRenderer';

@Builder
function defaultCustomFullScreenPage(_fragmentClass: string, _bundle: DoKitBundle, _onClose: () => void) {
  Column().width(0).height(0).hitTestBehavior(HitTestMode.None)
}

/**
 * @deprecated 浮层改挂主窗口 OverlayManager。业务页不要再放这个组件。
 * 留一个不占点击的空节点，避免旧页面还写着它时挡住列表。
 */
@Component
export struct DoKitFloatingWindow {
  @BuilderParam customFullScreenPage: CustomFragmentRenderer = defaultCustomFullScreenPage;

  build() {
    Column()
      .width(0)
      .height(0)
      .hitTestBehavior(HitTestMode.None)
  }
}
