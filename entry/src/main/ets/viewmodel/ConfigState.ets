import { common } from '@kit.AbilityKit';
import { BarkConfig, ConfigStore, DEFAULT_BARK_SERVER, isConfigComplete } from '../service/ConfigStore';
import { BarkClient, BarkPayload, BarkSendResult } from '../service/BarkClient';
import { CryptoSelfTest, SelfTestCase, SelfTestResult } from '../crypto/CryptoSelfTest';

/**
 * Bark 配置、本地加解密自检、测试发送。
 *
 * 配置只在页面创建时读一次（见 load 的调用方），绝不能在每次回到前台时重读——
 * 那会用库里的旧值覆盖用户正在输入、尚未保存的 Device Key 和加密 Key。
 */
@Observed
export class ConfigState {
  server: string = DEFAULT_BARK_SERVER;
  deviceKey: string = '';
  encryptKey: string = '';
  /** 是否明文显示密钥。默认关闭，避免旁人瞥见。 */
  reveal: boolean = false;
  /** 有改动尚未保存。用来提醒用户按保存，也避免误以为已经存上了。 */
  dirty: boolean = false;
  notice: string = '';

  selfTestResults: SelfTestResult[] = [];
  selectedCaseKey: string = 'chinese';
  sendNotice: string = '';
  sendOk: boolean = false;

  current(): BarkConfig {
    return { server: this.server, deviceKey: this.deviceKey, encryptKey: this.encryptKey };
  }

  complete(): boolean {
    return isConfigComplete(this.current());
  }

  async load(ctx: common.Context): Promise<void> {
    const saved: BarkConfig = await ConfigStore.load(ctx);
    this.server = saved.server;
    this.deviceKey = saved.deviceKey;
    this.encryptKey = saved.encryptKey;
    this.dirty = false;
  }

  async save(ctx: common.Context): Promise<void> {
    if (this.encryptKey.length !== 32) {
      this.notice = `加密 Key 必须是 32 个字符，当前 ${this.encryptKey.length} 个`;
      return;
    }
    if (this.deviceKey.length === 0) {
      this.notice = '请填写 Device Key';
      return;
    }
    const err: string = await ConfigStore.save(ctx, this.current());
    if (err.length === 0) {
      this.dirty = false;
      this.notice = '已保存';
    } else {
      this.notice = err;
    }
  }

  /** 本地往返自检，不联网。跑通它才有资格谈和 iPhone 的互通。 */
  async runSelfTest(): Promise<void> {
    if (this.encryptKey.length !== 32) {
      this.notice = '请先填入 32 个字符的加密 Key';
      return;
    }
    this.selfTestResults = [];
    // 先跑标准向量：它能发现往返测试发现不了的格式错误。
    const results: SelfTestResult[] = await CryptoSelfTest.checkStandardVectors();
    const roundTrip: SelfTestResult[] = await CryptoSelfTest.runRoundTrip(this.encryptKey);
    for (const item of roundTrip) {
      results.push(item);
    }
    results.push(CryptoSelfTest.checkIvUniqueness(100));
    this.selfTestResults = results;
  }

  /** 发送一条内置虚构测试消息。加密互操作通过前，只有这个入口能触网。 */
  async sendTest(): Promise<void> {
    const config: BarkConfig = this.current();
    if (!isConfigComplete(config)) {
      this.sendOk = false;
      this.sendNotice = '请先完整填写并保存 Bark 配置。';
      return;
    }
    let picked: SelfTestCase | undefined = undefined;
    for (const item of CryptoSelfTest.cases()) {
      if (item.key === this.selectedCaseKey) {
        picked = item;
      }
    }
    if (picked === undefined) {
      this.sendOk = false;
      this.sendNotice = '未选择测试用例。';
      return;
    }
    this.sendNotice = '';
    const payload: BarkPayload = {
      title: picked.title,
      body: picked.body,
      group: 'PushLink 自检',
      level: 'active',
      action: 'none'
    };
    // 测试消息用固定前缀的 id，方便在 Bark 里辨认，也不会与真实通知的 eventId 冲突。
    const id: string = `selftest-${picked.key}-${Date.now()}`;
    const result: BarkSendResult = await BarkClient.push(config, payload, id);
    this.sendOk = result.ok;
    this.sendNotice = result.ok
      ? `发送成功，耗时 ${result.elapsedMs} 毫秒。请在 iPhone 上确认内容显示正确。`
      : result.message;
  }
}
