import { access, connection } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger, Redact } from '../common/Logger';

const SCOPE: string = 'Bluetooth';

/** 一台已配对设备。addr 在 API 26 且未申请 GET_BLUETOOTH_PEERS_MAC 时是虚拟地址。 */
export interface PairedDevice {
  /** 传给 notificationExtensionSubscription.subscribe() 的地址，不上屏、不落日志。 */
  addr: string;
  /** 仅用于 UI 展示的掩码地址。 */
  maskedAddr: string;
  name: string;
}

export interface PairedDeviceListResult {
  devices: PairedDevice[];
  /** 0 表示成功；2900003 = 蓝牙未开启，2900001 = 蓝牙服务未启动。 */
  errorCode: number;
}

export class BluetoothService {
  static isEnabled(): boolean {
    try {
      return access.getState() === access.BluetoothState.STATE_ON;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `access.getState failed code=${e.code}`);
      return false;
    }
  }

  /**
   * 列出已配对设备。需要先完成系统配对（本应用不发起配对）。
   * 单台设备取名失败不影响整体列表，回退成掩码地址显示。
   */
  static listPaired(): PairedDeviceListResult {
    let addrs: Array<string> = [];
    try {
      addrs = connection.getPairedDevices();
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `getPairedDevices failed code=${e.code}`);
      return { devices: [], errorCode: e.code };
    }

    const devices: PairedDevice[] = [];
    for (const addr of addrs) {
      const masked: string = Redact.addr(addr);
      let name: string = '';
      try {
        name = connection.getRemoteDeviceName(addr);
      } catch (err) {
        const e: BusinessError = err as BusinessError;
        Logger.w(SCOPE, `getRemoteDeviceName failed addr=${masked} code=${e.code}`);
      }
      devices.push({
        addr: addr,
        maskedAddr: masked,
        name: name.length > 0 ? name : masked
      });
    }
    Logger.i(SCOPE, `listPaired count=${devices.length}`);
    return { devices: devices, errorCode: 0 };
  }
}
