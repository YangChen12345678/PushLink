import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger, Redact } from '../common/Logger';
import { Database, TABLE_CONFIG } from './Database';

const SCOPE: string = 'ConfigStore';
const ROW_ID: number = 1;

export const DEFAULT_BARK_SERVER: string = 'https://api.day.app';

export interface BarkConfig {
  /** Bark 服务地址，默认官方 https://api.day.app。 */
  server: string;
  /** Bark Device Key。 */
  deviceKey: string;
  /** 32 个 ASCII 字符的 AES-256 加密 Key，必须与 Bark App 里配置的完全一致。 */
  encryptKey: string;
}

export function emptyBarkConfig(): BarkConfig {
  return { server: DEFAULT_BARK_SERVER, deviceKey: '', encryptKey: '' };
}

export function isConfigComplete(config: BarkConfig): boolean {
  return config.server.length > 0 && config.deviceKey.length > 0 && config.encryptKey.length === 32;
}

export class ConfigStore {
  /** 读取配置。从未保存过时返回带默认服务地址的空配置。 */
  static async load(context: common.Context): Promise<BarkConfig> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_CONFIG);
      predicates.equalTo('id', ROW_ID);
      const result: relationalStore.ResultSet =
        await store.query(predicates, ['server', 'device_key', 'encrypt_key']);
      try {
        if (!result.goToFirstRow()) {
          return emptyBarkConfig();
        }
        const config: BarkConfig = {
          server: result.getString(result.getColumnIndex('server')),
          deviceKey: result.getString(result.getColumnIndex('device_key')),
          encryptKey: result.getString(result.getColumnIndex('encrypt_key'))
        };
        Logger.i(SCOPE, `load ok server=${config.server} deviceKey=${Redact.len(config.deviceKey)} ` +
          `encryptKey=${Redact.len(config.encryptKey)}`);
        return config;
      } finally {
        result.close();
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `load failed code=${e.code}`);
      return emptyBarkConfig();
    }
  }

  /** 覆盖保存配置。整表只有 id=1 这一行。 */
  static async save(context: common.Context, config: BarkConfig): Promise<string> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const values: relationalStore.ValuesBucket = {
        'id': ROW_ID,
        'server': config.server,
        'device_key': config.deviceKey,
        'encrypt_key': config.encryptKey,
        'updated_at': Date.now()
      };
      await store.insert(TABLE_CONFIG, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      Logger.i(SCOPE, `save ok server=${config.server} deviceKey=${Redact.len(config.deviceKey)} ` +
        `encryptKey=${Redact.len(config.encryptKey)}`);
      return '';
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `save failed code=${e.code}`);
      return `保存失败，错误码 ${e.code}`;
    }
  }

  static async clear(context: common.Context): Promise<void> {
    try {
      const store: relationalStore.RdbStore = await Database.get(context);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_CONFIG);
      predicates.equalTo('id', ROW_ID);
      await store.delete(predicates);
      Logger.i(SCOPE, 'clear ok');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.e(SCOPE, `clear failed code=${e.code}`);
    }
  }
}
