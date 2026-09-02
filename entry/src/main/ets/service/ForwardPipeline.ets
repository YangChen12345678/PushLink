import { common } from '@kit.AbilityKit';
import { runningLock } from '@kit.BasicServicesKit';
import { notificationExtensionSubscription } from '@kit.NotificationKit';
import { Logger, Redact } from '../common/Logger';
import { BODY_MAX_BYTES, TITLE_MAX_BYTES, truncateUtf8 } from '../common/TextUtil';
import { computeEventId } from '../crypto/EventId';
import { BarkCrypto } from '../crypto/BarkCrypto';
import { BarkClient, BarkPayload, BarkSendResult } from './BarkClient';
import { BarkConfig, ConfigStore, isConfigComplete } from './ConfigStore';
import { DiagnosticStore, Outcome } from './DiagnosticStore';
import { GrantStore } from './GrantStore';
import { DRAIN_BATCH, OUTBOX_TTL_MS, OutboxKind, OutboxRecord, OutboxStore } from './OutboxStore';

const SCOPE: string = 'Pipeline';
/** 唤醒锁最长持有时间。够跑完一轮批量投递，又不至于在异常时长期拖住系统。 */
const LOCK_TIMEOUT_MS: number = 10000;

/**
 * 从通知回调到 Bark 投递的完整编排。
 *
 * UI 进程和扩展进程都会调用这里：扩展在收到通知时调用，UI 在前台时补投积压。
 * 所有跨调用状态都在数据库里——阶段 B 实测扩展进程会被反复回收，内存里存不住东西。
 */
export class ForwardPipeline {
  /** 防止同一进程内并发投递。 */
  private static draining: boolean = false;
  /**
   * 投递期间有新的投递请求被挡下时置位，当前这轮结束后立刻再跑一轮。
   * 没有这个补偿的话，连续通知里最后一条的 drain 常常正好撞上前一轮，
   * 被跳过后就只能干等到用户打开 App 才补投。
   */
  private static rerunRequested: boolean = false;
  /** 兜底上限，避免持续涌入的通知把单次调用拖成不退出的循环。 */
  private static readonly MAX_ROUNDS: number = 5;

  /** 收到一条通知：白名单过滤 → 截断 → 加密 → 入队 → 触发投递。 */
  static async handleNotification(context: common.Context,
    info: notificationExtensionSubscription.NotificationInfo): Promise<void> {
    const started: number = Date.now();
    const bundleName: string = info.bundleName;
    const eventId: string = await computeEventId(info.hashCode);

    // 默认拒绝：不在系统授权白名单里的来源一律丢弃，绝不外发。
    const granted: boolean = await GrantStore.isGranted(context, bundleName, info.appIndex);
    if (!granted) {
      Logger.i(SCOPE, `drop not-granted bundle=${bundleName} appIndex=${info.appIndex}`);
      await DiagnosticStore.record(context, {
        eventId: eventId,
        bundleName: bundleName,
        outcome: Outcome.DROPPED.valueOf(),
        elapsedMs: Date.now() - started,
        detailCode: 0,
        createdAt: Date.now()
      });
      return;
    }

    const config: BarkConfig = await ConfigStore.load(context);
    if (!isConfigComplete(config)) {
      // 配置不全时入队也发不出去，直接丢弃并留痕，避免队列被永远发不掉的记录占满。
      Logger.w(SCOPE, `drop config-incomplete bundle=${bundleName}`);
      await DiagnosticStore.record(context, {
        eventId: eventId,
        bundleName: bundleName,
        outcome: Outcome.FAILED.valueOf(),
        elapsedMs: Date.now() - started,
        detailCode: 0,
        createdAt: Date.now()
      });
      return;
    }

    const payload: BarkPayload = {
      title: truncateUtf8(info.content.title, TITLE_MAX_BYTES),
      body: truncateUtf8(info.content.text, BODY_MAX_BYTES),
      // 用来源包名分组，iPhone 上可按应用归类。
      group: bundleName,
      level: 'active',
      action: 'none'
    };

    try {
      const iv: string = BarkCrypto.generateIv();
      const ciphertext: string = await BarkCrypto.encrypt(JSON.stringify(payload), config.encryptKey, iv);
      const now: number = Date.now();
      const record: OutboxRecord = {
        eventId: eventId,
        kind: OutboxKind.PUSH,
        ciphertext: ciphertext,
        iv: iv,
        createdAt: now,
        expiresAt: now + OUTBOX_TTL_MS,
        attempts: 0
      };
      // 同一 eventId 覆盖：通知被更新时替换旧密文，而不是发两条。
      await OutboxStore.enqueue(context, record);
      Logger.i(SCOPE, `queued event=${eventId} bundle=${bundleName} ` +
        `title=${Redact.len(payload.title)} body=${Redact.len(payload.body)}`);
      // 把刚读到的配置直接传下去，省掉 drain 里的重复读取。
      // 连续通知场景下这能把加密库的读次数减半。
      await ForwardPipeline.drain(context, config);
      return;
    } catch (err) {
      const e: Error = err as Error;
      Logger.e(SCOPE, `encrypt failed bundle=${bundleName}: ${e.message}`);
      await DiagnosticStore.record(context, {
        eventId: eventId,
        bundleName: bundleName,
        outcome: Outcome.FAILED.valueOf(),
        elapsedMs: Date.now() - started,
        detailCode: 0,
        createdAt: Date.now()
      });
      return;
    }
  }

