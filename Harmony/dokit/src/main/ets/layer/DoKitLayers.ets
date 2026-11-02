import { DOKIT_OVERLAY_TICK } from '../util/DoKitWindowUtil';

/** 一层浮层的绘制入口。参数：名字、宽、高、顶部避让、底部避让。 */
export type DoKitLayerBuilder = WrappedBuilder<[string, number, number, number, number]>;

/** 框架层名字。浮窗用自己的名字，不写在这里。 */
export class DoKitLayerName {
  /** 悬浮球。 */
  static readonly BALL: string = 'dokit.ball';
  /** 工具面板。 */
  static readonly PANEL: string = 'dokit.panel';
  /** 全屏功能页。同一时刻只有这一层，画的是页面栈顶。 */
  static readonly PAGE: string = 'dokit.page';
}

/** 给界面 ForEach 用的快照。order 越大越靠上。 */
export class DoKitLayerSnap {
  /** 层名字。 */
  name: string = '';
  /** 叠放序号。数字大的后画，压在上面。 */
  order: number = 0;
  /** 内容版本。变了 ForEach 才会拆掉旧节点重建。 */
  revision: number = 0;
  /** 要画在全屏页上面。 */
  abovePage: boolean = false;
  /** 要画在工具面板上面。 */
  abovePanel: boolean = false;
  /** 这一层怎么画。 */
  builder: DoKitLayerBuilder | null = null;
}

/** 顺序表里的一条。界面不直接读它，提交后由 snapshot 拷出去。 */
class DoKitLayerItem {
  name: string = '';
  order: number = 0;
  revision: number = 1;
  abovePage: boolean = false;
  abovePanel: boolean = false;
  builder: DoKitLayerBuilder | null = null;
}

/**
 * 浮层顺序表。后挂上的 order 更大，画在上面。
 * 全屏页和工具面板没有第二个窗口，带标记的记录会在 commit 时挪到它们之上。
 */
export class DoKitLayers {
  /** 当前叠着的层。 */
  private static readonly items: DoKitLayerItem[] = [];
  /** 全屏页刚打开或刚关掉时要通知的人。取色器用来关掉自己。 */
  private static readonly pageObservers: Array<(entered: boolean, left: boolean) => void> = [];
  /** 正在连续改表。大于 0 时 commit 先不通知界面。 */
  private static batchDepth: number = 0;
  /** 上次已经通知给界面的摘要。一样就不刷新。 */
  private static lastSignature: string = '';

  /** 登记全屏页进出的监听。清空层表时不会清掉。 */
  static addPageObserver(observer: (entered: boolean, left: boolean) => void): void {
    DoKitLayers.pageObservers.push(observer);
  }

  /** 全屏页刚打开或刚关掉时，逐个通知监听。 */
  static notifyPageEdge(entered: boolean, left: boolean): void {
    for (let i = 0; i < DoKitLayers.pageObservers.length; i++) {
      const observer = DoKitLayers.pageObservers[i];
      if (observer !== undefined) {
        observer(entered, left);
      }
    }
  }

  /** 连续改层表。全部改完，最外层结束时才提交一次。 */
  static batch(run: () => void): void {
    DoKitLayers.batchDepth++;
    run();
    DoKitLayers.batchDepth--;
    // 还有外层 batch 包着，等它结束再通知界面
    if (DoKitLayers.batchDepth === 0) {
      DoKitLayers.commit();
    }
  }

  /** 没有这条就按标记插进去。已经有则只更新画法和盖住标记，序号和版本不动。 */
  static ensure(name: string, builder: DoKitLayerBuilder, abovePage: boolean, abovePanel: boolean): void {
    const found = DoKitLayers.find(name);
    if (found !== undefined) {
      found.builder = builder;
      found.abovePage = abovePage;
      found.abovePanel = abovePanel;
      return;
    }
    const item = new DoKitLayerItem();
    item.name = name;
    item.builder = builder;
    item.abovePage = abovePage;
    item.abovePanel = abovePanel;
    // 新层插在该盖住的锚点下面，或排到当前最上面
    item.order = DoKitLayers.initialOrder(abovePage, abovePanel);
    item.revision = 1;
    DoKitLayers.items.push(item);
  }

