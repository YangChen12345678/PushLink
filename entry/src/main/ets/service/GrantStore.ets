import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';
import { GrantedBundle, grantKey } from '../common/Types';
import { Database, TABLE_GRANTS } from './Database';

const SCOPE: string = 'GrantStore';

/**
 * 系统授权白名单的本地快照。
 *
 * 唯一写入方是 UI 进程（每次前台刷新时整表重写），唯一读取方是扩展进程。
 * 语义是"默认拒绝"：查不到就丢弃，绝不因为表为空或读取失败而放行——
 * 那会导致全部应用的通知外发，是这个项目最严重的失效模式。
 */
export class GrantStore {
  /** 用系统返回的授权列表整表覆盖。整体事务，避免中途失败留下半张表。 */
  static async replaceAll(context: common.Context, bundles: GrantedBundle[]): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      store.beginTransaction();
      try {
        await store.delete(new relationalStore.RdbPredicates(TABLE_GRANTS));
        const now: number = Date.now();
        for (const item of bundles) {
          const values: relationalStore.ValuesBucket = {
            'grant_key': item.key,
            'bundle_name': item.bundleName,
            'app_index': item.appIndex,
            'app_name': item.appName,
            'updated_at': now
          };
          await store.insert(TABLE_GRANTS, values,
            relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        }
        store.commit();
        Logger.i(SCOPE, `replaceAll count=${bundles.length}`);
      } catch (err) {
        store.rollBack();
        throw err as Error;
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `replaceAll failed code=${e.code}`);
    }
  }

  /**
   * 查出白名单条目，未授权时返回 undefined。
   *
   * 顺带取回系统记录的应用名——投递时要用它做通知标题前缀。
   * 合并成一次查询而不是过滤后再查一次：连续通知场景下能省掉一半的库读取，
   * 而且这个名字来自系统授权列表，比什么都准。
   */
  static async findGranted(context: common.Context, bundleName: string,
    appIndex: number): Promise<GrantedBundle | undefined> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_GRANTS);
      predicates.equalTo('grant_key', grantKey(bundleName, appIndex));
      const result: relationalStore.ResultSet =
        await store.query(predicates, ['grant_key', 'bundle_name', 'app_index', 'app_name']);
      try {
        if (!result.goToFirstRow()) {
          return undefined;
        }
        return {
          bundleName: result.getString(result.getColumnIndex('bundle_name')),
          appIndex: result.getLong(result.getColumnIndex('app_index')),
          appName: result.getString(result.getColumnIndex('app_name')),
          key: result.getString(result.getColumnIndex('grant_key'))
        };
      } finally {
        result.close();
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `findGranted failed code=${e.code}`);
      return undefined;
    }
  }

  /**
   * 判断某个来源是否已授权。
   * 任何异常都返回 false——宁可漏发也不能误发。
   */
  static async isGranted(context: common.Context, bundleName: string, appIndex: number): Promise<boolean> {
    const found: GrantedBundle | undefined = await GrantStore.findGranted(context, bundleName, appIndex);
    return found !== undefined;
  }

  static async count(context: common.Context): Promise<number> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const result: relationalStore.ResultSet =
        await store.query(new relationalStore.RdbPredicates(TABLE_GRANTS), ['grant_key']);
      try {
        return result.rowCount;
      } finally {
        result.close();
      }
    } catch (err) {
      return 0;
    }
  }
}
