import { describe, it, expect } from '@ohos/hypium';
import { BODY_MAX_BYTES, truncateUtf8, utf8Length } from '../../../main/ets/common/TextUtil';
import { grantKey } from '../../../main/ets/common/Types';
import { BarkCrypto } from '../../../main/ets/crypto/BarkCrypto';
import { computeEventId } from '../../../main/ets/crypto/EventId';

/** 测试用密钥，仅存在于测试代码中，与真实 Bark 配置无关。 */
const TEST_KEY: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345';

export default function pipelineTest() {
  describe('pipelineTest', () => {

    // ---------- UTF-8 截断 ----------

    it('truncate_keeps_short_text_intact', 0, () => {
      const text: string = '短文本无需截断';
      expect(truncateUtf8(text, 100)).assertEqual(text);
    });

    it('truncate_respects_byte_limit', 0, () => {
      // 中文每字 3 字节，10 字 = 30 字节，限 16 字节应保留 5 字。
      const text: string = '一二三四五六七八九十';
      const result: string = truncateUtf8(text, 16);
      expect(utf8Length(result) <= 16).assertTrue();
      expect(result).assertEqual('一二三四五');
    });

    it('truncate_never_splits_emoji', 0, () => {
      // 🎉 是代理对，UTF-8 占 4 字节。限 5 字节时只能放下 'A'(1) 而放不下整个 Emoji，
      // 绝不能切出半个代理对——那会产生非法序列，在 iPhone 上表现为乱码。
      const text: string = 'A🎉B';
      const result: string = truncateUtf8(text, 5);
      expect(result).assertEqual('A🎉');
      expect(utf8Length(result)).assertEqual(5);

      const tight: string = truncateUtf8(text, 4);
      expect(tight).assertEqual('A');
    });

    it('truncate_handles_exact_boundary', 0, () => {
      const text: string = '一二';
      expect(truncateUtf8(text, 6)).assertEqual('一二');
      expect(truncateUtf8(text, 5)).assertEqual('一');
    });

    it('truncate_body_limit_produces_valid_length', 0, () => {
      let long: string = '';
      while (long.length < 2000) {
        long += '这是一段用于验证正文截断的测试文本。';
      }
      const result: string = truncateUtf8(long, BODY_MAX_BYTES);
      expect(utf8Length(result) <= BODY_MAX_BYTES).assertTrue();
      expect(result.length > 0).assertTrue();
    });

    // ---------- 白名单键 ----------

    it('grant_key_separates_app_clones', 0, () => {
      // 主体与分身必须产生不同的键，否则一次授权会放行两个实例。
      expect(grantKey('com.tencent.wechat', 0)).assertEqual('com.tencent.wechat#0');
      expect(grantKey('com.tencent.wechat', 1)).assertEqual('com.tencent.wechat#1');
      const same: boolean = grantKey('com.tencent.wechat', 0) === grantKey('com.tencent.wechat', 1);
      expect(same).assertFalse();
    });

    // ---------- eventId ----------

    it('event_id_is_stable_for_same_hash', 0, async (done: Function) => {
      // 稳定性是撤回功能的前提：发布与取消必须算出同一个 ID。
      const hash: string = '__100_20020072_com.tencent.wechat__1288282963';
      const first: string = await computeEventId(hash);
      const second: string = await computeEventId(hash);
      expect(first).assertEqual(second);
      expect(first.length).assertEqual(32);
      expect(/^[0-9a-f]{32}$/.test(first)).assertTrue();
      done();
    });

    it('event_id_differs_for_different_hash', 0, async (done: Function) => {
      const a: string = await computeEventId('__100_20020072_com.tencent.wechat__111');
      const b: string = await computeEventId('__100_20020072_com.tencent.wechat__222');
      const same: boolean = a === b;
      expect(same).assertFalse();
      done();
    });

    it('event_id_hides_bundle_name', 0, async (done: Function) => {
      // eventId 会作为 id 发给 Bark 服务端，不能让服务端看出通知来自哪个应用。
      const id: string = await computeEventId('__100_20020072_com.tencent.wechat__333');
      expect(id.indexOf('wechat')).assertEqual(-1);
      expect(id.indexOf('tencent')).assertEqual(-1);
      done();
    });

    // ---------- AES-256-GCM ----------

    it('crypto_matches_nist_vector_empty', 0, async (done: Function) => {
      // NIST SP 800-38D，全零 Key/IV/空明文。这条能证明输出格式与 Bark 一致，
      // 往返测试做不到——tag 拼错位置时加解密两边会错得一模一样。
      const out: Uint8Array = await BarkCrypto.encryptBytes(
        new Uint8Array(0), new Uint8Array(32), new Uint8Array(12));
      expect(BarkCrypto.toHex(out)).assertEqual('530f8afbc74536b9a963b4f1c4cb738b');
      done();
    });

    it('crypto_matches_nist_vector_16bytes', 0, async (done: Function) => {
      const out: Uint8Array = await BarkCrypto.encryptBytes(
        new Uint8Array(16), new Uint8Array(32), new Uint8Array(12));
      expect(BarkCrypto.toHex(out))
        .assertEqual('cea7403d4d606b6e074ec5d3baf39d18d0d1c8a799996bf0265b98b5d48ab919');
      done();
    });

    it('crypto_round_trip_preserves_unicode', 0, async (done: Function) => {
      const plain: string = '中文 Emoji 🎉👍🏽 换行\n第二行';
      const iv: string = BarkCrypto.generateIv();
      const cipher: string = await BarkCrypto.encrypt(plain, TEST_KEY, iv);
      expect(await BarkCrypto.decrypt(cipher, TEST_KEY, iv)).assertEqual(plain);
      done();
    });

    it('crypto_appends_16_byte_tag', 0, async (done: Function) => {
      // combined 格式：密文 ‖ 16 字节 authTag。长度差必须正好是 16。
      const plain: Uint8Array = new Uint8Array(32);
      const out: Uint8Array = await BarkCrypto.encryptBytes(
        plain, new Uint8Array(32), new Uint8Array(12));
      expect(out.length - plain.length).assertEqual(16);
      done();
    });

    it('crypto_rejects_wrong_key_length', 0, async (done: Function) => {
      let threw: boolean = false;
      try {
        await BarkCrypto.encrypt('x', 'tooshort', BarkCrypto.generateIv());
      } catch (err) {
        threw = true;
      }
      expect(threw).assertTrue();
      done();
    });

    it('crypto_rejects_non_ascii_key', 0, async (done: Function) => {
      // 非 ASCII 经 UTF-8 编码会变多字节，导致密钥长度不符而静默失配。
      let threw: boolean = false;
      try {
        await BarkCrypto.encrypt('x', '中文中文中文中文中文中文中文中文', BarkCrypto.generateIv());
      } catch (err) {
        threw = true;
      }
      expect(threw).assertTrue();
      done();
    });

    // ---------- IV ----------

    it('iv_is_12_ascii_chars', 0, () => {
      const iv: string = BarkCrypto.generateIv();
      expect(iv.length).assertEqual(12);
      expect(/^[A-Za-z0-9]{12}$/.test(iv)).assertTrue();
    });

    it('iv_never_repeats_across_100', 0, () => {
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < 100; i++) {
        seen.add(BarkCrypto.generateIv());
      }
      expect(seen.size).assertEqual(100);
    });
  });
}
