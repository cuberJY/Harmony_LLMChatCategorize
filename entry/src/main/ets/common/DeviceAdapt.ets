/**
 * 多规格设备适配工具（DeviceAdapt）
 * 统一断点体系 + 折叠屏状态监听，支撑手机/阔直板/折叠屏/阔折叠/三折叠/平板等不同宽高比设备
 *
 * 断点体系（按可用宽度 vp 分档，与官方 600/840 断点对齐）：
 * - sm  <600vp：常规手机 / 阔直板 / 折叠屏外屏（Stack 单栏 + 抽屉侧边栏）
 * - md  <840vp：折叠屏展开 / 小平板（Split 分栏：侧边栏常驻左栏）
 * - lg  ≥840vp：平板横屏 / 大平板 / 三折叠展开（Split 分栏 + 内容多列密度）
 *
 * 状态共享：AppStorageV2 全局响应式状态（@Trace），任何页面连接后断点变化自动刷新 UI，
 * 避免跨 Navigation/NavDestination 传递断点的手动同步
 *
 * 注意：折叠状态用自定义字符串而非 display.FoldStatus 枚举，
 * 避免各 SDK 版本枚举成员差异（如无 UNKNOWN）导致编译错误
 */

import { display, AppStorageV2 } from "@kit.ArkUI";

export const BP_SM = "sm"; // <600vp 手机全系 / 折叠外屏
export const BP_MD = "md"; // <840vp 折叠展开 / 小平板
export const BP_LG = "lg"; // >=840vp 平板横屏 / 大平板 / 三折叠

/** 宽屏进入分栏布局的阈值（vp）：>=600 即 Sidebar + Chat 并立 */
export const SPLIT_THRESHOLD_VP = 600;
/** 内容密度升档阈值（vp）：>=840 网格多列、内容限宽 */
export const LARGE_THRESHOLD_VP = 840;

/** 折叠状态字符串常量 */
export const FOLD_UNKNOWN = "unknown"; // 非折叠屏 / 查询失败
export const FOLD_FOLDED = "folded"; // 折叠屏合上（外屏）
export const FOLD_EXPANDED = "expanded"; // 折叠屏展开（内屏）
export const FOLD_HALF_FOLDED = "half_folded"; // 半折叠悬停

/** 全局设备状态（@ObservedV2 + @Trace，跨页面响应式共享） */
@ObservedV2
export class DeviceState {
  /** 当前断点档位（bp_sm / bp_md / bp_lg） */
  @Trace breakpoint: string = BP_SM;
  /** 当前折叠屏状态（字符串常量 FOLD_*） */
  @Trace foldStatus: string = FOLD_UNKNOWN;
  /** 是否宽屏分栏（>=600vp） */
  @Trace isWide: boolean = false;
}

/* 单例引用缓存（AppStorageV2.connect 幂等，重复连接返回同一实例） */
let cachedDeviceState: DeviceState | undefined = undefined;

/** 获取全局设备状态单例（页面/组件内调用，@Trace 字段变化驱动 UI 刷新） */
export function getDeviceState(): DeviceState {
  /* 局部变量承接，确保 ArkTS 出口类型窄化可靠（connect 返回 T | undefined，兜底 new 保证非空） */
  let s = cachedDeviceState;
  if (s === undefined) {
    s = AppStorageV2.connect(DeviceState, "deviceState", () => new DeviceState());
    if (s === undefined) {
      s = new DeviceState();
    }
    cachedDeviceState = s;
  }
  return s;
}

/** 依据可用宽度（vp）计算断点档位 */
export function calcBreakpoint(widthVp: number): string {
  if (widthVp < SPLIT_THRESHOLD_VP) {
    return BP_SM;
  }
  if (widthVp < LARGE_THRESHOLD_VP) {
    return BP_MD;
  }
  return BP_LG;
}

/** 断点是否为宽屏（>=600vp，分栏布局） */
export function isWideLayout(bp: string): boolean {
  return bp === BP_MD || bp === BP_LG;
}

/** 获取当前默认屏幕宽度（vp），失败兜底为 0（由调用方按窄屏处理） */
export function getWindowWidthVp(): number {
  try {
    const d = display.getDefaultDisplaySync();
    return d.width / d.densityPixels;
  } catch (e) {
    return 0;
  }
}

/** 获取当前折叠状态字符串（非折叠屏/查询失败返回 FOLD_UNKNOWN） */
export function getFoldState(): string {
  try {
    const s = display.getFoldStatus();
    /* 注意：API 20 的 FoldStatus 枚举成员带 FOLD_STATUS_ 前缀（FOLD_STATUS_FOLDED/EXPANDED/HALF_FOLDED） */
    if (s === display.FoldStatus.FOLD_STATUS_FOLDED) {
      return FOLD_FOLDED;
    }
    if (s === display.FoldStatus.FOLD_STATUS_EXPANDED) {
      return FOLD_EXPANDED;
    }
    if (s === display.FoldStatus.FOLD_STATUS_HALF_FOLDED) {
      return FOLD_HALF_FOLDED;
    }
    return FOLD_UNKNOWN;
  } catch (e) {
    /* 非折叠屏设备调用 getFoldStatus 抛异常 → 按未知处理 */
    return FOLD_UNKNOWN;
  }
}

/** 当前设备是否为折叠屏 */
export function isFoldable(): boolean {
  return getFoldState() !== FOLD_UNKNOWN;
}
