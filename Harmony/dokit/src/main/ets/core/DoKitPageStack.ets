import { DoKitBundle } from './FragmentRenderer';

/** 全屏栈记录 */
export class DoKitPageRecord {
  name: string;
  bundle: DoKitBundle;
  isSystem: boolean;

  constructor(name: string, bundle: DoKitBundle = {}, isSystem: boolean = false) {
    this.name = name;
    this.bundle = bundle;
    this.isSystem = isSystem;
  }
}

/**
 * 自研全屏页面栈：open=清栈进根页，push=下级页，pop=返回
 */
export class DoKitPageStack {
  private static records: DoKitPageRecord[] = [];
  private static changeHandler: (() => void) | null = null;
  private static revision: number = 0;

  static getRevision(): number {
    return DoKitPageStack.revision;
  }

  static setChangeHandler(handler: (() => void) | null): void {
    DoKitPageStack.changeHandler = handler;
  }

  static open(record: DoKitPageRecord): void {
    DoKitPageStack.records = [record];
    DoKitPageStack.notify();
  }

  static push(record: DoKitPageRecord): void {
    DoKitPageStack.records.push(record);
    DoKitPageStack.notify();
  }

  /** @returns 弹出后栈是否仍非空 */
  static pop(): boolean {
    if (DoKitPageStack.records.length === 0) {
      return false;
    }
    DoKitPageStack.records.pop();
    DoKitPageStack.notify();
    return DoKitPageStack.records.length > 0;
  }

  static clear(): void {
    if (DoKitPageStack.records.length === 0) {
      return;
    }
    DoKitPageStack.records = [];
    DoKitPageStack.notify();
  }

  static peek(): DoKitPageRecord | undefined {
    if (DoKitPageStack.records.length === 0) {
      return undefined;
    }
    return DoKitPageStack.records[DoKitPageStack.records.length - 1];
  }

  static size(): number {
    return DoKitPageStack.records.length;
  }

  static isEmpty(): boolean {
    return DoKitPageStack.records.length === 0;
  }

  private static notify(): void {
    DoKitPageStack.revision++;
    if (DoKitPageStack.changeHandler !== null) {
      DoKitPageStack.changeHandler();
    }
  }
}
