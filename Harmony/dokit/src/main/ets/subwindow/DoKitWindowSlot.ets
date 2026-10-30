import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { setSubWindowTransparent } from './DoKitSubWindowUtil';

const DOMAIN = 0xD0F1;
const TAG = 'DoKitWindow';

export class WindowRectPx {
  leftPx: number;
  topPx: number;
  widthPx: number;
  heightPx: number;

  constructor(leftPx: number, topPx: number, widthPx: number, heightPx: number) {
    this.leftPx = leftPx;
    this.topPx = topPx;
    this.widthPx = widthPx;
    this.heightPx = heightPx;
  }
}

/**
 * 一个子窗槽：创建、按矩形摆放、销毁。
 * 手势过程中只 move，尺寸没变时不 resize。
 */
export class DoKitWindowSlot {
  windowName: string;
  private subWindow?: window.Window;
  private opening: boolean = false;
  private epoch: number = 0;
  private pending?: WindowRectPx;
  private fullScreen: boolean = false;
  private layoutApplied: boolean = false;
  private appliedLeft: number = -100000;
  private appliedTop: number = -100000;
  private appliedWidth: number = -1;
  private appliedHeight: number = -1;
  private layerPinned: boolean = false;

  constructor(windowName: string) {
    this.windowName = windowName;
  }

  hasWindow(): boolean {
    return this.subWindow !== undefined;
  }

  close(): void {
    this.epoch++;
    this.opening = false;
    this.pending = undefined;
    this.layoutApplied = false;
    this.appliedLeft = -100000;
    this.appliedTop = -100000;
    this.appliedWidth = -1;
    this.appliedHeight = -1;
    this.layerPinned = false;
    const win = this.subWindow;
    this.subWindow = undefined;
    if (win !== undefined) {
      try {
        win.destroyWindow();
      } catch (_e) {
      }
    }
  }

  open(stage: window.WindowStage, routeName: string, storage: LocalStorage | null, focusable: boolean,
    fullScreen: boolean, rect: WindowRectPx, onShown: (() => void) | null = null): void {
    this.fullScreen = fullScreen;
    this.pending = rect;
    if (this.subWindow !== undefined) {
      this.applyRect(this.subWindow, rect, onShown);
      return;
    }
    if (this.opening) {
      return;
    }
    const epoch = this.epoch;
    this.opening = true;
    stage.createSubWindow(this.windowName, (err, subWindow) => {
      if (epoch !== this.epoch) {
        if (subWindow !== undefined) {
          try {
            subWindow.destroyWindow();
          } catch (_e) {
          }
        }
        return;
      }
      if (err.code !== 0 || subWindow === undefined) {
        this.opening = false;
        hilog.error(DOMAIN, TAG, 'createSubWindow %{public}s failed: %{public}s', this.windowName,
          JSON.stringify(err));
        return;
      }
      this.subWindow = subWindow;
      try {
        subWindow.setWindowFocusable(focusable);
      } catch (_e) {
      }
      const onLoaded = (loadErr: BusinessError): void => {
        if (epoch !== this.epoch) {
          try {
            subWindow.destroyWindow();
          } catch (_e) {
          }
          return;
        }
        if (loadErr.code !== 0) {
          this.opening = false;
          hilog.error(DOMAIN, TAG, 'loadContent %{public}s failed: %{public}s', routeName, JSON.stringify(loadErr));
          this.destroyIfCurrent(subWindow);
          return;
        }
        setSubWindowTransparent(subWindow);
        subWindow.showWindow((showErr) => {
          if (epoch !== this.epoch) {
            try {
              subWindow.destroyWindow();
            } catch (_e) {
            }
            return;
          }
          this.opening = false;
          if (showErr.code !== 0) {
            hilog.error(DOMAIN, TAG, 'showWindow %{public}s failed: %{public}s', this.windowName,
              JSON.stringify(showErr));
            this.destroyIfCurrent(subWindow);
            return;
          }
          setSubWindowTransparent(subWindow);
          const again = this.pending;
          if (again !== undefined) {
            this.applyRect(subWindow, again, () => {
              if (onShown !== null) {
                onShown();
              }
            });
            return;
          }
          if (onShown !== null) {
            onShown();
          }
        });
      };
      if (storage === null) {
        subWindow.loadContentByName(routeName, onLoaded);
      } else {
        subWindow.loadContentByName(routeName, storage, onLoaded);
      }
    });
  }

