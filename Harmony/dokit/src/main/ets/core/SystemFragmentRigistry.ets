import { BundleKey } from '../constant/BundleKey';
import { FragmentIndex } from '../constant/FragmentIndex';
import { DoKitBundle, FragmentCloseHandler, SystemFragmentBuilder } from './FragmentRenderer';
import { DoKitPageRecord, DoKitPageStack } from './DoKitPageStack';
import { SysInfoFragment, renderSysInfoFragment } from '../kit/sysinfo/SysInfoPage';
import { WebDoorFragment, renderWebDoorFragment } from '../kit/webdoor/WebDoorPage';
import { WebDoorDefaultFragment, renderWebDoorDefaultFragment } from '../kit/webdoor/WebDoorWebViewPage';
import { FileExplorerFragment, renderFileExplorerFragment } from '../kit/fileexplorer/FileExplorerPage';
import { ThirdLibInfoFragment, renderThirdLibInfoFragment } from '../kit/sysinfo/ThirdLibInfoPage';
import { DataCleanFragment, renderDataCleanFragment } from '../kit/dataclean/DataCleanPage';
import { CrashCaptureMainFragmentMeta, renderCrashCaptureMainFragment } from '../kit/crash/CrashCaptureMainFragment';
import { BlockMonitorFragmentMeta, renderBlockMonitorFragment } from '../kit/blockmonitor/BlockMonitorFragment';
import { FrameInfoFragmentMeta, renderFrameInfoFragment } from '../kit/parameter/frameInfo/FrameInfoFragment';
import { CpuMainPageFragmentMeta, renderCpuMainPageFragment } from '../kit/parameter/cpu/CpuMainPageFragment';
import { RamMainPageFragmentMeta, renderRamMainPageFragment } from '../kit/parameter/ram/RamMainPageFragment';
import { NetWorkMonitorFragmentMeta, renderNetWorkMonitorFragment } from '../kit/network/NetWorkMonitorFragment';
import {
  PerformanceMonitorFragmentMeta,
  renderPerformanceMonitorFragment
} from '../kit/performance/PerformanceMonitorFragment';

/**
 * 全屏工具页容器，对标 Android kit/core/UniversalActivity
 * 内部使用 DoKitPageStack 支持 A→B→返回 A
 */
export class SystemFragmentRegistry {
  private static readonly fragments: Map<string, SystemFragmentBuilder> = new Map();
  private static initialized: boolean = false;
  private static openHandler: ((fragmentName: string, isSystemFragment: boolean) => void) | null = null;
  private static closeHandler: (() => void) | null = null;

  static initDefaultFragments(): void {
    if (SystemFragmentRegistry.initialized) {
      return;
    }
    SystemFragmentRegistry.registerSystemFragment(SysInfoFragment.CLASS_NAME, wrapBuilder(renderSysInfoFragment));
    SystemFragmentRegistry.registerSystemFragment(WebDoorFragment.CLASS_NAME, wrapBuilder(renderWebDoorFragment));
    SystemFragmentRegistry.registerSystemFragment(WebDoorDefaultFragment.CLASS_NAME,
      wrapBuilder(renderWebDoorDefaultFragment));
    SystemFragmentRegistry.registerSystemFragment(FileExplorerFragment.CLASS_NAME,
      wrapBuilder(renderFileExplorerFragment));
    SystemFragmentRegistry.registerSystemFragment(ThirdLibInfoFragment.CLASS_NAME,
      wrapBuilder(renderThirdLibInfoFragment));
    SystemFragmentRegistry.registerSystemFragment(DataCleanFragment.CLASS_NAME, wrapBuilder(renderDataCleanFragment));
    SystemFragmentRegistry.registerSystemFragment(CrashCaptureMainFragmentMeta.CLASS_NAME,
      wrapBuilder(renderCrashCaptureMainFragment));
    SystemFragmentRegistry.registerSystemFragment(BlockMonitorFragmentMeta.CLASS_NAME,
      wrapBuilder(renderBlockMonitorFragment));
    SystemFragmentRegistry.registerSystemFragment(PerformanceMonitorFragmentMeta.CLASS_NAME,
      wrapBuilder(renderPerformanceMonitorFragment));
    SystemFragmentRegistry.registerSystemFragment(FrameInfoFragmentMeta.CLASS_NAME,
      wrapBuilder(renderFrameInfoFragment));
    SystemFragmentRegistry.registerSystemFragment(CpuMainPageFragmentMeta.CLASS_NAME,
      wrapBuilder(renderCpuMainPageFragment));
    SystemFragmentRegistry.registerSystemFragment(RamMainPageFragmentMeta.CLASS_NAME,
      wrapBuilder(renderRamMainPageFragment));
    SystemFragmentRegistry.registerSystemFragment(NetWorkMonitorFragmentMeta.CLASS_NAME,
      wrapBuilder(renderNetWorkMonitorFragment));
    SystemFragmentRegistry.initialized = true;
  }

