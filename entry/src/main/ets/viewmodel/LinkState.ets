import { common } from '@kit.AbilityKit';
import { Logger } from '../common/Logger';
import { BluetoothService, PairedDevice, PairedDeviceListResult } from '../service/BluetoothService';
import { PermissionService } from '../service/PermissionService';
import { SubscriptionService, SubscriptionSnapshot } from '../service/SubscriptionService';
import { GrantStore } from '../service/GrantStore';
import { HealthMonitor } from '../service/HealthMonitor';

export function emptySnapshot(): SubscriptionSnapshot {
  return {
    subscribed: false,
    subscribedAddrMasked: '',
    userGranted: false,
    grantedBundles: [],
    lastError: ''
  };
}

/**
 * 转发链路的状态与动作：蓝牙权限、配对设备、订阅登记、系统授权白名单。
 *
 * 从页面里提出来的目的不只是让页面变短——宽屏下同一份状态要同时喂给
 * 左侧列表和右侧详情两个组件，状态留在页面上就做不到。
 */
@Observed
export class LinkState {
  btGranted: boolean = false;
  btEnabled: boolean = false;
  devices: PairedDevice[] = [];
  deviceError: number = 0;
  selectedAddr: string = '';
  snap: SubscriptionSnapshot = emptySnapshot();
  /** 能否发出中断提醒。用户没给通知权限时提醒发不出去，界面要能说明。 */
  notifyEnabled: boolean = false;
  notice: string = '';

  /**
   * 链路是否真的能工作。
   * 阶段 B 实测：蓝牙关闭时 subscribed 仍为 true 但一条回调都收不到，
   * 所以不能只看订阅记录，必须三个条件同时成立。
   */
  healthy(): boolean {
    return this.snap.subscribed && this.snap.userGranted && this.btEnabled;
  }

  healthDetail(): string {
    if (this.healthy()) {
      return '正常';
    }
    const missing: string[] = [];
    if (!this.snap.subscribed) {
      missing.push('未订阅');
    }
    if (!this.snap.userGranted) {
      missing.push('未开启通知读取');
    }
    if (!this.btEnabled) {
      missing.push('蓝牙未开启');
    }
    return missing.join('、');
  }

  refreshBluetooth(): void {
    this.btGranted = PermissionService.isBluetoothGranted();
    this.btEnabled = BluetoothService.isEnabled();
    Logger.i('UI', `refreshBluetooth granted=${this.btGranted} enabled=${this.btEnabled}`);
    if (!this.btGranted || !this.btEnabled) {
      this.devices = [];
      this.deviceError = 0;
      return;
    }
    const result: PairedDeviceListResult = BluetoothService.listPaired();
    this.devices = result.devices;
    this.deviceError = result.errorCode;
    // 选中的设备若已解除配对，清空选择；不去猜测系统当前订阅对应哪台设备——地址已掩码，无法反查。
    if (this.selectedAddr.length > 0) {
      let stillPaired: boolean = false;
      for (const device of this.devices) {
        if (device.addr === this.selectedAddr) {
          stillPaired = true;
          break;
        }
      }
      if (!stillPaired) {
        this.selectedAddr = '';
      }
    }
  }

  async refreshSubscription(): Promise<void> {
    this.snap = await SubscriptionService.snapshot();
    this.notifyEnabled = await HealthMonitor.canNotify();
  }

  async requestNotifyPermission(ctx: common.UIAbilityContext): Promise<void> {
    this.notifyEnabled = await HealthMonitor.requestPermission(ctx);
    if (!this.notifyEnabled) {
      this.notice = '未获得通知权限，链路中断时无法提醒你。可在系统设置里手动开启';
    }
  }

  /**
   * 把系统授权列表同步到本地缓存。
   * 系统授权列表是唯一白名单来源，扩展进程只认这份缓存——它自己没法拉起授权页去问系统。
   */
  async syncWhitelist(ctx: common.Context): Promise<void> {
    await GrantStore.replaceAll(ctx, this.snap.grantedBundles);
  }

  async requestBluetooth(ctx: common.UIAbilityContext): Promise<void> {
    const granted: boolean = await PermissionService.requestBluetooth(ctx);
    this.notice = granted ? '' : '蓝牙权限未授予。若之前选过“禁止后不再询问”，需到系统设置手动开启';
    this.refreshBluetooth();
  }

  async subscribe(): Promise<void> {
    if (this.selectedAddr.length === 0) {
      this.notice = '请先选择一台已配对设备';
      return;
    }
    this.notice = await SubscriptionService.subscribe(this.selectedAddr);
  }

  async unsubscribe(): Promise<void> {
    this.notice = await SubscriptionService.unsubscribe();
  }

  async openSettings(ctx: common.UIAbilityContext): Promise<void> {
    const result: SubscriptionSnapshot = await SubscriptionService.openSettings(ctx);
    this.notice = result.lastError;
  }
}
