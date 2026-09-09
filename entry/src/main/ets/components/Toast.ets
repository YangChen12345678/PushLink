import { UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';

const SCOPE: string = 'Toast';
/** 停留时长，够读完一句短提示。 */
const DURATION_MS: number = 2000;
/** 距屏幕底部的距离。抬高一些，避开底部标签栏。 */
const BOTTOM_OFFSET: string = '15%';

/**
 * 操作反馈的统一出口，用系统原生 Toast。
 *
 * 之前用的是 HdsSnackBar，但它是横贯屏幕的条状浮层：
 * 宽度只能给固定值、没有按内容自适应，文字对齐也控制不了
 * （contentModifier 里的 width 会被浮层内部布局覆盖）。
 * 为了让它看起来贴合文字，只能按字符估算宽度，估不准就会显得没对齐。
 *
 * 原生 Toast 天生就是胶囊形、宽度贴合内容、文字居中，正是这里需要的形态。
 * 代价是不能挂操作按钮——但实际上一个都没用到。
 */
export class Toast {
  static show(ui: UIContext, message: string): void {
    if (message.length === 0) {
      return;
    }
    try {
      ui.getPromptAction().showToast({
        message: message,
        duration: DURATION_MS,
        bottom: BOTTOM_OFFSET
      });
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      // 提示弹不出来不该影响主流程，记一笔即可。
      Logger.w(SCOPE, `showToast failed code=${e.code}`);
    }
  }
}
