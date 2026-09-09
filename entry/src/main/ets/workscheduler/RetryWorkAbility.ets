import WorkSchedulerExtensionAbility from '@ohos.WorkSchedulerExtensionAbility';
import { workScheduler } from '@kit.BackgroundTasksKit';
import { Logger } from '../common/Logger';
import { ForwardPipeline } from '../service/ForwardPipeline';

const SCOPE: string = 'RetryWork';

/**
 * 队列的兜底重投。
 *
 * 转发链路原本只有三个投递时机：新通知到达、界面回到前台、有通知被撤回。
 * 中间若没有新通知、用户也没打开应用，投递失败的那条就一直躺在队列里，
 * 躺到 TTL 过期被清掉——消息就此丢失，这是「后台久了会漏推」的直接原因。
 *
 * 这个扩展由系统按 WorkInfo 的条件择机拉起（只在有网络时），
 * 拉起来只做一件事：把队列清空。任务由 ForwardPipeline 在队列非空时注册、
 * 清空后撤销，所以平时不占调度配额。
 */
export default class RetryWorkAbility extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    Logger.attachFile(this.context.filesDir, 'work');
    Logger.i(SCOPE, `work start id=${work.workId}`);
    // 这里拿到的是扩展自己的 context，可以直接用于打开加密库。
    ForwardPipeline.drain(this.context, undefined, 'work')
      .then(() => {
        Logger.i(SCOPE, 'drain finished');
      })
      .catch((err: Error) => {
        Logger.e(SCOPE, `drain failed: ${err.message}`);
      });
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    Logger.i(SCOPE, `work stop id=${work.workId}`);
  }
}
