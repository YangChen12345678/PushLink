import { power } from '@kit.BasicServicesKit';
import { batteryInfo } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';

const SCOPE: string = 'Motion';
/** 低于这个电量就停掉持续动画。 */
const LOW_BATTERY_PERCENT: number = 20;

/** 流光一个循环的时长。慢一点更像呼吸，快了显得焦躁。 */
export const FLOW_DURATION_MS: number = 2600;
/** 状态切换等一次性过渡的时长。 */
export const TRANSITION_MS: number = 220;

/**
 * 视效的降级判定。
 *
 * 持续动画要为续航让路：省电模式下、或电量偏低时一律停掉，
 * 界面退回静态外观，功能完全不受影响。
 *
 * 注意 HarmonyOS 没有公开的「减弱动效」无障碍设置查询接口，
 * 所以这里只能靠电源状态判断，无法响应用户在系统里的动效偏好。
 */
export class Motion {
  /** 是否允许播放持续动画。查询失败时保守返回 false——宁可不动，不能费电。 */
  static allowContinuousAnimation(): boolean {
    try {
      if (power.getPowerMode() !== power.DevicePowerMode.MODE_NORMAL) {
        return false;
      }
    } catch (err) {
      Logger.w(SCOPE, 'getPowerMode failed, animation disabled');
      return false;
    }
    try {
      if (batteryInfo.batterySOC <= LOW_BATTERY_PERCENT) {
        return false;
      }
    } catch (err) {
      Logger.w(SCOPE, 'batterySOC unavailable, animation disabled');
      return false;
    }
    return true;
  }
}
