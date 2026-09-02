import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger, Redact } from '../common/Logger';
import { BarkConfig } from './ConfigStore';
import { BarkCrypto } from '../crypto/BarkCrypto';

const SCOPE: string = 'BarkClient';
const TIMEOUT_MS: number = 8000;

/** 加密前的 Bark 载荷。字段名与顺序按 Bark 约定，不要改。 */
export interface BarkPayload {
  title: string;
  body: string;
  /** Bark 侧的分组，用来源包名填充，便于在 iPhone 上按应用归类。 */
  group: string;
  level: string;
  action: string;
}

export interface BarkSendResult {
  ok: boolean;
  /** HTTP 状态码，网络层失败时为 0。 */
  httpCode: number;
  /** Bark 业务返回码，未解析出时为 0。 */
  barkCode: number;
  /** 已脱敏的结果说明，可直接上屏。 */
  message: string;
  elapsedMs: number;
}

/** Bark 的 JSON 响应体。 */
interface BarkResponseBody {
  code: number;
  message: string;
  timestamp?: number;
}

export class BarkClient {
  /**
   * 加密并推送一条消息。
   *
   * @param id 幂等标识。同一条通知的更新复用同一 id，Bark 会覆盖而不是新增。
   */
  static async push(config: BarkConfig, payload: BarkPayload, id: string): Promise<BarkSendResult> {
    const started: number = Date.now();
    let ciphertext: string = '';
    let iv: string = '';
    try {
      iv = BarkCrypto.generateIv();
      ciphertext = await BarkCrypto.encrypt(JSON.stringify(payload), config.encryptKey, iv);
    } catch (err) {
      const e: Error = err as Error;
      Logger.e(SCOPE, `encrypt failed: ${e.message}`);
      return {
        ok: false, httpCode: 0, barkCode: 0,
        message: `加密失败：${e.message}`,
        elapsedMs: Date.now() - started
      };
    }
    return BarkClient.post(config, ciphertext, iv, id, started);
  }

  /**
   * 发送已经加密好的内容。
   * 队列里存的就是密文，重投时直接发，不能重新加密——那样会换掉 IV，
   * 而 Bark 侧靠请求里的 iv 解密，虽然仍能解开，但白白多耗一次加密且失去幂等性。
   */
  static async pushCiphertext(config: BarkConfig, ciphertext: string, iv: string,
    id: string): Promise<BarkSendResult> {
    return BarkClient.post(config, ciphertext, iv, id, Date.now());
  }

  /**
   * 撤回一条已投递的消息。这是控制消息，不携带任何正文。
   * iPhone 端需要开启 Bark 的「后台 App 刷新」才会真正删除。
   */
  static async deleteMessage(config: BarkConfig, id: string): Promise<BarkSendResult> {
    const started: number = Date.now();
    const form: string = `id=${encodeURIComponent(id)}&delete=1`;
    return BarkClient.send(BarkClient.deviceEndpoint(config), form, started, 'delete');
  }

  private static async post(config: BarkConfig, ciphertext: string, iv: string,
    id: string, started: number): Promise<BarkSendResult> {
    // Bark 的加密推送走 POST /{device_key} + form-urlencoded。
    // /push 端点只认明文 JSON 的 title/body，把 ciphertext 发过去会因缺字段被判 400。
    const form: string = `ciphertext=${encodeURIComponent(ciphertext)}` +
      `&iv=${encodeURIComponent(iv)}&id=${encodeURIComponent(id)}`;
    return BarkClient.send(BarkClient.deviceEndpoint(config), form, started, 'push');
  }

