import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';
import { Database, TABLE_DIAGNOSTICS } from './Database';

const SCOPE: string = 'Diagnostic';
/** 只留最近这么多条，够排查即可，不做历史归档。 */
const KEEP_ROWS: number = 60;

/**
 * 一次处理的结果分类。取值刻意做成可直接上屏的短标签。
 *
 * 用静态常量而不是 enum：枚举成员传给 ValuesBucket 或查询谓词时过不了
 * ArkTS 的参数校验（会以 401 拒绝），这里直接就是 string，没有转换环节。
 */
export class Outcome {
  static readonly SENT: string = '已送达';
  static readonly DROPPED: string = '未授权已丢弃';
  static readonly QUEUED: string = '已入队待重试';
  static readonly FAILED: string = '发送失败';
  static readonly EXPIRED: string = '超时未送达已丢弃';
  static readonly CANCELLED: string = '已撤回';
}

/**
 * 诊断记录。刻意不含标题、正文、密文、密钥——
 * 这张表的存在价值是"能排查"，不是"能还原通知"。
 */
export interface DiagnosticEntry {
  eventId: string;
  bundleName: string;
  outcome: string;
  elapsedMs: number;
  /** HTTP 或系统错误码，无错误时为 0。 */
  detailCode: number;
  createdAt: number;
}

export class DiagnosticStore {
  static async record(context: common.Context, entry: DiagnosticEntry): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const values: relationalStore.ValuesBucket = {
        'event_id': entry.eventId,
        'bundle_name': entry.bundleName,
        'outcome': entry.outcome,
        'elapsed_ms': entry.elapsedMs,
        'detail_code': entry.detailCode,
        'created_at': entry.createdAt
      };
      await store.insert(TABLE_DIAGNOSTICS, values);
      await DiagnosticStore.trim(store);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `record failed code=${e.code}`);
    }
  }

  /**
   * 只保留最近 KEEP_ROWS 条。与 OutboxStore.enforceLimit 同理，
   * 不用带 LIMIT 占位符的子查询——参数没绑上时 `NOT IN (全表)` 恒为空集，
   * 清理会静默失效，表只增不减。
   */
  private static async trim(store: relationalStore.RdbStore): Promise<void> {
    const boundary: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(TABLE_DIAGNOSTICS);
    boundary.orderByDesc('created_at');
    boundary.limitAs(KEEP_ROWS);
    const result: relationalStore.ResultSet = await store.query(boundary, ['created_at']);
    let cutoff: number = 0;
    try {
      if (result.rowCount >= KEEP_ROWS && result.goToLastRow()) {
        cutoff = result.getLong(result.getColumnIndex('created_at'));
      }
    } finally {
      result.close();
    }
    if (cutoff <= 0) {
      return;
    }
    const stale: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(TABLE_DIAGNOSTICS);
    stale.lessThan('created_at', cutoff);
    await store.delete(stale);
  }

  static async recent(context: common.Context, limit: number): Promise<DiagnosticEntry[]> {
    const entries: DiagnosticEntry[] = [];
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const predicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates(TABLE_DIAGNOSTICS);
      predicates.orderByDesc('created_at');
      predicates.limitAs(limit);
      const result: relationalStore.ResultSet = await store.query(predicates);
      try {
        while (result.goToNextRow()) {
          entries.push({
            eventId: result.getString(result.getColumnIndex('event_id')),
            bundleName: result.getString(result.getColumnIndex('bundle_name')),
            outcome: result.getString(result.getColumnIndex('outcome')),
            elapsedMs: result.getLong(result.getColumnIndex('elapsed_ms')),
            detailCode: result.getLong(result.getColumnIndex('detail_code')),
            createdAt: result.getLong(result.getColumnIndex('created_at'))
          });
        }
      } finally {
        result.close();
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `recent failed code=${e.code}`);
    }
    return entries;
  }

  /** 最近一次成功送达的时间戳，0 表示尚无成功记录。 */
  static async lastSuccessAt(context: common.Context): Promise<number> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const predicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates(TABLE_DIAGNOSTICS);
      predicates.equalTo('outcome', Outcome.SENT);
      predicates.orderByDesc('created_at');
      predicates.limitAs(1);
      const result: relationalStore.ResultSet = await store.query(predicates, ['created_at']);
      try {
        return result.goToFirstRow() ? result.getLong(result.getColumnIndex('created_at')) : 0;
      } finally {
        result.close();
      }
    } catch (err) {
      return 0;
    }
  }

  static async clear(context: common.Context): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      await store.delete(new relationalStore.RdbPredicates(TABLE_DIAGNOSTICS));
      Logger.i(SCOPE, 'clear ok');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `clear failed code=${e.code}`);
    }
  }
}
