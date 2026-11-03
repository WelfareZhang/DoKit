import { common } from '@kit.AbilityKit';
import { AbstractKit, Category, DoKit } from '@didi-hummer/dokit';
import {
  buildMultiPageA,
  buildMultiPageB,
  buildMultiPageC,
  MultiPageA,
  MultiPageB,
  MultiPageC
} from './MultiPagePages';

/** 全屏页 A → B → C，再按栈逐级返回 */
export class MultiPageKit extends AbstractKit {
  constructor() {
    super();
    this.category = Category.BIZ;
  }

  getName(): string {
    return '多页面kit';
  }

  getIcon(): Resource {
    return $r('app.media.dk_sys_info');
  }

  onClickWithReturn(_context: common.UIAbilityContext): boolean {
    DoKit.launchFullScreen(MultiPageA.CLASS_NAME);
    return true;
  }
}

/** 注册 A / B / C，点击 kit 之前就要挂上 */
export function registerMultiPageFragments(): void {
  DoKit.registerCustomFragment(MultiPageA.CLASS_NAME, wrapBuilder(buildMultiPageA));
  DoKit.registerCustomFragment(MultiPageB.CLASS_NAME, wrapBuilder(buildMultiPageB));
  DoKit.registerCustomFragment(MultiPageC.CLASS_NAME, wrapBuilder(buildMultiPageC));
}
