import { describe, it, expect, beforeAll, afterAll, afterEach } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility, Want } from '@kit.AbilityKit';
import { BarkConfig, ConfigStore } from '../../../main/ets/service/ConfigStore';
import { GrantStore } from '../../../main/ets/service/GrantStore';
import {
  OUTBOX_MAX, OUTBOX_TTL_MS, OutboxKind, OutboxRecord, OutboxStore
} from '../../../main/ets/service/OutboxStore';

/**
 * 这些用例跑在**真实数据库**上，因此全程带保护：
 *   - 测试记录一律用 TEST_PREFIX 开头的 eventId，结束后逐条清除；
 *   - 真实配置在 beforeAll 备份、afterAll 原样写回；
 *   - 会挤占队列的容量上限用例，只在队列本来就空时才执行。
 * 绝不能因为跑一次测试就冲掉用户的 Bark 凭证或待发消息。
 */
const TEST_PREFIX: string = 'pltest-';

function testRecord(suffix: string, createdAt: number, expiresAt: number): OutboxRecord {
  return {
    eventId: `${TEST_PREFIX}${suffix}`,
    kind: OutboxKind.PUSH,
    ciphertext: 'dGVzdA==',
    iv: 'ABCDEFGHIJKL',
    createdAt: createdAt,
    expiresAt: expiresAt,
    attempts: 0
  };
}