  static registerSystemFragment(fragmentName: string, builder: SystemFragmentBuilder): void {
    SystemFragmentRegistry.fragments.set(fragmentName, builder);
  }

  static getSystemFragmentBuilder(fragmentName: string): SystemFragmentBuilder | undefined {
    return SystemFragmentRegistry.fragments.get(fragmentName);
  }

  static hasSystemFragment(fragmentName: string): boolean {
    return SystemFragmentRegistry.fragments.has(fragmentName);
  }

  static setOpenHandler(handler: ((fragmentName: string, isSystemFragment: boolean) => void) | null): void {
    SystemFragmentRegistry.openHandler = handler;
  }

  static setCloseHandler(handler: (() => void) | null): void {
    SystemFragmentRegistry.closeHandler = handler;
  }

  /** 打开工具根页：清栈再 push */
  static showContent(fragmentName: string, bundle?: DoKitBundle, isSystemFragment: boolean = false): void {
    const pageBundle = SystemFragmentRegistry.buildBundle(fragmentName, bundle, isSystemFragment);
    DoKitPageStack.open(new DoKitPageRecord(fragmentName, pageBundle, isSystemFragment));
    SystemFragmentRegistry.notifyOpen();
  }

  /** 全屏内下级页：压栈 */
  static pushContent(fragmentName: string, bundle?: DoKitBundle, isSystemFragment: boolean = false): void {
    const pageBundle = SystemFragmentRegistry.buildBundle(fragmentName, bundle, isSystemFragment);
    DoKitPageStack.push(new DoKitPageRecord(fragmentName, pageBundle, isSystemFragment));
    SystemFragmentRegistry.notifyOpen();
  }

  /** 返回上一页；栈空则关闭全屏 */
  static popOrFinish(): void {
    if (DoKitPageStack.isEmpty()) {
      SystemFragmentRegistry.finish();
      return;
    }
    const stillHas = DoKitPageStack.pop();
    if (!stillHas) {
      SystemFragmentRegistry.finish();
      return;
    }
    SystemFragmentRegistry.notifyOpen();
  }

  static finish(): void {
    DoKitPageStack.clear();
    if (SystemFragmentRegistry.closeHandler !== null) {
      SystemFragmentRegistry.closeHandler();
    }
  }

  static getFragmentName(): string {
    return DoKitPageStack.peek()?.name ?? '';
  }

  static getBundle(): DoKitBundle {
    return DoKitPageStack.peek()?.bundle ?? {};
  }

  static isSystemFragmentActive(): boolean {
    return DoKitPageStack.peek()?.isSystem ?? false;
  }

  static hasActiveFragment(): boolean {
    return !DoKitPageStack.isEmpty();
  }

  static clearContent(): void {
    DoKitPageStack.clear();
  }

  private static buildBundle(fragmentName: string, bundle: DoKitBundle | undefined,
    isSystemFragment: boolean): DoKitBundle {
    const pageBundle: DoKitBundle = bundle ?? {};
    pageBundle[BundleKey.FRAGMENT_INDEX] =
      isSystemFragment ? FragmentIndex.FRAGMENT_SYSTEM : FragmentIndex.FRAGMENT_CUSTOM;
    pageBundle[isSystemFragment ? BundleKey.SYSTEM_FRAGMENT_CLASS : BundleKey.CUSTOM_FRAGMENT_CLASS] = fragmentName;
    return pageBundle;
  }

  private static notifyOpen(): void {
    const top = DoKitPageStack.peek();
    if (top === undefined) {
      return;
    }
    if (SystemFragmentRegistry.openHandler !== null) {
      SystemFragmentRegistry.openHandler(top.name, top.isSystem);
    }
  }

  /**
   * 对标 Android UniversalActivity.onCreate 中按 FRAGMENT_INDEX 解析 Fragment Class
   */
  static resolvefragmentName(bundle: DoKitBundle): string {
    const index = bundle[BundleKey.FRAGMENT_INDEX] as number;
    if (!index) {
      return '';
    }
    switch (index) {
      case FragmentIndex.FRAGMENT_SYSTEM:
        return (bundle[BundleKey.SYSTEM_FRAGMENT_CLASS] as string) ?? '';
      case FragmentIndex.FRAGMENT_CUSTOM:
        return (bundle[BundleKey.CUSTOM_FRAGMENT_CLASS] as string) ?? '';
      default:
        return '';
    }
  }
}

@Builder
export function buildUniversalFragment(fragmentName: string, bundle: DoKitBundle, onClose: FragmentCloseHandler) {
  SystemFragmentRegistry.getSystemFragmentBuilder(fragmentName)?.builder(bundle, onClose);
}