  /** 按名字拿掉一层。没有这个名字则什么都不做。 */
  static detach(name: string): void {
    for (let i = 0; i < DoKitLayers.items.length; i++) {
      const item = DoKitLayers.items[i];
      if (item !== undefined && item.name === name) {
        DoKitLayers.items.splice(i, 1);
        return;
      }
    }
  }

  /** 去掉已经不在浮窗表里的浮窗。球、面板、全屏页保留。 */
  static retainFloats(names: string[]): void {
    const kept: DoKitLayerItem[] = [];
    for (let i = 0; i < DoKitLayers.items.length; i++) {
      const item = DoKitLayers.items[i];
      if (item === undefined) {
        continue;
      }
      if (DoKitLayers.isReserved(item.name) || DoKitLayers.containsName(names, item.name)) {
        kept.push(item);
      }
    }
    // 清空后放回同一批对象，序号和版本都还在
    DoKitLayers.items.length = 0;
    for (let i = 0; i < kept.length; i++) {
      const item = kept[i];
      if (item !== undefined) {
        DoKitLayers.items.push(item);
      }
    }
  }

  /** 先把该盖住的层抬上去。层表和上次不一样，才通知界面重画。 */
  static commit(): void {
    // 还在 batch 里，这次先不提交
    if (DoKitLayers.batchDepth > 0) {
      return;
    }
    DoKitLayers.relift();
    const signature = DoKitLayers.signature();
    // 名字、序号、版本都没变，界面不用重画
    if (signature === DoKitLayers.lastSignature) {
      return;
    }
    DoKitLayers.lastSignature = signature;
    const tick = (AppStorage.get<number>(DOKIT_OVERLAY_TICK) ?? 0) + 1;
    AppStorage.setOrCreate(DOKIT_OVERLAY_TICK, tick);
  }

  /** 按序号从小到大拷出一份，给界面先画下层、再画上层。 */
  static snapshot(): DoKitLayerSnap[] {
    const result: DoKitLayerSnap[] = [];
    for (let i = 0; i < DoKitLayers.items.length; i++) {
      const item = DoKitLayers.items[i];
      if (item === undefined || item.builder === null) {
        continue;
      }
      const snap = new DoKitLayerSnap();
      snap.name = item.name;
      snap.order = item.order;
      snap.revision = item.revision;
      snap.abovePage = item.abovePage;
      snap.abovePanel = item.abovePanel;
      snap.builder = item.builder;
      result.push(snap);
    }
    DoKitLayers.sortByOrder(result);
    return result;
  }

  /** 层表里有没有这个名字。 */
  static has(name: string): boolean {
    return DoKitLayers.find(name) !== undefined;
  }

  /** 清空层表和上次的摘要。进出监听还留着。 */
  static clear(): void {
    DoKitLayers.items.length = 0;
    DoKitLayers.lastSignature = '';
  }

  /** 提交前调顺序：先抬过全屏页，再抬过工具面板，最后让球回到最上面。 */
  private static relift(): void {
    DoKitLayers.liftMatching(DoKitLayerName.PAGE, true);
    DoKitLayers.liftMatching(DoKitLayerName.PANEL, false);
    DoKitLayers.raiseBall();
  }

  /** 把带标记、且还在锚点下面的记录按原顺序挪到锚点之上。 */
  private static liftMatching(anchorName: string, usePageFlag: boolean): void {
    const anchor = DoKitLayers.find(anchorName);
    if (anchor === undefined) {
      return;
    }
    const limit = anchor.order;
    let ceiling = anchor.order;
    let guard = 0;
    while (guard < DoKitLayers.items.length) {
      guard++;
      let pick: DoKitLayerItem | undefined = undefined;
      for (let i = 0; i < DoKitLayers.items.length; i++) {
        const item = DoKitLayers.items[i];
        // 锚点自己，以及已经在它上面的，不用再抬
        if (item === undefined || item.name === anchorName || item.order > limit) {
          continue;
        }
        const match = usePageFlag ? item.abovePage : item.abovePanel;
        if (!match) {
          continue;
        }
        // 每次抬当前最靠下的一条，原来的先后顺序还在
        if (pick === undefined || item.order < pick.order) {
          pick = item;
        }
      }
      if (pick === undefined) {
        return;
      }
      ceiling++;
      pick.order = ceiling;
    }
  }