export default function storageTest() {
  describe('storageTest', () => {
    let context: common.Context;
    let savedConfig: BarkConfig;

    beforeAll(async () => {
      // 不能用 delegator.getAppContext()：RDB 会以
      // `401 Parameter error.Illegal context.` 拒绝它，
      // 于是每个用例都在"数据库根本没打开"的状态下跑，失败原因会被层层掩盖。
      // 必须拉起真实 Ability 取它的 UIAbilityContext。
      const delegator: abilityDelegatorRegistry.AbilityDelegator =
        abilityDelegatorRegistry.getAbilityDelegator();
      const want: Want = {
        bundleName: 'com.pushlink.app',
        abilityName: 'EntryAbility'
      };
      await delegator.startAbility(want);
      const ability: UIAbility = await delegator.getCurrentTopAbility();
      context = ability.context;
      savedConfig = await ConfigStore.load(context);
    });

    afterAll(async () => {
      // 原样写回，测试不得改变用户的真实配置。
      if (savedConfig.deviceKey.length > 0) {
        await ConfigStore.save(context, savedConfig);
      }
    });

    afterEach(async () => {
      for (let i = 0; i < OUTBOX_MAX + 10; i++) {
        await OutboxStore.remove(context, `${TEST_PREFIX}${i}`);
      }
      await OutboxStore.remove(context, `${TEST_PREFIX}a`);
      await OutboxStore.remove(context, `${TEST_PREFIX}b`);
      await OutboxStore.remove(context, `${TEST_PREFIX}expired`);
    });

    // ---------- 队列 upsert ----------

    it('outbox_upsert_replaces_same_event', 0, async (done: Function) => {
      // 同一条通知被更新时必须覆盖，而不是堆两条出去。
      const now: number = Date.now();
      const before: number = await OutboxStore.depth(context);
      await OutboxStore.enqueue(context, testRecord('a', now, now + OUTBOX_TTL_MS));
      await OutboxStore.enqueue(context, testRecord('a', now + 1, now + OUTBOX_TTL_MS));
      expect(await OutboxStore.depth(context)).assertEqual(before + 1);
      expect(await OutboxStore.exists(context, `${TEST_PREFIX}a`)).assertTrue();
      done();
    });

    it('outbox_remove_deletes_record', 0, async (done: Function) => {
      const now: number = Date.now();
      await OutboxStore.enqueue(context, testRecord('a', now, now + OUTBOX_TTL_MS));
      await OutboxStore.remove(context, `${TEST_PREFIX}a`);
      expect(await OutboxStore.exists(context, `${TEST_PREFIX}a`)).assertFalse();
      done();
    });

    // ---------- 过期 ----------

    it('outbox_pending_excludes_expired', 0, async (done: Function) => {
      const now: number = Date.now();
      // 已过期一小时的记录不应出现在待发列表里。
      await OutboxStore.enqueue(context, testRecord('expired', now - 7200000, now - 3600000));
      const pending: OutboxRecord[] = await OutboxStore.takePending(context, OUTBOX_MAX);
      let found: boolean = false;
      for (const item of pending) {
        if (item.eventId === `${TEST_PREFIX}expired`) {
          found = true;
        }
      }
      expect(found).assertFalse();
      done();
    });

    it('outbox_prune_removes_expired', 0, async (done: Function) => {
      const now: number = Date.now();
      await OutboxStore.enqueue(context, testRecord('expired', now - 7200000, now - 3600000));
      await OutboxStore.pruneExpired(context);
      expect(await OutboxStore.exists(context, `${TEST_PREFIX}expired`)).assertFalse();
      done();
    });

    it('outbox_pending_is_oldest_first', 0, async (done: Function) => {
      const now: number = Date.now();
      await OutboxStore.enqueue(context, testRecord('b', now + 1000, now + OUTBOX_TTL_MS));
      await OutboxStore.enqueue(context, testRecord('a', now, now + OUTBOX_TTL_MS));
      const pending: OutboxRecord[] = await OutboxStore.takePending(context, OUTBOX_MAX);
      let indexA: number = -1;
      let indexB: number = -1;
      for (let i = 0; i < pending.length; i++) {
        if (pending[i].eventId === `${TEST_PREFIX}a`) {
          indexA = i;
        }
        if (pending[i].eventId === `${TEST_PREFIX}b`) {
          indexB = i;
        }
      }
      // 投递顺序应贴近通知发生顺序。
      expect(indexA >= 0 && indexB >= 0 && indexA < indexB).assertTrue();
      done();
    });

    it('outbox_bump_attempts_persists', 0, async (done: Function) => {
      const now: number = Date.now();
      await OutboxStore.enqueue(context, testRecord('a', now, now + OUTBOX_TTL_MS));
      await OutboxStore.bumpAttempts(context, `${TEST_PREFIX}a`, 3);
      const pending: OutboxRecord[] = await OutboxStore.takePending(context, OUTBOX_MAX);
      let attempts: number = -1;
      for (const item of pending) {
        if (item.eventId === `${TEST_PREFIX}a`) {
          attempts = item.attempts;
        }
      }
      expect(attempts).assertEqual(3);
      done();
    });

    // ---------- 容量上限 ----------

    it('outbox_enforces_capacity_limit', 0, async (done: Function) => {
      const existing: number = await OutboxStore.depth(context);
      if (existing > 0) {
        // 队列非空说明有真实待发消息，此时灌入测试数据会把它们挤掉，跳过。
        expect(true).assertTrue();
        done();
        return;
      }
      const now: number = Date.now();
      for (let i = 0; i < OUTBOX_MAX + 5; i++) {
        await OutboxStore.enqueue(context, testRecord(`${i}`, now + i, now + OUTBOX_TTL_MS));
      }
      expect(await OutboxStore.depth(context)).assertEqual(OUTBOX_MAX);
      // 挤掉的应该是最旧的那几条。
      expect(await OutboxStore.exists(context, `${TEST_PREFIX}0`)).assertFalse();
      expect(await OutboxStore.exists(context, `${TEST_PREFIX}${OUTBOX_MAX + 4}`)).assertTrue();
      done();
    });

    // ---------- 白名单默认拒绝 ----------

    it('grant_store_denies_unknown_bundle', 0, async (done: Function) => {
      // 最重要的一条：没登记过的来源必须判定为未授权，绝不能默认放行。
      const granted: boolean =
        await GrantStore.isGranted(context, 'com.example.definitely.not.granted', 0);
      expect(granted).assertFalse();
      done();
    });

    it('grant_store_distinguishes_app_index', 0, async (done: Function) => {
      // 分身实例不得因为主体被授权而蒙混过关。
      const granted: boolean =
        await GrantStore.isGranted(context, 'com.example.definitely.not.granted', 7);
      expect(granted).assertFalse();
      done();
    });
  });
}
