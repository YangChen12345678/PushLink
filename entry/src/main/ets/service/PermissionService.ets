import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';

const SCOPE: string = 'Permission';

/**
 * 本应用声明的六个权限里，只有 ACCESS_BLUETOOTH 是 user_grant（需要运行时弹窗）；
 * INTERNET / GET_NETWORK_INFO / RUNNING_LOCK / GET_BUNDLE_INFO 安装时授予；
 * SUBSCRIBE_NOTIFICATION 是受限权限，靠签名 Profile 里的 ACL 生效，同样不走弹窗。
 */
const BLUETOOTH_PERMISSION: Permissions = 'ohos.permission.ACCESS_BLUETOOTH';

export class PermissionService {
  /** 同步查询蓝牙权限当前是否已授予，用于进入页面时展示状态。 */
  static isBluetoothGranted(): boolean {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const status: abilityAccessCtrl.GrantStatus =
        abilityAccessCtrl.createAtManager().checkAccessTokenSync(info.appInfo.accessTokenId, BLUETOOTH_PERMISSION);
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `checkAccessTokenSync failed code=${e.code}`);
      return false;
    }
  }

  /**
   * 拉起蓝牙权限弹窗。已授予时系统直接返回结果不弹窗。
   * 用户勾选"禁止后不再询问"后再次调用会静默失败，此时只能引导去系统设置。
   */
  static async requestBluetooth(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const result = await abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(context, [BLUETOOTH_PERMISSION]);
      const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
      Logger.i(SCOPE, `requestBluetooth granted=${granted}`);
      return granted;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `requestPermissionsFromUser failed code=${e.code}`);
      return false;
    }
  }
}
