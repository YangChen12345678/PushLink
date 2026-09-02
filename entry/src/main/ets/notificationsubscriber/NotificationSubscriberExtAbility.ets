import { NotificationSubscriberExtensionAbility, notificationExtensionSubscription } from '@kit.NotificationKit';
import { Logger, Redact } from '../common/Logger';
import { ForwardPipeline } from '../service/ForwardPipeline';

const SCOPE: string = 'NotifExt';

/**
 * 通知订阅扩展。系统在本机发布/取消通知时拉起本扩展并回调。
 *
 * 这里只做记录与转交，全部业务在 ForwardPipeline 里：
 * 阶段 B 实测本进程会被系统反复回收（观察到 5 个不同进程号，实例计数每次归零），
 * 所以任何跨回调的状态都必须落在数据库上，不能放在成员变量里。
 *
 * 回调签名是同步的，而管线是异步的，因此这里只能 fire-and-forget，
 * 但必须自行兜住异常——未捕获的 Promise 拒绝会连累整个扩展进程。
 */
export default class NotificationSubscriberExtAbility extends NotificationSubscriberExtensionAbility {
  /** 仅本进程存活期间的计数，进程被回收即归零。用于日志对账，不参与业务。 */
  private receivedCount: number = 0;

  onReceiveMessage(notificationInfo: notificationExtensionSubscription.NotificationInfo): void {
    this.receivedCount++;

    // hashCode 是系统内部标识，不含用户内容，完整记录以便与 onCancelMessages 对账。
    // 标题与正文只记录长度，任何情况下都不落日志。
    Logger.i(SCOPE, `onReceiveMessage #${this.receivedCount} bundle=${notificationInfo.bundleName} ` +
      `appIndex=${notificationInfo.appIndex} hash=${notificationInfo.hashCode} ` +
      `title=${Redact.len(notificationInfo.content.title)} ` +
      `body=${Redact.len(notificationInfo.content.text)}`);

    ForwardPipeline.handleNotification(this.context, notificationInfo)
      .catch((err: Error) => {
        Logger.e(SCOPE, `handleNotification failed: ${err.message}`);
      });
  }

  onCancelMessages(hashCodes: Array<string>): void {
    Logger.i(SCOPE, `onCancelMessages count=${hashCodes.length} hashes=[${hashCodes.join(',')}]`);

    ForwardPipeline.handleCancel(this.context, hashCodes)
      .catch((err: Error) => {
        Logger.e(SCOPE, `handleCancel failed: ${err.message}`);
      });
  }

  onDestroy(): void {
    Logger.i(SCOPE, `onDestroy received=${this.receivedCount}`);
  }
}
