import { access } from '@kit.ConnectivityKit';
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';

const SCOPE: string = 'Health';
/** 中断提醒固定用这个 id，后一条会覆盖前一条，不会在通知栏堆积。 */
const NOTIFICATION_ID: number = 1001;

/**
 * 链路中断提醒。
 *
 * 要解决的问题：蓝牙一关，系统就停止投递通知回调，而界面上的「订阅已登记」
 * 仍然显示为是——用户不会察觉，只会在某天发现「iPhone 怎么半天没消息了」。
 *
 * **触发源的选择**：链路一断就收不到通知回调，扩展进程也不会被拉起，
 * 所以不能指望在投递路径上发现问题。唯一可行的主动信号是蓝牙状态变化事件。
 *
 * **已知限制**：监听依赖应用进程存活。进程被系统完全回收后，
 * 关闭蓝牙不会有任何提醒——这是系统限制，没有合规的绕法。
 * 兜底是用户下次打开应用时，界面顶部的健康状态会立刻显示异常。
 *
 * **不能指望事件本身去重**：实测关一次蓝牙，系统会在 3 秒内连发三次 STATE_OFF
 * （经典蓝牙与 BLE 等子系统依次关闭，各报一次）。所以必须自己按状态跃迁去重。
 */
export class HealthMonitor {
  private static listener: ((state: access.BluetoothState) => void) | undefined = undefined;
  /** 上一次观察到的状态。只在「非关闭 → 关闭」的跃迁上提醒，重复的 OFF 一律忽略。 */
  private static lastState: access.BluetoothState | undefined = undefined;
  /** 两次提醒的最小间隔，兜住状态短时间反复跳变的情况。 */
  private static lastNotifiedAt: number = 0;
  private static readonly MIN_INTERVAL_MS: number = 30000;

  /** 开始监听。幂等，重复调用不会叠加监听器。 */
  static start(): void {
    if (HealthMonitor.listener !== undefined) {
      return;
    }
    const handler = (state: access.BluetoothState): void => {
      const wasOff: boolean = HealthMonitor.lastState === access.BluetoothState.STATE_OFF;
      HealthMonitor.lastState = state;
      // 只关心「非关闭 → 关闭」这一个跃迁。打开时不打扰用户——
      // 界面自己会变绿，没必要再推一条通知。
      if (state !== access.BluetoothState.STATE_OFF || wasOff) {
        return;
      }
      const now: number = Date.now();
      if (now - HealthMonitor.lastNotifiedAt < HealthMonitor.MIN_INTERVAL_MS) {
        return;
      }
      HealthMonitor.lastNotifiedAt = now;
      Logger.w(SCOPE, 'bluetooth turned off, link interrupted');
      HealthMonitor.notifyInterrupted();
    };
    try {
      // 先记下当前状态，避免启动瞬间把「本来就关着」误判成刚刚关闭。
      HealthMonitor.lastState = access.getState();
    } catch (err) {
      HealthMonitor.lastState = undefined;
    }
    try {
      access.on('stateChange', handler);
      HealthMonitor.listener = handler;
      Logger.i(SCOPE, 'monitor started');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `monitor start failed code=${e.code}`);
    }
  }

  static stop(): void {
    if (HealthMonitor.listener === undefined) {
      return;
    }
    try {
      access.off('stateChange', HealthMonitor.listener);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.w(SCOPE, `monitor stop failed code=${e.code}`);
    }
    HealthMonitor.listener = undefined;
    HealthMonitor.lastState = undefined;
    Logger.i(SCOPE, 'monitor stopped');
  }

  /** 通知权限是否已开启。未开启时提醒发不出去，界面要能告诉用户。 */
  static async canNotify(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (err) {
      return false;
    }
  }

  /** 拉起系统的通知授权弹窗。 */
  static async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      await notificationManager.requestEnableNotification(context);
      return await HealthMonitor.canNotify();
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.w(SCOPE, `requestEnableNotification failed code=${e.code}`);
      return false;
    }
  }

  private static async notifyInterrupted(): Promise<void> {
    const request: notificationManager.NotificationRequest = {
      id: NOTIFICATION_ID,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: 'PushLink 转发已中断',
          text: '蓝牙已关闭，通知不会再转发到 iPhone。重新打开蓝牙即可恢复。'
        }
      }
    };
    try {
      await notificationManager.publish(request);
      Logger.i(SCOPE, 'interruption notice published');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      // 多半是用户没给通知权限。这里只留痕，不打断任何流程。
      Logger.w(SCOPE, `publish failed code=${e.code}`);
    }
  }
}