  /**
   * 把子窗固定在指定层级。层级高的不会被低层级的 moveWindowTo 抬上去。
   * 浮标额外推迟拖动抬升，避免拖动过程中盖住悬浮球。
   */
  pinLayer(level: number, delayRaise: boolean): void {
    const win = this.subWindow;
    if (win === undefined) {
      this.layerPinned = false;
      return;
    }
    if (delayRaise) {
      try {
        win.setWindowDelayRaiseOnDrag(true);
      } catch (_e) {
      }
    }
    try {
      win.setSubWindowZLevel(level).then(() => {
        this.layerPinned = true;
      }).catch(() => {
        this.layerPinned = false;
      });
    } catch (_e) {
      this.layerPinned = false;
    }
  }

  isLayerPinned(): boolean {
    return this.layerPinned;
  }

  /**
   * 松手后等窗口服务处理完最后一次移动，再去抬悬浮球。
   * 拖动过程中不要走这里。
   */
  whenSettled(onSettled: () => void): void {
    const win = this.subWindow;
    if (win === undefined || this.appliedLeft <= -100000) {
      onSettled();
      return;
    }
    try {
      win.moveWindowTo(this.appliedLeft, this.appliedTop, (_err: BusinessError) => {
        onSettled();
      });
    } catch (_e) {
      onSettled();
    }
  }

  place(rect: WindowRectPx, onPlaced: (() => void) | null = null): void {
    this.pending = rect;
    const win = this.subWindow;
    if (win === undefined) {
      return;
    }
    this.applyRect(win, rect, onPlaced);
  }

  /**
   * 子窗在 moveWindowTo / resize 后会被系统抬到同级最前。
   * 浮标挪完后必须把球再抬回去，否则球会被盖住。
   */
  bringToFront(): void {
    const win = this.subWindow;
    if (win === undefined || this.appliedLeft <= -100000) {
      return;
    }
    try {
      win.raiseToAppTop().catch(() => {
        this.repeatMove(win);
      });
    } catch (_e) {
      this.repeatMove(win);
    }
  }

  private repeatMove(win: window.Window): void {
    try {
      win.moveWindowTo(this.appliedLeft, this.appliedTop);
    } catch (_e) {
    }
  }

  private applyRect(win: window.Window, rect: WindowRectPx, onPlaced: (() => void) | null): void {
    const width = Math.max(1, rect.widthPx);
    const height = Math.max(1, rect.heightPx);
    const left = rect.leftPx;
    const top = rect.topPx;
    if (!this.layoutApplied) {
      try {
        win.setWindowLayoutFullScreen(this.fullScreen);
      } catch (_e) {
      }
      this.layoutApplied = true;
    }
    const resized = width !== this.appliedWidth || height !== this.appliedHeight;
    const moved = left !== this.appliedLeft || top !== this.appliedTop;
    this.appliedWidth = width;
    this.appliedHeight = height;
    this.appliedLeft = left;
    this.appliedTop = top;
    if (!resized && !moved) {
      if (onPlaced !== null) {
        onPlaced();
      }
      return;
    }
    // 拖动每帧都走这里。回调版 moveWindowTo 要等窗口服务返回，手指会把图标甩开。
    if (onPlaced === null) {
      try {
        if (resized) {
          win.resize(width, height);
        }
        if (moved) {
          win.moveWindowTo(left, top);
        }
      } catch (_e) {
      }
      return;
    }
    const placed = onPlaced;
    const shrink = (): void => {
      if (!resized) {
        placed();
        return;
      }
      try {
        win.resize(width, height, (_err: BusinessError) => {
          placed();
        });
      } catch (_e) {
        placed();
      }
    };
    // 先挪到终点再缩小。先缩小的话窗口左上角还在屏幕原点，图标会跳到顶部。
    if (moved) {
      try {
        win.moveWindowTo(left, top, (_err: BusinessError) => {
          shrink();
        });
      } catch (_e) {
        shrink();
      }
      return;
    }
    shrink();
  }

  private destroyIfCurrent(subWindow: window.Window): void {
    if (this.subWindow === subWindow) {
      this.subWindow = undefined;
      this.layoutApplied = false;
      this.appliedWidth = -1;
      this.appliedHeight = -1;
      this.layerPinned = false;
    }
    try {
      subWindow.destroyWindow();
    } catch (_e) {
    }
  }
}