  /**
   * 新层的序号。要盖住页面和面板时排到最上面。
   * 页面在且不盖住页面，就插到页面下面；面板同理。
   */
  private static initialOrder(abovePage: boolean, abovePanel: boolean): number {
    let limit: number = -1;
    const page = DoKitLayers.find(DoKitLayerName.PAGE);
    if (page !== undefined && !abovePage) {
      limit = page.order;
    }
    const panel = DoKitLayers.find(DoKitLayerName.PANEL);
    if (panel !== undefined && !abovePanel) {
      // 两个锚点都要避开时，插到更靠下的那个下面
      if (limit < 0 || panel.order < limit) {
        limit = panel.order;
      }
    }
    // 没有要避开的锚点，排到当前最上面
    if (limit < 0) {
      return DoKitLayers.maxOrder() + 1;
    }
    // 锚点和它上面的层都让出一位，新层占原来的位置
    for (let i = 0; i < DoKitLayers.items.length; i++) {
      const item = DoKitLayers.items[i];
      if (item !== undefined && item.order >= limit) {
        item.order += 1;
      }
    }
    return limit;
  }

  /** 没有全屏页和面板时，悬浮球回到最上面。 */
  private static raiseBall(): void {
    if (DoKitLayers.find(DoKitLayerName.PAGE) !== undefined ||
      DoKitLayers.find(DoKitLayerName.PANEL) !== undefined) {
      return;
    }
    const ball = DoKitLayers.find(DoKitLayerName.BALL);
    if (ball === undefined) {
      return;
    }
    const max = DoKitLayers.maxOrder();
    // 已经在最上面就不动，避免每次提交序号都加一
    if (ball.order < max) {
      ball.order = max + 1;
    }
  }

  /** 按序号从小到大排。界面按这个顺序先画下面的。 */
  private static sortByOrder(list: DoKitLayerSnap[]): void {
    for (let i = 1; i < list.length; i++) {
      const current = list[i];
      if (current === undefined) {
        continue;
      }
      let j = i - 1;
      while (j >= 0) {
        const prev = list[j];
        if (prev === undefined || prev.order <= current.order) {
          break;
        }
        list[j + 1] = prev;
        j--;
      }
      list[j + 1] = current;
    }
  }

  /** 当前最大的叠放序号。表是空的时返回 0。 */
  private static maxOrder(): number {
    let max = 0;
    for (let i = 0; i < DoKitLayers.items.length; i++) {
      const item = DoKitLayers.items[i];
      if (item !== undefined && item.order > max) {
        max = item.order;
      }
    }
    return max;
  }

  /** 按名字找那一条。没有则返回空。 */
  private static find(name: string): DoKitLayerItem | undefined {
    for (let i = 0; i < DoKitLayers.items.length; i++) {
      const item = DoKitLayers.items[i];
      if (item !== undefined && item.name === name) {
        return item;
      }
    }
    return undefined;
  }

  /** 层表摘要：名字、序号、版本。这三项变了界面才重画。 */
  private static signature(): string {
    const parts: string[] = [];
    for (let i = 0; i < DoKitLayers.items.length; i++) {
      const item = DoKitLayers.items[i];
      if (item === undefined) {
        continue;
      }
      parts.push(`${item.name}@${item.order}#${item.revision}`);
    }
    return parts.join('|');
  }

  /** 球、面板、全屏页。对齐浮窗时不会被删掉。 */
  private static isReserved(name: string): boolean {
    return name === DoKitLayerName.BALL || name === DoKitLayerName.PANEL || name === DoKitLayerName.PAGE;
  }

  /** 这个名字是否还在当前浮窗名单里。 */
  private static containsName(names: string[], name: string): boolean {
    for (let i = 0; i < names.length; i++) {
      if (names[i] === name) {
        return true;
      }
    }
    return false;
  }
}