  /** 收到取消：把对应的 Bark 消息撤回。 */
  static async handleCancel(context: common.Context, hashCodes: Array<string>): Promise<void> {
    for (const hashCode of hashCodes) {
      const eventId: string = await computeEventId(hashCode);
      // 还躺在队列里没发出去的，直接删掉即可——没送出去的消息不需要撤回，
      // 发一次无谓的 delete 请求反而会在 Bark 端制造一条不存在消息的操作。
      const pending: boolean = await OutboxStore.exists(context, eventId);
      if (pending) {
        await OutboxStore.remove(context, eventId);
        Logger.i(SCOPE, `cancel removed-pending event=${eventId}`);
        continue;
      }
      const now: number = Date.now();
      await OutboxStore.enqueue(context, {
        eventId: eventId,
        kind: OutboxKind.CANCEL,
        ciphertext: '',
        iv: '',
        createdAt: now,
        expiresAt: now + OUTBOX_TTL_MS,
        attempts: 0
      });
      Logger.i(SCOPE, `cancel queued event=${eventId}`);
    }
    await ForwardPipeline.drain(context);
  }

  /**
   * 清空队列。取最多 DRAIN_BATCH 条，整轮持一个唤醒锁。
   * 每条失败后立即重试一次，仍失败就留在队列里等下次机会。
   */
  static async drain(context: common.Context, known?: BarkConfig): Promise<void> {
    if (ForwardPipeline.draining) {
      // 不能直接丢弃：被挡下的这次可能是队列里最后一条的唯一投递机会。
      ForwardPipeline.rerunRequested = true;
      Logger.i(SCOPE, 'drain deferred, rerun requested');
      return;
    }
    ForwardPipeline.draining = true;
    let lock: runningLock.RunningLock | undefined = undefined;
    try {
      let round: number = 0;
      do {
        ForwardPipeline.rerunRequested = false;
        round++;
        await ForwardPipeline.expireOverdue(context);

        const pending: OutboxRecord[] = await OutboxStore.takePending(context, DRAIN_BATCH);
        if (pending.length > 0) {
          // 调用方刚读过就直接复用，避免每条通知重复读一次加密库。
          const config: BarkConfig = known !== undefined ? known : await ConfigStore.load(context);
          if (!isConfigComplete(config)) {
            Logger.w(SCOPE, 'drain aborted, config incomplete');
            break;
          }

          // 息屏时若不持锁，请求可能在途中被挂起。整轮共用一把，不重复申请。
          if (lock === undefined) {
            try {
              lock = await runningLock.create('PushLink-drain', runningLock.RunningLockType.BACKGROUND);
              lock.hold(LOCK_TIMEOUT_MS);
            } catch (err) {
              // 拿不到锁不阻断投递，前台场景本来也不需要它。
              Logger.w(SCOPE, 'running lock unavailable');
              lock = undefined;
            }
          }

          for (const record of pending) {
            await ForwardPipeline.deliver(context, config, record);
          }
        }
      } while (ForwardPipeline.rerunRequested && round < ForwardPipeline.MAX_ROUNDS);
    } finally {
      if (lock !== undefined) {
        try {
          lock.unhold();
        } catch (err) {
          Logger.w(SCOPE, 'unhold failed');
        }
      }
      ForwardPipeline.draining = false;
    }
  }

  private static async deliver(context: common.Context, config: BarkConfig,
    record: OutboxRecord): Promise<void> {
    let result: BarkSendResult = await ForwardPipeline.send(config, record);
    if (!result.ok) {
      // 立即重试一次：多数失败是瞬时的网络抖动，等下一轮唤醒代价太大。
      result = await ForwardPipeline.send(config, record);
    }

    if (result.ok) {
      await OutboxStore.remove(context, record.eventId);
      await DiagnosticStore.record(context, {
        eventId: record.eventId,
        bundleName: '',
        outcome: record.kind === OutboxKind.CANCEL
          ? Outcome.CANCELLED.valueOf() : Outcome.SENT.valueOf(),
        elapsedMs: result.elapsedMs,
        detailCode: 0,
        createdAt: Date.now()
      });
      return;
    }

    await OutboxStore.bumpAttempts(context, record.eventId, record.attempts + 2);
    await DiagnosticStore.record(context, {
      eventId: record.eventId,
      bundleName: '',
      outcome: Outcome.QUEUED.valueOf(),
      elapsedMs: result.elapsedMs,
      detailCode: result.httpCode !== 0 ? result.httpCode : result.barkCode,
      createdAt: Date.now()
    });
  }

  private static async send(config: BarkConfig, record: OutboxRecord): Promise<BarkSendResult> {
    if (record.kind === OutboxKind.CANCEL) {
      return BarkClient.deleteMessage(config, record.eventId);
    }
    return BarkClient.pushCiphertext(config, record.ciphertext, record.iv, record.eventId);
  }

  /** 过期记录在清理前留一条诊断，否则用户只会看到"消息凭空没了"。 */
  private static async expireOverdue(context: common.Context): Promise<void> {
    const removed: number = await OutboxStore.pruneExpired(context);
    if (removed > 0) {
      await DiagnosticStore.record(context, {
        eventId: `${removed} 条`,
        bundleName: '',
        outcome: Outcome.EXPIRED.valueOf(),
        elapsedMs: 0,
        detailCode: 0,
        createdAt: Date.now()
      });
    }
  }
}
