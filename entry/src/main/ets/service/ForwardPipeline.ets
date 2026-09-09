import { common } from '@kit.AbilityKit';
import { runningLock } from '@kit.BasicServicesKit';
import { workScheduler } from '@kit.BackgroundTasksKit';
import { notificationExtensionSubscription } from '@kit.NotificationKit';
import { Logger, Redact } from '../common/Logger';
import { BODY_MAX_BYTES, composeTitle, shapeOf, truncateUtf8 } from '../common/TextUtil';
import { computeEventId } from '../crypto/EventId';
import { BarkCrypto } from '../crypto/BarkCrypto';
import { BarkClient, BarkPayload, BarkSendResult } from './BarkClient';
import { BarkConfig, ConfigStore, isConfigComplete } from './ConfigStore';
import { DiagnosticStore, Outcome } from './DiagnosticStore';
import { GrantStore } from './GrantStore';
import { GrantedBundle } from '../common/Types';
import { DRAIN_BATCH, OUTBOX_TTL_MS, OutboxKind, OutboxRecord, OutboxStore } from './OutboxStore';

const SCOPE: string = 'Pipeline';
/**
 * 唤醒锁最长持有时间。
 *
 * **必须大于它要保护的工作的最坏耗时**，否则锁先到期、进程被挂起，
 * 请求断在半路——曾经取 10s，而单条通知最坏就要 2 次 send × 8s = 16s，
 * 锁比工作还短。症状是应用在后台久了就转发不出去，
 * 消息积在队列里、等下次打开应用才补投出去。
 *
 * 现在按「单条最坏 16s + 前置 4 次数据库 I/O 与一次 AES 加密的余量」取 30s。
 * 一轮批量（DRAIN_BATCH=10）跑满仍会超时，但那是极端情况：
 * 超时后剩余记录留在队列里等下一次机会，不会丢。
 */
const LOCK_TIMEOUT_MS: number = 30000;

/** 兜底重投任务的固定 id。同一个 id 反复 start 会覆盖，不会堆积出多个任务。 */
const RETRY_WORK_ID: number = 1;
/** 期望的重投间隔。系统按自己的节奏调度，这只是个愿望值，不是保证。 */
const RETRY_CYCLE_MS: number = 20 * 60 * 1000;
/** 包名。WorkInfo 要求显式给出，取不到 context 时也得能拼出任务描述。 */
const BUNDLE_NAME: string = 'com.pushlink.app';

/**
 * 是否向 Bark 发送撤回请求。
 *
 * **暂时关闭**：Bark 在加密模式下不认这个删除指令，两种发法都只制造垃圾通知——
 *   明文发 `id=xxx&delete=1`：请求里没有 ciphertext，Bark 判为解密失败，
 *     推一条 "Decryption Failed"；
 *   加密发 `{"id":..,"delete":"1"}`：能解开了，但载荷里没有 title/body，
 *     于是显示成 "Empty Message"。
 * 实测撤回比推送还频繁（29 : 23），所以这些提示才会没完没了地自己冒出来。
 *
 * 撤回本身只是让 iPhone 上的旧通知自动消失，属于锦上添花；转发才是主线。
 * 等查清 Bark 加密模式下删除接口的正确形态，把这里打开即可，其余代码都留着。
 *
 * 注意：队列里**还没发出去**的通知照常直接删除，那条路不联网、也不受此开关影响。
 */
