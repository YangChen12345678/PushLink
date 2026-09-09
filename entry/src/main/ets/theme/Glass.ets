import { uiMaterial } from '@kit.ArkUI';
import { Logger } from '../common/Logger';

const SCOPE: string = 'Glass';

/**
 * 沉浸材质（「沉浸光感视效」）。
 *
 * 这是原生 ArkUI 的能力（@ohos.arkui.uiMaterial），不是 HDS——
 * 此前判断「原生只能用 backgroundBlurStyle 做近似」是错的，
 * 系统材质层做的是滤镜，与手工模糊不是一回事。
 *
 * 材质有三层开关，任一层关掉都会退回普通外观：
 *   1. 设备算力——低算力设备只落到背景色/描边/阴影，没有滤镜；
 *   2. 系统状态——用户可在系统侧禁用，禁用后设了参数也不生效；
 *   3. 调用失败——查询本身抛异常时一律当作不可用。
 *
 * 降级不需要额外代码：材质生效时会盖掉组件自己的背景色与模糊，
 * 所以调用方照常设 backgroundBlurStyle 当基线即可。
 */
export class Glass {
  /** 本机此刻能否用沉浸材质。查询失败一律按不可用处理。 */
  static available(): boolean {
    try {
      if (!uiMaterial.isImmersiveMaterialSupported()) {
        Logger.i(SCOPE, 'immersive material unsupported on this device');
        return false;
      }
      // DEFAULT 表示由应用自行决定，只有 DISABLE 是明确关闭。
      const info: uiMaterial.MaterialInfo = uiMaterial.getMaterialInfo();
      if (info.state === uiMaterial.MaterialState.DISABLE) {
        Logger.i(SCOPE, 'immersive material disabled by system');
        return false;
      }
      return true;
    } catch (err) {
      Logger.w(SCOPE, 'material probe failed, falling back to blur');
      return false;
    }
  }

  /**
   * 底部悬浮标签栏用的材质。不可用时返回 undefined，
   * 交给 barBackgroundBlurStyle 那条基线接管。
   */
  static floatingBar(): uiMaterial.ImmersiveMaterial | undefined {
    if (!Glass.available()) {
      return undefined;
    }
    try {
      return new uiMaterial.ImmersiveMaterial({
        // REGULAR 是默认档：再薄会透得看不清文字，再厚就失去了通透感。
        style: uiMaterial.ImmersiveStyle.REGULAR,
        applyShadow: true,
        // interactive 暂时关掉：它是「交互式形变」，胶囊会跟手变形。
        // 怀疑形变后视觉位置偏离了布局位置，而命中判定仍按未形变的布局算——
        // 实测底部标签栏拖动松手会选中左边一格的 tab，偏移量正好接近一格。
        // 光感反馈（lightEffect）与形变无关，保留。
        interactive: false,
        lightEffect: {}
      });
    } catch (err) {
      Logger.w(SCOPE, 'ImmersiveMaterial construction failed');
      return undefined;
    }
  }
}
