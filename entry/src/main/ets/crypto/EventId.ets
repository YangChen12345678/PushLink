import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { BarkCrypto } from './BarkCrypto';

/**
 * 由系统通知的 hashCode 推导出稳定的事件 ID。
 *
 * 只用 hashCode，不掺 bundleName / appIndex——这是相对原计划的一处修正，两个原因：
 *
 * 1. **取消回调拿不到包名。** onCancelMessages 只给 Array<string> 形式的 hashCodes，
 *    没有 bundleName 也没有 appIndex。若 eventId 依赖它们，收到取消时就无法反推出
 *    要撤回哪条 Bark 消息，删除功能直接失效。
 * 2. **hashCode 本身已经全局唯一。** 阶段 B 实测形如
 *    `__100_20020072_com.tencent.wechat__1288282963`，其中已含 userId、uid 与包名，
 *    而应用分身有独立 uid，主体与分身天然不会碰撞，不需要再拼 appIndex。
 *
 * 取 SHA-256 而不是直接用 hashCode，是因为原值含明文包名，
 * 而 eventId 会作为 id 发给 Bark 服务端——不能让服务端看出通知来自哪个应用。
 */
export async function computeEventId(hashCode: string): Promise<string> {
  const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
  await md.update({ data: new util.TextEncoder().encodeInto(hashCode) });
  const digest: cryptoFramework.DataBlob = await md.digest();
  return BarkCrypto.toHex(digest.data).substring(0, 32);
}
