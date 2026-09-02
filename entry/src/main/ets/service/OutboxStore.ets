import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';
import { Database, TABLE_OUTBOX } from './Database';

const SCOPE: string = 'OutboxStore';

/** 队列上限。超出后丢弃最旧的，防止长时间断网把库撑爆。 */
export const OUTBOX_MAX: number = 100;
/** 有效期 30 分钟。超过这个时间的通知再送达已无意义，只会打扰。 */
export const OUTBOX_TTL_MS: number = 30 * 60 * 1000;
/** 每轮最多发送条数，避免一次唤醒里长时间占用网络与唤醒锁。 */
export const DRAIN_BATCH: number = 10;

export enum OutboxKind {
  PUSH = 0,
  CANCEL = 1
}

export interface OutboxRecord {
  eventId: string;
  kind: OutboxKind;
  /** 撤回消息为空串——它是控制消息，不携带任何正文。 */
  ciphertext: string;
  iv: string;
  createdAt: number;
  expiresAt: number;
  attempts: number;
}

export class OutboxStore {
  /**
   * 入队或覆盖。同一 eventId 走 upsert：
   * 通知被更新时（同一条通知内容变化）应该覆盖旧密文，而不是堆两条出去。
   */
  static async enqueue(context: common.Context, record: OutboxRecord): Promise<boolean> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      // 必须显式落成 number：ValuesBucket 只收 number/string/boolean/Uint8Array/null，
      // 直接塞枚举成员（哪怕调了 valueOf）过不了参数校验，整条 insert 会被以 401 拒掉。
      const kindValue: number = record.kind === OutboxKind.CANCEL ? 1 : 0;
      const values: relationalStore.ValuesBucket = {
        'event_id': record.eventId,
        'kind': kindValue,
        'ciphertext': record.ciphertext,
        'iv': record.iv,
        'created_at': record.createdAt,
        'expires_at': record.expiresAt,
        'attempts': record.attempts
      };
      await store.insert(TABLE_OUTBOX, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      await OutboxStore.enforceLimit(store);
      return true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `enqueue failed code=${e.code}`);
      return false;
    }
  }

  /** 取一批未过期的待发记录，最旧的优先，保证投递顺序接近通知发生顺序。 */
  static async takePending(context: common.Context, limit: number): Promise<OutboxRecord[]> {
    const records: OutboxRecord[] = [];
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_OUTBOX);
      predicates.greaterThan('expires_at', Date.now());
      predicates.orderByAsc('created_at');
      predicates.limitAs(limit);
      const result: relationalStore.ResultSet = await store.query(predicates);
      try {
        while (result.goToNextRow()) {
          records.push({
            eventId: result.getString(result.getColumnIndex('event_id')),
            kind: result.getLong(result.getColumnIndex('kind')) === 1
              ? OutboxKind.CANCEL : OutboxKind.PUSH,
            ciphertext: result.getString(result.getColumnIndex('ciphertext')),
            iv: result.getString(result.getColumnIndex('iv')),
            createdAt: result.getLong(result.getColumnIndex('created_at')),
            expiresAt: result.getLong(result.getColumnIndex('expires_at')),
            attempts: result.getLong(result.getColumnIndex('attempts'))
          });
        }
      } finally {
        result.close();
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `takePending failed code=${e.code}`);
    }
    return records;
  }

  static async exists(context: common.Context, eventId: string): Promise<boolean> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_OUTBOX);
      predicates.equalTo('event_id', eventId);
      const result: relationalStore.ResultSet = await store.query(predicates, ['event_id']);
      try {
        return result.rowCount > 0;
      } finally {
        result.close();
      }
    } catch (err) {
      return false;
    }
  }

  /** 投递成功后删除。计划要求不保留已发送通知的历史。 */
  static async remove(context: common.Context, eventId: string): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_OUTBOX);
      predicates.equalTo('event_id', eventId);
      await store.delete(predicates);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `remove failed code=${e.code}`);
    }
  }

  static async bumpAttempts(context: common.Context, eventId: string, attempts: number): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_OUTBOX);
      predicates.equalTo('event_id', eventId);
      const values: relationalStore.ValuesBucket = { 'attempts': attempts };
      await store.update(values, predicates);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `bumpAttempts failed code=${e.code}`);
    }
  }

  /** 清掉已过期的记录，返回清理条数。 */
  static async pruneExpired(context: common.Context): Promise<number> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_OUTBOX);
      predicates.lessThanOrEqualTo('expires_at', Date.now());
      const removed: number = await store.delete(predicates);
      if (removed > 0) {
        Logger.i(SCOPE, `pruneExpired removed=${removed}`);
      }
      return removed;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `pruneExpired failed code=${e.code}`);
      return 0;
    }
  }

  static async depth(context: common.Context): Promise<number> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const result: relationalStore.ResultSet =
        await store.query(new relationalStore.RdbPredicates(TABLE_OUTBOX), ['event_id']);
      try {
        return result.rowCount;
      } finally {
        result.close();
      }
    } catch (err) {
      return 0;
    }
  }

  /**
   * 超出上限时丢弃最旧的若干条。
   *
   * 刻意不用 `DELETE ... WHERE id IN (SELECT ... LIMIT ?)`：那种写法一旦参数没绑上，
   * SQLite 会把 LIMIT 当成无限制，子查询返回全表，整个队列被删光——
   * 断网攒下的消息会在越过上限的瞬间全部蒸发。这里改用谓词接口，不碰 SQL 参数绑定。
   */
  private static async enforceLimit(store: relationalStore.RdbStore): Promise<void> {
    const countResult: relationalStore.ResultSet =
      await store.query(new relationalStore.RdbPredicates(TABLE_OUTBOX), ['event_id']);
    let total: number = 0;
    try {
      total = countResult.rowCount;
    } finally {
      countResult.close();
    }
    if (total <= OUTBOX_MAX) {
      return;
    }

    // 取按时间倒序的第 OUTBOX_MAX 条，它的时间戳就是保留边界。
    const boundary: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_OUTBOX);
    boundary.orderByDesc('created_at');
    boundary.limitAs(OUTBOX_MAX);
    const boundaryResult: relationalStore.ResultSet = await store.query(boundary, ['created_at']);
    let cutoff: number = 0;
    try {
      if (boundaryResult.rowCount >= OUTBOX_MAX && boundaryResult.goToLastRow()) {
        cutoff = boundaryResult.getLong(boundaryResult.getColumnIndex('created_at'));
      }
    } finally {
      boundaryResult.close();
    }
    if (cutoff <= 0) {
      return;
    }

    const stale: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_OUTBOX);
    stale.lessThan('created_at', cutoff);
    const removed: number = await store.delete(stale);
    Logger.w(SCOPE, `enforceLimit dropped=${removed} total=${total}`);
  }
}
