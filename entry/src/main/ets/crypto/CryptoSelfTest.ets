import { BarkCrypto } from './BarkCrypto';
import { Logger } from '../common/Logger';

const SCOPE: string = 'SelfTest';

/** 一个虚构的测试用例。内容全部是编造的，绝不取自真实通知。 */
export interface SelfTestCase {
  key: string;
  name: string;
  title: string;
  body: string;
}

export interface SelfTestResult {
  name: string;
  passed: boolean;
  detail: string;
}

/** 用来凑长文本的虚构句子，重复拼接到接近正文上限。 */
const FILLER: string = '这是一条用于验证加密互通的虚构测试内容，不含任何真实通知信息。';

function buildLongBody(): string {
  let text: string = '';
  // 正文上限 1500 UTF-8 字节，中文按 3 字节算，留出余量停在 1400 字节附近。
  while (text.length * 3 < 1400) {
    text += FILLER;
  }
  return text;
}

export class CryptoSelfTest {
  /**
   * 覆盖计划里点名的四类内容：中文、Emoji、换行、长文本。
   * 这四类正是编码环节最容易出问题的地方——UTF-8 多字节、代理对、控制字符、载荷超限。
   */
  static cases(): SelfTestCase[] {
    return [
      {
        key: 'ascii',
        name: '纯 ASCII',
        title: 'PushLink',
        body: 'Hello from PushLink self test.'
      },
      {
        key: 'chinese',
        name: '中文',
        title: '中文标题测试',
        body: '这是一条虚构的中文测试消息，用于验证多字节字符能否正确解密。'
      },
      {
        key: 'emoji',
        name: 'Emoji',
        title: 'Emoji 测试 🎉',
        body: '表情符号往返验证：🚀 ✅ 🔐 👍🏽 —— 其中包含需要代理对表示的字符。'
      },
      {
        key: 'newline',
        name: '换行',
        title: '多行正文',
        body: '第一行\n第二行\n第三行\n\n空行之后的第四行'
      },
      {
        key: 'long',
        name: '长文本',
        title: '长正文测试',
        body: buildLongBody()
      }
    ];
  }

  /**
   * 本地加解密往返自检，不联网。
   * 在惊动 iPhone 之前就能抓出密钥长度、IV 编码、authTag 拼接顺序这类错误。
   */
  static async runRoundTrip(encryptKey: string): Promise<SelfTestResult[]> {
    const results: SelfTestResult[] = [];
    for (const item of CryptoSelfTest.cases()) {
      const plaintext: string = JSON.stringify(item);
      try {
        const iv: string = BarkCrypto.generateIv();
        const encrypted: string = await BarkCrypto.encrypt(plaintext, encryptKey, iv);
        const decrypted: string = await BarkCrypto.decrypt(encrypted, encryptKey, iv);
        const passed: boolean = decrypted === plaintext;
        results.push({
          name: item.name,
          passed: passed,
          detail: passed
            ? `密文 ${encrypted.length} 字符`
            : '解密结果与原文不一致'
        });
      } catch (err) {
        const e: Error = err as Error;
        results.push({ name: item.name, passed: false, detail: e.message });
      }
    }
    Logger.i(SCOPE, `runRoundTrip cases=${results.length} ` +
      `passed=${results.filter((r: SelfTestResult) => r.passed).length}`);
    return results;
  }

  /**
   * 用 NIST SP 800-38D 的 AES-256-GCM 标准向量比对输出。
   *
   * 这是唯一能证明"输出格式和 Bark 对得上"的本地手段：往返测试只能证明自洽，
   * tag 拼错位置时加解密两边错得一样，照样通过。向量用全零 Key / IV / 明文，
   * 期望值是公开的标准结果。
   *
   * 若这里失败而 iPhone 实际解密正常，应先怀疑向量常量本身抄错，而不是急着改实现。
   */
  static async checkStandardVectors(): Promise<SelfTestResult[]> {
    return [
      await CryptoSelfTest.runVector('NIST 向量·空明文', 0,
        '530f8afbc74536b9a963b4f1c4cb738b'),
      await CryptoSelfTest.runVector('NIST 向量·16 字节', 16,
        'cea7403d4d606b6e074ec5d3baf39d18d0d1c8a799996bf0265b98b5d48ab919')
    ];
  }

  private static async runVector(name: string, plainLength: number,
    expectedHex: string): Promise<SelfTestResult> {
    try {
      // Uint8Array 默认填充 0，正好对应向量里的全零 Key / IV / 明文。
      const output: Uint8Array = await BarkCrypto.encryptBytes(
        new Uint8Array(plainLength), new Uint8Array(32), new Uint8Array(12));
      const actual: string = BarkCrypto.toHex(output);
      const passed: boolean = actual === expectedHex;
      return {
        name: name,
        passed: passed,
        detail: passed ? '与标准向量逐字节一致' : `实际输出 ${actual}`
      };
    } catch (err) {
      const e: Error = err as Error;
      return { name: name, passed: false, detail: e.message };
    }
  }

  /**
   * IV 唯一性：计划要求连续 100 条不得重复。
   * 随机数接口可能抛异常，这里必须自行兜住——否则一次失败会让整个自检中断。
   */
  static checkIvUniqueness(count: number): SelfTestResult {
    const label: string = `IV 唯一性（${count} 条）`;
    try {
      const seen: Set<string> = new Set<string>();
      let duplicated: number = 0;
      for (let i = 0; i < count; i++) {
        const iv: string = BarkCrypto.generateIv();
        if (seen.has(iv)) {
          duplicated++;
        }
        seen.add(iv);
      }
      const passed: boolean = duplicated === 0;
      Logger.i(SCOPE, `checkIvUniqueness count=${count} unique=${seen.size} duplicated=${duplicated}`);
      return {
        name: label,
        passed: passed,
        detail: passed ? `${seen.size} 条全部互不相同` : `出现 ${duplicated} 次重复`
      };
    } catch (err) {
      const e: Error = err as Error;
      Logger.e(SCOPE, `checkIvUniqueness failed: ${e.message}`);
      return { name: label, passed: false, detail: `随机数生成失败：${e.message}` };
    }
  }
}
