import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/Logger';

const SCOPE: string = 'Database';

/**
 * 整库加密（encrypt: true），密钥由系统经 HUKS 托管、绑定本机与本应用。
 * 配合阶段 A 删除的备份扩展，Bark 凭证与待发队列都不会离开这台设备。
 *
 * UI 进程与 notificationSubscriber 扩展进程共用这一个库：
 * 阶段 B 实测扩展进程会被系统反复回收，任何内存状态都不可靠，
 * 白名单与投递队列必须落盘才能跨进程、跨重启存活。
 */
const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'pushlink.db',
  securityLevel: relationalStore.SecurityLevel.S3,
  encrypt: true
};

export const TABLE_CONFIG: string = 'bark_config';
export const TABLE_GRANTS: string = 'granted_bundles';
export const TABLE_OUTBOX: string = 'outbox';
export const TABLE_DIAGNOSTICS: string = 'diagnostics';

const DDL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${TABLE_CONFIG} (
    id INTEGER PRIMARY KEY,
    server TEXT NOT NULL,
    device_key TEXT NOT NULL,
    encrypt_key TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  // 系统授权白名单的本地快照。UI 每次前台刷新时整表重写，
  // 扩展进程只读；查不到的来源一律丢弃，绝不"默认放行"。
  `CREATE TABLE IF NOT EXISTS ${TABLE_GRANTS} (
    grant_key TEXT PRIMARY KEY,
    bundle_name TEXT NOT NULL,
    app_index INTEGER NOT NULL,
    app_name TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  // 待投递队列。只存尚未成功发出的，成功即删——不保留已发送通知的历史。
  // kind: 0=推送 1=撤回。撤回是控制消息，ciphertext 与 iv 为空串。
  `CREATE TABLE IF NOT EXISTS ${TABLE_OUTBOX} (
    event_id TEXT PRIMARY KEY,
    kind INTEGER NOT NULL,
    ciphertext TEXT NOT NULL,
    iv TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    attempts INTEGER NOT NULL
  )`,
  // 诊断记录只保留脱敏字段：事件 ID、来源包名、结果、耗时、错误码。
  // 不含标题、正文、密钥，也不含密文。
  `CREATE TABLE IF NOT EXISTS ${TABLE_DIAGNOSTICS} (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL,
    bundle_name TEXT NOT NULL,
    outcome TEXT NOT NULL,
    elapsed_ms INTEGER NOT NULL,
    detail_code INTEGER NOT NULL,
    created_at INTEGER NOT NULL
  )`
];

export class Database {
  private static store: relationalStore.RdbStore | undefined = undefined;
  private static opening: Promise<relationalStore.RdbStore> | undefined = undefined;

  /**
   * 取得库句柄。并发调用共享同一次打开操作——扩展进程可能在极短时间内
   * 收到多条通知并各自触发打开，重复建表会浪费且可能相互阻塞。
   */
  static async get(context: common.Context): Promise<relationalStore.RdbStore> {
    if (Database.store !== undefined) {
      return Database.store;
    }
    if (Database.opening === undefined) {
      Database.opening = Database.open(context);
    }
    return Database.opening;
  }

  private static async open(context: common.Context): Promise<relationalStore.RdbStore> {
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
    for (const statement of DDL) {
      await store.executeSql(statement);
    }
    Database.store = store;
    Logger.i(SCOPE, 'store ready');
    return store;
  }
}