  private static async send(url: string, formBody: string, started: number,
    kind: string): Promise<BarkSendResult> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/x-www-form-urlencoded' },
        extraData: formBody,
        connectTimeout: TIMEOUT_MS,
        readTimeout: TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      });
      const elapsed: number = Date.now() - started;
      const httpCode: number = response.responseCode;
      const parsed: BarkResponseBody | undefined = BarkClient.parseBody(response.result);

      if (httpCode !== 200) {
        // 请求体含 device_key 与密文，任何情况下都不记录，只记录规模与状态。
        Logger.e(SCOPE, `${kind} http failed code=${httpCode} bytes=${formBody.length} elapsed=${elapsed}`);
        // Bark 在 4xx 时通常会在响应体里说明具体原因，务必透出来——
        // 只显示自己编的固定文案会把真正的线索丢掉。
        const detail: string = parsed !== undefined && parsed.message.length > 0
          ? `：${parsed.message}`
          : BarkClient.rawSnippet(response.result);
        return {
          ok: false, httpCode: httpCode, barkCode: parsed !== undefined ? parsed.code : 0,
          message: `${BarkClient.describeHttp(httpCode)}${detail}`,
          elapsedMs: elapsed
        };
      }
      if (parsed === undefined) {
        Logger.e(SCOPE, `${kind} unparsable response elapsed=${elapsed}`);
        return {
          ok: false, httpCode: httpCode, barkCode: 0,
          message: '服务返回的内容无法解析为 Bark 响应',
          elapsedMs: elapsed
        };
      }
      const ok: boolean = parsed.code === 200;
      Logger.i(SCOPE, `${kind} done http=${httpCode} barkCode=${parsed.code} elapsed=${elapsed}`);
      return {
        ok: ok,
        httpCode: httpCode,
        barkCode: parsed.code,
        message: ok ? '' : `Bark 返回 ${parsed.code}：${parsed.message}`,
        elapsedMs: elapsed
      };
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      const elapsed: number = Date.now() - started;
      Logger.e(SCOPE, `${kind} network error code=${e.code} elapsed=${elapsed}`);
      return {
        ok: false, httpCode: 0, barkCode: 0,
        message: BarkClient.describeNetwork(e.code),
        elapsedMs: elapsed
      };
    } finally {
      request.destroy();
    }
  }

  private static parseBody(raw: string | Object | ArrayBuffer): BarkResponseBody | undefined {
    if (typeof raw !== 'string') {
      return undefined;
    }
    try {
      return JSON.parse(raw) as BarkResponseBody;
    } catch (err) {
      return undefined;
    }
  }

  /** 加密推送的目标是 {server}/{device_key}，Device Key 走路径而不是请求体。 */
  private static deviceEndpoint(config: BarkConfig): string {
    const base: string = config.server.endsWith('/')
      ? config.server.substring(0, config.server.length - 1)
      : config.server;
    return `${base}/${config.deviceKey}`;
  }

  /** 响应体不是标准 JSON 时，截一小段原文帮助排查。Bark 的错误响应不会回显密文。 */
  private static rawSnippet(raw: string | Object | ArrayBuffer): string {
    if (typeof raw !== 'string' || raw.length === 0) {
      return '';
    }
    const trimmed: string = raw.length > 120 ? `${raw.substring(0, 120)}…` : raw;
    return `，服务返回：${trimmed}`;
  }

  private static describeHttp(code: number): string {
    switch (code) {
      case 400:
        return 'Bark 拒绝了请求（400）';
      case 401:
      case 403:
        return `Bark 拒绝授权（${code}），检查 Device Key`;
      case 404:
        return 'Bark 找不到该 Device Key（404）';
      case 429:
        return '请求过于频繁，被 Bark 限流（429）';
      default:
        return code >= 500 ? `Bark 服务端错误（${code}）` : `HTTP ${code}`;
    }
  }

  private static describeNetwork(code: number): string {
    switch (code) {
      case 2300006:
        return '无法解析服务域名，检查网络连接';
      case 2300007:
        return '无法连接到 Bark 服务器';
      case 2300028:
        return `请求超时（超过 ${TIMEOUT_MS / 1000} 秒）`;
      case 201:
        return '缺少网络权限';
      default:
        return `网络错误，错误码 ${code}`;
    }
  }
}
