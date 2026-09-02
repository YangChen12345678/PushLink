import { notificationExtensionSubscription } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger, Redact } from '../common/Logger';
import { GrantedBundle, grantKey } from '../common/Types';

const SCOPE: string = 'Subscription';

/** 订阅链路的完整状态快照，UI 每次前台刷新时整体重取。 */
export interface SubscriptionSnapshot {
  /** 是否已向系统登记订阅。 */
  subscribed: boolean;
  /** 已订阅设备的掩码地址；未订阅时为空串。 */
  subscribedAddrMasked: string;
  /** 系统"允许读取本机通知"总开关是否打开。 */
  userGranted: boolean;
  /** 系统授权的应用白名单。 */
  grantedBundles: GrantedBundle[];
  /** 脱敏后的错误描述，无错误时为空串。 */
  lastError: string;
}

/**
 * 把系统错误码翻译成可执行的中文说明。
 * 阶段 B 的分支判断（FreeBuds 失败是否改用 Mate 40E、是否停在 PoC）直接依赖这里的区分度。
 */
export function describeError(code: number): string {
  switch (code) {
    case 201:
      return `权限被拒绝或本机不支持（201）。优先排查签名 Profile 的 ACL 是否包含 SUBSCRIBE_NOTIFICATION`;
    case 801:
      return `本机不支持通知订阅扩展能力（801）`;
    case 1600001:
      return `通知服务内部错误（1600001）`;
    case 1600003:
      return `连接通知服务失败（1600003）`;
    case 1600018:
      return `通知设置窗口已在显示（1600018）`;
    case 1600023:
      return `系统未识别到本应用的 NotificationSubscriberExtensionAbility（1600023）。检查 module.json5 的扩展注册与安装包是否为最新`;
    default:
      return `未预期的错误码 ${code}`;
  }
}

export class SubscriptionService {
  /** 用指定的已配对设备地址登记订阅。addr 只传给系统，不上屏、不落日志。 */
  static async subscribe(addr: string): Promise<string> {
    const info: notificationExtensionSubscription.NotificationExtensionSubscriptionInfo = {
      addr: addr,
      type: notificationExtensionSubscription.SubscribeType.BLUETOOTH
    };
    try {
      await notificationExtensionSubscription.subscribe([info]);
      Logger.i(SCOPE, `subscribe ok addr=${Redact.addr(addr)}`);
      return '';
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      const desc: string = describeError(e.code);
      Logger.e(SCOPE, `subscribe failed addr=${Redact.addr(addr)} ${desc}`);
      return desc;
    }
  }

  static async unsubscribe(): Promise<string> {
    try {
      await notificationExtensionSubscription.unsubscribe();
      Logger.i(SCOPE, 'unsubscribe ok');
      return '';
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      const desc: string = describeError(e.code);
      Logger.e(SCOPE, `unsubscribe failed ${desc}`);
      return desc;
    }
  }

  /**
   * 拉起系统的"允许读取本机通知"半模态设置页，并接收用户当场设定的授权结果。
   * 这是 v1 白名单的唯一来源，返回的 grantedBundleInfos 直接作为白名单使用。
   */
  static async openSettings(context: common.UIAbilityContext): Promise<SubscriptionSnapshot> {
    try {
      const setting: notificationExtensionSubscription.UserGrantSetting =
        await notificationExtensionSubscription.openSubscriptionSettingsWithResult(context);
      const bundles: GrantedBundle[] = SubscriptionService.toGrantedBundles(setting.grantedBundleInfos);
      Logger.i(SCOPE, `openSettings enabled=${setting.userGrantEnabled} grantedCount=${bundles.length}`);
      return {
        subscribed: false,
        subscribedAddrMasked: '',
        userGranted: setting.userGrantEnabled,
        grantedBundles: bundles,
        lastError: ''
      };
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      const desc: string = describeError(e.code);
      Logger.e(SCOPE, `openSettings failed ${desc}`);
      return {
        subscribed: false,
        subscribedAddrMasked: '',
        userGranted: false,
        grantedBundles: [],
        lastError: desc
      };
    }
  }

  /** 整体重取订阅状态。任一子查询失败都记进 lastError，但不阻断其余字段。 */
  static async snapshot(): Promise<SubscriptionSnapshot> {
    let subscribed: boolean = false;
    let addrMasked: string = '';
    let userGranted: boolean = false;
    let bundles: GrantedBundle[] = [];
    let lastError: string = '';

    try {
      const infos: notificationExtensionSubscription.NotificationExtensionSubscriptionInfo[] =
        await notificationExtensionSubscription.getSubscribeInfo();
      subscribed = infos.length > 0;
      if (subscribed) {
        addrMasked = Redact.addr(infos[0].addr);
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      lastError = describeError(e.code);
      Logger.e(SCOPE, `getSubscribeInfo failed ${lastError}`);
    }

    try {
      userGranted = await notificationExtensionSubscription.isUserGranted();
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      lastError = describeError(e.code);
      Logger.e(SCOPE, `isUserGranted failed ${lastError}`);
    }

    try {
      const infos: notificationExtensionSubscription.GrantedBundleInfo[] =
        await notificationExtensionSubscription.getUserGrantedEnabledBundles();
      bundles = SubscriptionService.toGrantedBundles(infos);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      lastError = describeError(e.code);
      Logger.e(SCOPE, `getUserGrantedEnabledBundles failed ${lastError}`);
    }

    Logger.i(SCOPE, `snapshot subscribed=${subscribed} userGranted=${userGranted} granted=${bundles.length}`);
    return {
      subscribed: subscribed,
      subscribedAddrMasked: addrMasked,
      userGranted: userGranted,
      grantedBundles: bundles,
      lastError: lastError
    };
  }

  private static toGrantedBundles(
    infos: Array<notificationExtensionSubscription.GrantedBundleInfo> | undefined): GrantedBundle[] {
    const result: GrantedBundle[] = [];
    if (infos === undefined) {
      return result;
    }
    for (const info of infos) {
      const appIndex: number = info.appIndex;
      const appName: string = info.appName !== undefined ? info.appName : info.bundleName;
      result.push({
        bundleName: info.bundleName,
        appIndex: appIndex,
        appName: appName,
        key: grantKey(info.bundleName, appIndex)
      });
    }
    return result;
  }
}
