import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { Logger, Redact } from '../common/Logger';

const SCOPE: string = 'BarkCrypto';

/**
 * IV 字符集只用字母数字。Bark 的 IV 以字符串形式随请求传递，
 * 用纯字母数字可以彻底避开 JSON 转义与 URL 编码带来的不一致风险。
 * 12 个字符 × log2(62) ≈ 71 bit 熵，对本场景的唯一性绰绰有余。
 */
const IV_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
const IV_LENGTH: number = 12;
const KEY_LENGTH: number = 32;
const TAG_LENGTH: number = 16;

/** 拒绝采样上界：256 - (256 % 62) = 248，避免取模带来的字符分布偏差。 */
const REJECT_BOUND: number = 256 - (256 % 62);

export class CryptoConfigError extends Error {
}

/**
 * 与 Bark iOS 端（CryptoSwift）互通的 AES-256-GCM 实现。
 *
 * 关键互操作约定：
 *   - Bark 侧固定为 AES256 / GCM / noPadding；
 *   - CryptoSwift 的 GCM 用 combined 模式，即密文与 16 字节 authTag 首尾相接后再 Base64；
 *   - HarmonyOS 这边 update() 出密文、doFinal(null) 单独出 authTag，必须手工拼接，
 *     直接把 doFinal 的结果当密文用是对不上的。
 */
export class BarkCrypto {
  /** 生成一条消息专用的随机 IV。每条消息都必须重新生成，绝不复用。 */
  static generateIv(): string {
    const random: cryptoFramework.Random = cryptoFramework.createRandom();
    let result: string = '';
    while (result.length < IV_LENGTH) {
      const blob: cryptoFramework.DataBlob = random.generateRandomSync(IV_LENGTH * 2);
      for (let i = 0; i < blob.data.length && result.length < IV_LENGTH; i++) {
        const b: number = blob.data[i];
        if (b < REJECT_BOUND) {
          result += IV_ALPHABET.charAt(b % IV_ALPHABET.length);
        }
      }
    }
    return result;
  }

  /**
   * 加密并返回 Base64(ciphertext || authTag)。
   *
   * @param plaintext 明文 JSON，按 UTF-8 编码，可含中文与 Emoji。
   * @param key32 32 个 ASCII 字符的 Bark 加密 Key。
   * @param iv12 12 个 ASCII 字符的 IV，由 generateIv() 产生。
   */
  static async encrypt(plaintext: string, key32: string, iv12: string): Promise<string> {
    BarkCrypto.assertAscii(key32, KEY_LENGTH, '加密 Key');
    BarkCrypto.assertAscii(iv12, IV_LENGTH, 'IV');

    const encoder: util.TextEncoder = new util.TextEncoder();
    const combined: Uint8Array = await BarkCrypto.encryptBytes(
      encoder.encodeInto(plaintext), encoder.encodeInto(key32), encoder.encodeInto(iv12));

    const encoded: string = new util.Base64Helper().encodeToStringSync(combined);
    // 明文与密钥一律不落日志，只记录规模，便于排查载荷超限。
    Logger.i(SCOPE, `encrypt plain=${Redact.len(plaintext)} cipherB64=${encoded.length}`);
    return encoded;
  }

  /**
   * 字节层加密，返回 ciphertext || authTag。
   *
   * 单独暴露这一层是为了能用 NIST 标准测试向量直接打它：
   * 往返测试（加密再解密）即使 tag 拼接顺序反了也会通过，因为两边错得一样，
   * 只有拿固定向量比对才能证明输出格式真的和 Bark/CryptoSwift 对得上。
   */
  static async encryptBytes(plainBytes: Uint8Array, keyBytes: Uint8Array,
    ivBytes: Uint8Array): Promise<Uint8Array> {
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
    const symKey: cryptoFramework.SymKey = await generator.convertKey({ data: keyBytes });

    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    const params: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: ivBytes },
      // Bark 侧不使用附加认证数据，这里必须同样留空，否则 tag 校验会失败。
      aad: { data: new Uint8Array(0) },
      // 加密方向上 authTag 只是长度占位，实际值由 doFinal 返回。
      authTag: { data: new Uint8Array(TAG_LENGTH) }
    };

    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
    // 明文为空时（标准向量里有这种用例）不能调 update，直接取 tag。
    let cipherBytes: Uint8Array = new Uint8Array(0);
    if (plainBytes.length > 0) {
      const cipherPart: cryptoFramework.DataBlob = await cipher.update({ data: plainBytes });
      cipherBytes = cipherPart.data;
    }
    const tagPart: cryptoFramework.DataBlob = await cipher.doFinal(null);

    const combined: Uint8Array = new Uint8Array(cipherBytes.length + tagPart.data.length);
    combined.set(cipherBytes, 0);
    combined.set(tagPart.data, cipherBytes.length);
    return combined;
  }

  /** 字节数组转小写十六进制，仅用于标准向量比对。 */
  static toHex(bytes: Uint8Array): string {
    let out: string = '';
    for (let i = 0; i < bytes.length; i++) {
      const part: string = bytes[i].toString(16);
      out += part.length === 1 ? `0${part}` : part;
    }
    return out;
  }

  /**
   * 本地自解密校验。发送前跑一次，能在不惊动 iPhone 的情况下抓出
   * 密钥长度、IV 编码、tag 拼接顺序这类错误。
   */
  static async decrypt(base64Combined: string, key32: string, iv12: string): Promise<string> {
    BarkCrypto.assertAscii(key32, KEY_LENGTH, '加密 Key');
    BarkCrypto.assertAscii(iv12, IV_LENGTH, 'IV');

    const combined: Uint8Array = new util.Base64Helper().decodeSync(base64Combined);
    if (combined.length < TAG_LENGTH) {
      throw new CryptoConfigError('密文长度不足，无法分离 authTag');
    }
    const cipherBytes: Uint8Array = combined.slice(0, combined.length - TAG_LENGTH);
    const tagBytes: Uint8Array = combined.slice(combined.length - TAG_LENGTH);

    const encoder: util.TextEncoder = new util.TextEncoder();
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
    const symKey: cryptoFramework.SymKey = await generator.convertKey({ data: encoder.encodeInto(key32) });

    const decipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    const params: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: encoder.encodeInto(iv12) },
      aad: { data: new Uint8Array(0) },
      authTag: { data: tagBytes }
    };

    await decipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
    const out: cryptoFramework.DataBlob = await decipher.update({ data: cipherBytes });
    await decipher.doFinal(null);
    return new util.TextDecoder().decodeToString(out.data);
  }

  /** Key 与 IV 必须是纯 ASCII：非 ASCII 字符经 UTF-8 编码会变成多字节，导致长度不符而静默失配。 */
  private static assertAscii(value: string, expectedLength: number, label: string): void {
    if (value.length !== expectedLength) {
      throw new CryptoConfigError(`${label}必须是 ${expectedLength} 个字符，当前 ${value.length} 个`);
    }
    for (let i = 0; i < value.length; i++) {
      const code: number = value.charCodeAt(i);
      if (code < 0x20 || code > 0x7e) {
        throw new CryptoConfigError(`${label}只能包含可打印 ASCII 字符（位置 ${i + 1} 不合法）`);
      }
    }
  }
}