const CANCEL_REMOTE: boolean = false;

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

  /**
   * 兜底重投任务的描述。
   *
   * 只在有网络时唤醒——没网时拉起来也是白跑一趟，还白耗一次调度配额。
   * isPersisted 让它在重启后依然有效：队列是落盘的，重启后照样需要有人来投。
   */
  private static retryWork(): workScheduler.WorkInfo {
    return {
      workId: RETRY_WORK_ID,
      bundleName: BUNDLE_NAME,
      abilityName: 'RetryWorkAbility',
      networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
      isRepeat: true,
      repeatCycleTime: RETRY_CYCLE_MS,
      isPersisted: true
    };
  }

  /**
   * 队列里还有货就挂上重投任务，清空了就撤掉。
   *
   * 不常驻是有意的：常驻会持续占用系统的调度配额，而绝大多数时候队列是空的。
   * 注册失败不抛——它只是兜底，主路径（新通知到达、回到前台）照常工作。
   */
  private static async syncRetrySchedule(context: common.Context): Promise<void> {
    let depth: number = -1;
    try {
      depth = await OutboxStore.depth(context);
      if (depth === 0) {
        try {
          workScheduler.stopWork(ForwardPipeline.retryWork(), true);
          Logger.i(SCOPE, 'retry disarmed, queue empty');
        } catch (err) {
          // 任务本来就没注册时 stopWork 抛 9700004（workId do not exist），
          // 这是正常状态不是故障。单独接住，别让它污染真正的失败日志。
          Logger.i(SCOPE, 'retry already absent, queue empty');
        }
        return;
      }
      workScheduler.startWork(ForwardPipeline.retryWork());
      Logger.i(SCOPE, `retry armed depth=${depth}`);
    } catch (err) {
      const e: Error = err as Error;
      // 9700005 是「任务已存在」——上一轮挂上了还没跑完，这轮又来挂。
      // 目标本来就是「有任务盯着」，已经有了就是成功，不该记成故障。
      if (e.message.indexOf('9700005') >= 0) {
        Logger.i(SCOPE, `retry already armed depth=${depth}`);
        return;
      }
      Logger.e(SCOPE, `retry arm FAILED depth=${depth} msg=${e.message}`);
      return;
    }
    // startWork 不抛异常不代表系统收下了。回查一次，
    // 这是判断「兜底任务从没跑过」到底是没注册上、还是注册了没被调度的唯一依据。
    try {
      const info: workScheduler.WorkInfo = await workScheduler.getWorkStatus(RETRY_WORK_ID);
      Logger.i(SCOPE, `retry verified id=${info.workId} repeat=${info.isRepeat} ` +
        `cycle=${info.repeatCycleTime} net=${info.networkType} persist=${info.isPersisted}`);
    } catch (err) {
      const e: Error = err as Error;
      Logger.e(SCOPE, `retry NOT registered after startWork: ${e.message}`);
    }
  }

  /**
   * 申请一把后台唤醒锁。拿不到就返回 undefined，调用方照常往下走——
   * 前台场景本来也不需要它，不能因为取不到锁就不投递。
   */
  private static async acquireLock(tag: string): Promise<runningLock.RunningLock | undefined> {
    try {
      const lock: runningLock.RunningLock =
        await runningLock.create(tag, runningLock.RunningLockType.BACKGROUND);
      lock.hold(LOCK_TIMEOUT_MS);
      return lock;
    } catch (err) {
      Logger.w(SCOPE, `running lock unavailable for ${tag}`);
      return undefined;
    }
  }

  private static releaseLock(lock: runningLock.RunningLock | undefined): void {
    if (lock === undefined) {
      return;
    }
    try {
      lock.unhold();
    } catch (err) {
      Logger.w(SCOPE, 'unhold failed');
    }
  }

  /**
   * 处理链的尾巴。每条通知排在前一条之后，不并发。
   *
   * 扩展的 onReceiveMessage 是同步方法、甩出 Promise 就返回，多条通知涌进来时
   * 加密流程会交错执行。而 cryptoFramework 的 init / update / doFinal 三步之间
   * 夹着 await，底下是 native 实现——交错时怀疑会串味，A 的 authTag 配到 B 的密文上。
   * GCM 的 tag 一旦对不上，iPhone 端解密整条失败，而 Bark 服务端照样返回 200，
   * 应用这边完全看不出异常（诊断页显示「已送达」，人却收到 Decryption Failed）。
   *
   * 排队的代价可以忽略：通知本来就是零星到达的，串起来处理不会积压。
   */
  private static chain: Promise<void> = Promise.resolve();

  /**
   * 收到一条通知。
   *
   * 整条链（4 次数据库 I/O + AES 加密 + 网络投递）都在锁的保护下跑完。
   * 扩展的 onReceiveMessage 甩出这个 Promise 就返回，系统随时可以回收进程——
   * 锁是这条链唯一的护栏，所以从第一步就要持有，
   * 不能等到 drain 里确认有待发记录之后才申请。
   */
  static async handleNotification(context: common.Context,
    info: notificationExtensionSubscription.NotificationInfo): Promise<void> {
    const previous: Promise<void> = ForwardPipeline.chain;
    let release: () => void = () => {};
    ForwardPipeline.chain = new Promise<void>((resolve: () => void) => {
      release = resolve;
    });
    // 前一条即使抛错也不能把后面全卡住，所以这里吞掉它的异常。
    await previous;

    // 锁在排队之后才申请：排队期间占着锁没有意义，还挤占系统配额。
    const lock: runningLock.RunningLock | undefined =
      await ForwardPipeline.acquireLock('PushLink-forward');
    try {
      await ForwardPipeline.forward(context, info);
    } finally {
      ForwardPipeline.releaseLock(lock);
      release();
    }
  }

  /** 白名单过滤 → 截断 → 加密 → 入队 → 触发投递。锁由 handleNotification 持有。 */
  private static async forward(context: common.Context,
    info: notificationExtensionSubscription.NotificationInfo): Promise<void> {
    const started: number = Date.now();
    const bundleName: string = info.bundleName;
    const eventId: string = await computeEventId(info.hashCode);

    // 默认拒绝：不在系统授权白名单里的来源一律丢弃，绝不外发。
    // 顺带取回应用名用作标题前缀，不额外查一次库。
    const granted: GrantedBundle | undefined =
      await GrantStore.findGranted(context, bundleName, info.appIndex);
    if (granted === undefined) {
      Logger.i(SCOPE, `drop not-granted bundle=${bundleName} appIndex=${info.appIndex}`);
      await DiagnosticStore.record(context, {
        eventId: eventId,
        bundleName: bundleName,
        outcome: Outcome.DROPPED,
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
        outcome: Outcome.FAILED,
        elapsedMs: Date.now() - started,
        detailCode: 0,
        createdAt: Date.now()
      });
      return;
    }

    // 优先用回调自带的应用名，缺失时回落到白名单里系统记录的那个。
    const appLabel: string = info.appName !== undefined && info.appName.length > 0
      ? info.appName
      : granted.appName;
    const payload: BarkPayload = {
      // 标题带上来源，如「[微信] 张三：晚上吃什么」——Bark 显示不了应用图标，
      // 前缀是不牺牲隐私的辨识度方案。group 与 title 都在加密内容里，服务端看不到。
      title: composeTitle(appLabel, info.content.title),
      body: truncateUtf8(info.content.text, BODY_MAX_BYTES),
      // 用应用名分组，iPhone 上按应用归类时可读性比包名好。
      group: appLabel.length > 0 ? appLabel : bundleName,
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
      // 记上密文长度：出现「诊断页显示已送达、手机却报解密失败」时，
      // 靠 eventId 就能从这里反查那条的规模，不必再拿时间去猜。
      Logger.i(SCOPE, `queued event=${eventId} bundle=${bundleName} ` +
        `title=${Redact.len(payload.title)} body=${Redact.len(payload.body)} ` +
        `cipher=${ciphertext.length} iv=${iv}`);
      // 只记形状不记内容：出现「发送成功但对端解不开」时，
      // 用它对比成功与失败两组样本，看差异是不是落在换行、控制字符或代理对上。
      Logger.i(SCOPE, `shape event=${eventId} title[${shapeOf(payload.title)}] ` +
        `body[${shapeOf(payload.body)}] group[${shapeOf(payload.group)}] ` +
        `json=${JSON.stringify(payload).length}`);
      // 把刚读到的配置直接传下去，省掉 drain 里的重复读取。
      // 连续通知场景下这能把加密库的读次数减半。
      await ForwardPipeline.drain(context, config, 'notify');
      return;
    } catch (err) {
      const e: Error = err as Error;
      Logger.e(SCOPE, `encrypt failed bundle=${bundleName}: ${e.message}`);
      await DiagnosticStore.record(context, {
        eventId: eventId,
        bundleName: bundleName,
        outcome: Outcome.FAILED,
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
      if (!CANCEL_REMOTE) {
        Logger.i(SCOPE, `cancel skipped(remote off) event=${eventId}`);
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
    await ForwardPipeline.drain(context, undefined, 'cancel');
  }

  /**
   * 清空队列。取最多 DRAIN_BATCH 条，整轮持一个唤醒锁。
   * 每条失败后立即重试一次，仍失败就留在队列里等下次机会。
   */
  static async drain(context: common.Context, known?: BarkConfig, caller?: string): Promise<void> {
    // 记来源：后台漏推时要能分清这一轮是通知触发的、界面触发的，还是兜底任务拉起来的。
    const from: string = caller !== undefined ? caller : 'unknown';
    Logger.i(SCOPE, `drain enter from=${from} busy=${ForwardPipeline.draining}`);
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
          // 从 handleNotification 进来时外层已经有一把，这里这把是给
          // 从界面直接触发 drain 的路径用的；两把并存无妨。
          if (lock === undefined) {
            lock = await ForwardPipeline.acquireLock('PushLink-drain');
          }

          for (const record of pending) {
            await ForwardPipeline.deliver(context, config, record);
          }
        }
      } while (ForwardPipeline.rerunRequested && round < ForwardPipeline.MAX_ROUNDS);
    } finally {
      ForwardPipeline.releaseLock(lock);
      ForwardPipeline.draining = false;
      // 放在最后：这一轮之后队列是空是满，决定了还要不要留着兜底任务。
      await ForwardPipeline.syncRetrySchedule(context);
    }
  }

  private static async deliver(context: common.Context, config: BarkConfig,
    record: OutboxRecord): Promise<void> {
    // 不再立即重试。它让单条最坏耗时翻倍到 16s，在后台是实打实的负担，
    // 而失败本来就会留在队列里——现在有了兜底任务，下一轮重投是有保障的，
    // 不必赌这一次。
    const result: BarkSendResult = await ForwardPipeline.send(config, record);

    if (result.ok) {
      Logger.i(SCOPE, `sent event=${record.eventId} kind=${record.kind} ` +
        `cipher=${record.ciphertext.length} elapsed=${result.elapsedMs}`);
      await OutboxStore.remove(context, record.eventId);
      await DiagnosticStore.record(context, {
        eventId: record.eventId,
        bundleName: '',
        outcome: record.kind === OutboxKind.CANCEL
          ? Outcome.CANCELLED : Outcome.SENT,
        elapsedMs: result.elapsedMs,
        detailCode: 0,
        createdAt: Date.now()
      });
      return;
    }

    Logger.w(SCOPE, `deliver failed event=${record.eventId} kind=${record.kind} ` +
      `attempts=${record.attempts} http=${result.httpCode} bark=${result.barkCode} ` +
      `elapsed=${result.elapsedMs} msg=${result.message}`);
    await OutboxStore.bumpAttempts(context, record.eventId, record.attempts + 2);
    await DiagnosticStore.record(context, {
      eventId: record.eventId,
      bundleName: '',
      outcome: Outcome.QUEUED,
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
        outcome: Outcome.EXPIRED,
        elapsedMs: 0,
        detailCode: 0,
        createdAt: Date.now()
      });
    }
  }
}
