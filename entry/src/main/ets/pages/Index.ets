import { common } from '@kit.AbilityKit';
import { BluetoothService, PairedDevice, PairedDeviceListResult } from '../service/BluetoothService';
import { PermissionService } from '../service/PermissionService';
import { SubscriptionService, SubscriptionSnapshot } from '../service/SubscriptionService';
import { GrantedBundle } from '../common/Types';
import { Logger } from '../common/Logger';
import { BarkConfig, ConfigStore, DEFAULT_BARK_SERVER, isConfigComplete } from '../service/ConfigStore';
import { BarkClient, BarkPayload, BarkSendResult } from '../service/BarkClient';
import { CryptoSelfTest, SelfTestCase, SelfTestResult } from '../crypto/CryptoSelfTest';
import { GrantStore } from '../service/GrantStore';
import { ForwardPipeline } from '../service/ForwardPipeline';
import { OutboxStore } from '../service/OutboxStore';
import { DiagnosticEntry, DiagnosticStore } from '../service/DiagnosticStore';

/** 时间戳转 HH:MM:SS，0 表示还没有过。 */
function formatClock(timestamp: number): string {
  if (timestamp === 0) {
    return '尚无';
  }
  const date: Date = new Date(timestamp);
  const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
  return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

function emptySnapshot(): SubscriptionSnapshot {
  return {
    subscribed: false,
    subscribedAddrMasked: '',
    userGranted: false,
    grantedBundles: [],
    lastError: ''
  };
}

/**
 * statusRow 的参数必须包成对象。
 * ArkUI 的 @Builder 在参数为简单类型时按值传递，状态变化不会触发内部 UI 刷新——
 * 那会让状态行永远停在首次渲染的值上。只有按引用传递（单个对象字面量参数）才会跟着刷新。
 */
interface StatusRowParam {
  label: string;
  value: string;
  ok: boolean;
}

const COLOR_MUTED: string = '#8A8A8E';
const COLOR_OK: string = '#1E9E5A';
const COLOR_BAD: string = '#C0392B';
const COLOR_CARD: string = '#F5F5F7';

@Entry
@Component
struct Index {
  @State btGranted: boolean = false;
  @State btEnabled: boolean = false;
  @State devices: PairedDevice[] = [];
  @State deviceError: number = 0;
  @State selectedAddr: string = '';
  @State snap: SubscriptionSnapshot = emptySnapshot();
  @State busy: boolean = false;
  @State notice: string = '';
  // 配置用三个独立的 @State 字段，不用单个对象：
  // @State 只观察第一层属性，改 obj.field 不会触发刷新，和 @Builder 按值传递是同一类陷阱。
  @State cfgServer: string = DEFAULT_BARK_SERVER;
  @State cfgDeviceKey: string = '';
  @State cfgEncryptKey: string = '';
  @State revealSecrets: boolean = false;
  /** 有改动尚未保存。用来提醒用户按保存，也避免误以为已经存上了。 */
  @State configDirty: boolean = false;
  @State configNotice: string = '';
  @State selfTestResults: SelfTestResult[] = [];
  @State selectedCaseKey: string = 'chinese';
  @State sendNotice: string = '';
  @State sendOk: boolean = false;
  @State queueDepth: number = 0;
  @State lastSuccessAt: number = 0;
  @State diagnostics: DiagnosticEntry[] = [];
  /** 测试用例是常量，取一次即可，避免 ForEach 每帧重建数组。 */
  private readonly testCases: SelfTestCase[] = CryptoSelfTest.cases();

  /**
   * 链路是否真的能工作。
   * 阶段 B 实测：蓝牙关闭时 subscribed 仍为 true 但一条回调都收不到，
   * 所以不能只看订阅记录，必须三个条件同时成立。
   */
  private healthy(): boolean {
    return this.snap.subscribed && this.snap.userGranted && this.btEnabled;
  }

  private healthDetail(): string {
    if (this.healthy()) {
      return '正常';
    }
    const missing: string[] = [];
    if (!this.snap.subscribed) {
      missing.push('未订阅');
    }
    if (!this.snap.userGranted) {
      missing.push('未开启通知读取');
    }
    if (!this.btEnabled) {
      missing.push('蓝牙未开启');
    }
    return missing.join('、');
  }

  /**
   * 配置只在页面创建时读一次。
   * 绝不能放进 onPageShow：那样每次回到前台都会用库里的旧值覆盖用户正在输入、
   * 尚未保存的 Device Key 和加密 Key，输入内容会凭空消失。
   */
  aboutToAppear(): void {
    this.loadConfig();
  }

  /** 每次回到前台重取订阅与蓝牙状态。授权列表以系统返回为准，不做本地累积。 */
  onPageShow(): void {
    this.refreshAll();
  }

  private async loadConfig(): Promise<void> {
    const ctx: common.UIAbilityContext | undefined = this.hostContext();
    if (ctx === undefined) {
      return;
    }
    const saved: BarkConfig = await ConfigStore.load(ctx);
    this.cfgServer = saved.server;
    this.cfgDeviceKey = saved.deviceKey;
    this.cfgEncryptKey = saved.encryptKey;
    this.configDirty = false;
  }

  /** getHostContext() 在异常场景可能返回 undefined，调用方必须判空，避免真机上直接崩溃。 */
  private hostContext(): common.UIAbilityContext | undefined {
    return this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
  }

  private refreshBluetooth(): void {
    this.btGranted = PermissionService.isBluetoothGranted();
    this.btEnabled = BluetoothService.isEnabled();
    Logger.i('UI', `refreshBluetooth granted=${this.btGranted} enabled=${this.btEnabled}`);
    if (!this.btGranted || !this.btEnabled) {
      this.devices = [];
      this.deviceError = 0;
      return;
    }
    const result: PairedDeviceListResult = BluetoothService.listPaired();
    this.devices = result.devices;
    this.deviceError = result.errorCode;
    // 选中的设备若已解除配对，清空选择；不去猜测系统当前订阅对应哪台设备——地址已掩码，无法反查。
    if (this.selectedAddr.length > 0) {
      let stillPaired: boolean = false;
      for (const device of this.devices) {
        if (device.addr === this.selectedAddr) {
          stillPaired = true;
          break;
        }
      }
      if (!stillPaired) {
        this.selectedAddr = '';
      }
    }
  }

  private async refreshAll(): Promise<void> {
    this.refreshBluetooth();
    this.snap = await SubscriptionService.snapshot();

    const ctx: common.UIAbilityContext | undefined = this.hostContext();
    if (ctx === undefined) {
      return;
    }
    // 系统授权列表是唯一白名单来源，每次前台把它同步到本地缓存，
    // 扩展进程只认这份缓存——它自己没法拉起授权页去问系统。
    await GrantStore.replaceAll(ctx, this.snap.grantedBundles);
    // 回到前台顺带补投积压：断网期间攒下的队列在这里获得一次清空机会。
    await ForwardPipeline.drain(ctx);
    await this.refreshDiagnostics(ctx);
  }

  private async refreshDiagnostics(ctx: common.UIAbilityContext): Promise<void> {
    this.queueDepth = await OutboxStore.depth(ctx);
    this.lastSuccessAt = await DiagnosticStore.lastSuccessAt(ctx);
    this.diagnostics = await DiagnosticStore.recent(ctx, 12);
  }

  private async onClearDiagnostics(): Promise<void> {
    const ctx: common.UIAbilityContext | undefined = this.hostContext();
    if (ctx === undefined) {
      return;
    }
    await DiagnosticStore.clear(ctx);
    await this.refreshDiagnostics(ctx);
  }

  private async onDrainNow(): Promise<void> {
    const ctx: common.UIAbilityContext | undefined = this.hostContext();
    if (ctx === undefined) {
      return;
    }
    this.busy = true;
    try {
      await ForwardPipeline.drain(ctx);
      await this.refreshDiagnostics(ctx);
    } finally {
      this.busy = false;
    }
  }

  private currentConfig(): BarkConfig {
    return { server: this.cfgServer, deviceKey: this.cfgDeviceKey, encryptKey: this.cfgEncryptKey };
  }

  private async onSaveConfig(): Promise<void> {
    const ctx: common.UIAbilityContext | undefined = this.hostContext();
    if (ctx === undefined) {
      this.configNotice = '无法获取页面上下文，请重新打开应用。';
      return;
    }
    if (this.cfgEncryptKey.length !== 32) {
      this.configNotice = `加密 Key 必须是 32 个字符，当前 ${this.cfgEncryptKey.length} 个。`;
      return;
    }
    if (this.cfgDeviceKey.length === 0) {
      this.configNotice = '请填写 Device Key。';
      return;
    }
    this.busy = true;
    const err: string = await ConfigStore.save(ctx, this.currentConfig());
    this.busy = false;
    if (err.length === 0) {
      this.configDirty = false;
      this.configNotice = '已保存。';
    } else {
      this.configNotice = err;
    }
  }

  /** 本地往返自检，不联网。跑通它才有资格谈和 iPhone 的互通。 */
  private async onRunSelfTest(): Promise<void> {
    if (this.cfgEncryptKey.length !== 32) {
      this.configNotice = '请先填入 32 个字符的加密 Key。';
      return;
    }
    this.busy = true;
    this.selfTestResults = [];
    try {
      // 先跑标准向量：它能发现往返测试发现不了的格式错误。
      const results: SelfTestResult[] = await CryptoSelfTest.checkStandardVectors();
      const roundTrip: SelfTestResult[] = await CryptoSelfTest.runRoundTrip(this.cfgEncryptKey);
      for (const item of roundTrip) {
        results.push(item);
      }
      results.push(CryptoSelfTest.checkIvUniqueness(100));
      this.selfTestResults = results;
    } finally {
      // 无论自检怎么失败，都要把按钮解锁，不能把界面卡死在 busy 上。
      this.busy = false;
    }
  }

  /** 发送一条内置虚构测试消息。加密互操作通过前，只有这个入口能触网。 */
  private async onSendTest(): Promise<void> {
    const config: BarkConfig = this.currentConfig();
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

    this.busy = true;
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
    this.busy = false;
    this.sendOk = result.ok;
    this.sendNotice = result.ok
      ? `发送成功，耗时 ${result.elapsedMs} 毫秒。请在 iPhone 上确认内容显示正确。`
      : result.message;
  }

  private async onRequestBluetooth(): Promise<void> {
    const ctx: common.UIAbilityContext | undefined = this.hostContext();
    if (ctx === undefined) {
      this.notice = '无法获取页面上下文，请重新打开应用。';
      return;
    }
    this.busy = true;
    const granted: boolean = await PermissionService.requestBluetooth(ctx);
    this.busy = false;
    this.notice = granted ? '' : '蓝牙权限未授予。若之前选过“禁止后不再询问”，需到系统设置手动开启。';
    this.refreshBluetooth();
  }

  private async onSubscribe(): Promise<void> {
    if (this.selectedAddr.length === 0) {
      this.notice = '请先选择一台已配对设备。';
      return;
    }
    this.busy = true;
    this.notice = await SubscriptionService.subscribe(this.selectedAddr);
    await this.refreshAll();
    this.busy = false;
  }

  private async onUnsubscribe(): Promise<void> {
    this.busy = true;
    this.notice = await SubscriptionService.unsubscribe();
    await this.refreshAll();
    this.busy = false;
  }

  private async onOpenSettings(): Promise<void> {
    const ctx: common.UIAbilityContext | undefined = this.hostContext();
    if (ctx === undefined) {
      this.notice = '无法获取页面上下文，请重新打开应用。';
      return;
    }
    this.busy = true;
    const result: SubscriptionSnapshot = await SubscriptionService.openSettings(ctx);
    this.notice = result.lastError;
    // 半模态关闭后系统状态可能已变，整体重取而非只用返回值。
    await this.refreshAll();
    this.busy = false;
  }

  @Builder
  sectionHeader(index: number, title: string) {
    Row({ space: 8 }) {
      Text(index.toString())
        .fontSize(12)
        .fontColor(Color.White)
        .backgroundColor(COLOR_MUTED)
        .borderRadius(9)
        .width(18)
        .height(18)
        .textAlign(TextAlign.Center)
      Text(title).fontSize(16).fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .margin({ top: 18, bottom: 8 })
  }

  @Builder
  statusRow($$: StatusRowParam) {
    Row() {
      Text($$.label).fontSize(14).fontColor(COLOR_MUTED).layoutWeight(1)
      Text($$.value).fontSize(14).fontColor($$.ok ? COLOR_OK : COLOR_BAD)
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
  }

  build() {
    Scroll() {
      Column() {
        Text('PushLink').fontSize(28).fontWeight(FontWeight.Bold).width('100%')
        Text('阶段 B · 通知订阅验证').fontSize(12).fontColor(COLOR_MUTED).width('100%').margin({ top: 2 })

        if (this.notice.length > 0) {
          Text(this.notice)
            .fontSize(13)
            .fontColor(COLOR_BAD)
            .width('100%')
            .padding(10)
            .backgroundColor('#FDECEA')
            .borderRadius(8)
            .margin({ top: 12 })
        }

        this.sectionHeader(1, 'ACL / 通知订阅状态')
        Column() {
          // 综合健康状态放在最前：单看"订阅已登记"会误导——
          // 蓝牙关闭时它照样是"是"，但一条通知都收不到。
          this.statusRow({
            label: '转发链路',
            value: this.healthDetail(),
            ok: this.healthy()
          })
          this.statusRow({
            label: '订阅已登记',
            value: this.snap.subscribed ? '是' : '否',
            ok: this.snap.subscribed
          })
          if (this.snap.subscribed && this.snap.subscribedAddrMasked.length > 0) {
            this.statusRow({ label: '订阅设备', value: this.snap.subscribedAddrMasked, ok: true })
          }
          this.statusRow({
            label: '允许读取本机通知',
            value: this.snap.userGranted ? '已开启' : '未开启',
            ok: this.snap.userGranted
          })
          if (this.snap.lastError.length > 0) {
            Text(this.snap.lastError).fontSize(12).fontColor(COLOR_BAD).width('100%').margin({ top: 6 })
          }
        }
        .width('100%').padding(12).backgroundColor(COLOR_CARD).borderRadius(10)

        this.sectionHeader(2, '已配对蓝牙设备')
        Column() {
          this.statusRow({
            label: '蓝牙权限',
            value: this.btGranted ? '已授予' : '未授予',
            ok: this.btGranted
          })
          this.statusRow({
            label: '蓝牙开关',
            value: this.btEnabled ? '已开启' : '未开启',
            ok: this.btEnabled
          })

          if (!this.btGranted) {
            Button('申请蓝牙权限')
              .fontSize(14).width('100%').margin({ top: 10 })
              .enabled(!this.busy)
              .onClick(() => { this.onRequestBluetooth(); })
          } else if (!this.btEnabled) {
            Text('请在系统里打开蓝牙后返回本页。')
              .fontSize(12).fontColor(COLOR_MUTED).width('100%').margin({ top: 8 })
          } else if (this.devices.length === 0) {
            Text(this.deviceError === 0
              ? '没有已配对设备。请先在系统设置里完成配对，本应用不发起配对。'
              : '读取配对列表失败，错误码 ' + this.deviceError.toString() + '。')
              .fontSize(12).fontColor(COLOR_MUTED).width('100%').margin({ top: 8 })
          } else {
            Text('选择一台设备作为订阅登记对象：')
              .fontSize(12).fontColor(COLOR_MUTED).width('100%').margin({ top: 10, bottom: 4 })
            ForEach(this.devices, (item: PairedDevice) => {
              Row({ space: 8 }) {
                Radio({ value: item.addr, group: 'pairedDevices' })
                  .checked(this.selectedAddr === item.addr)
                  .onChange((checked: boolean) => {
                    if (checked) {
                      this.selectedAddr = item.addr;
                    }
                  })
                Column() {
                  Text(item.name).fontSize(14).width('100%')
                  Text(item.maskedAddr).fontSize(11).fontColor(COLOR_MUTED).width('100%')
                }.layoutWeight(1)
              }
              .width('100%').padding({ top: 4, bottom: 4 })
            }, (item: PairedDevice) => item.addr)

            Row({ space: 10 }) {
              Button('订阅')
                .fontSize(14).layoutWeight(1)
                .enabled(!this.busy && this.selectedAddr.length > 0)
                .onClick(() => { this.onSubscribe(); })
              Button('退订')
                .fontSize(14).layoutWeight(1)
                .backgroundColor(COLOR_MUTED)
                .enabled(!this.busy && this.snap.subscribed)
                .onClick(() => { this.onUnsubscribe(); })
            }
            .width('100%').margin({ top: 12 })
          }
        }
        .width('100%').padding(12).backgroundColor(COLOR_CARD).borderRadius(10)

        this.sectionHeader(3, '系统通知白名单授权')
        Column() {
          Text('系统授权列表是唯一白名单，本应用不另设开关。未在列表中的来源一律丢弃。')
            .fontSize(12).fontColor(COLOR_MUTED).width('100%')
          Button('打开系统授权页')
            .fontSize(14).width('100%').margin({ top: 10 })
            .enabled(!this.busy)
            .onClick(() => { this.onOpenSettings(); })

          Text('已授权应用：' + this.snap.grantedBundles.length.toString())
            .fontSize(13).width('100%').margin({ top: 12, bottom: 4 })
          if (this.snap.grantedBundles.length === 0) {
            Text('列表为空。在系统授权页里勾选需要转发的应用。')
              .fontSize(12).fontColor(COLOR_MUTED).width('100%')
          } else {
            ForEach(this.snap.grantedBundles, (item: GrantedBundle) => {
              Column() {
                Row({ space: 6 }) {
                  Text(item.appName).fontSize(14).layoutWeight(1)
                  if (item.appIndex > 0) {
                    Text('分身 ' + item.appIndex.toString()).fontSize(11).fontColor(COLOR_MUTED)
                  }
                }.width('100%')
                Text(item.bundleName).fontSize(11).fontColor(COLOR_MUTED).width('100%')
              }
              .width('100%').padding({ top: 4, bottom: 4 })
            }, (item: GrantedBundle) => item.key)
          }
        }
        .width('100%').padding(12).backgroundColor(COLOR_CARD).borderRadius(10)

        this.sectionHeader(4, 'Bark 服务与加密配置')
        Column({ space: 6 }) {
          Text('Device Key 与加密 Key 只存在本机加密数据库里，不进日志、不进备份。')
            .fontSize(12).fontColor(COLOR_MUTED).width('100%')

          Text('服务地址').fontSize(12).fontColor(COLOR_MUTED).width('100%').margin({ top: 8 })
          TextInput({ text: this.cfgServer, placeholder: DEFAULT_BARK_SERVER })
            .fontSize(14)
            .onChange((value: string) => { this.cfgServer = value; this.configDirty = true; })

          Text('Device Key').fontSize(12).fontColor(COLOR_MUTED).width('100%').margin({ top: 8 })
          TextInput({ text: this.cfgDeviceKey, placeholder: '在 Bark App 首页复制' })
            .fontSize(14)
            .type(this.revealSecrets ? InputType.Normal : InputType.Password)
            .onChange((value: string) => { this.cfgDeviceKey = value; this.configDirty = true; })

          Row() {
            Text('加密 Key').fontSize(12).fontColor(COLOR_MUTED).layoutWeight(1)
            Text(this.cfgEncryptKey.length.toString() + ' / 32')
              .fontSize(12)
              .fontColor(this.cfgEncryptKey.length === 32 ? COLOR_OK : COLOR_BAD)
          }.width('100%').margin({ top: 8 })
          TextInput({ text: this.cfgEncryptKey, placeholder: '32 个 ASCII 字符，与 Bark App 完全一致' })
            .fontSize(14)
            .type(this.revealSecrets ? InputType.Normal : InputType.Password)
            .onChange((value: string) => { this.cfgEncryptKey = value; this.configDirty = true; })

          if (this.configDirty) {
            Text('有改动尚未保存，离开本页前请先点保存')
              .fontSize(12).fontColor('#E08A00').width('100%').margin({ top: 8 })
          }

          Row({ space: 10 }) {
            Text(this.revealSecrets ? '隐藏密钥' : '显示密钥')
              .fontSize(13).fontColor('#0A59F7')
              .onClick(() => { this.revealSecrets = !this.revealSecrets; })
            Blank()
            Button(this.configDirty ? '保存 *' : '保存')
              .fontSize(14)
              .enabled(!this.busy)
              .onClick(() => { this.onSaveConfig(); })
          }.width('100%').margin({ top: 12 })

          if (this.configNotice.length > 0) {
            Text(this.configNotice)
              .fontSize(12)
              .fontColor(this.configNotice === '已保存。' ? COLOR_OK : COLOR_BAD)
              .width('100%')
          }
        }
        .width('100%').padding(12).backgroundColor(COLOR_CARD).borderRadius(10)
        .alignItems(HorizontalAlign.Start)

        this.sectionHeader(5, '加密自检与测试发送')
        Column({ space: 6 }) {
          Text('互操作验证通过前，只有内置虚构测试消息会走网络，真实通知不会外发。')
            .fontSize(12).fontColor(COLOR_MUTED).width('100%')

          Button('本地加解密自检（含 100 条 IV 唯一性）')
            .fontSize(14).width('100%').margin({ top: 10 })
            .enabled(!this.busy)
            .onClick(() => { this.onRunSelfTest(); })

          ForEach(this.selfTestResults, (item: SelfTestResult) => {
            Row({ space: 6 }) {
              Text(item.passed ? '通过' : '失败')
                .fontSize(12).fontColor(item.passed ? COLOR_OK : COLOR_BAD).width(30)
              Text(item.name).fontSize(13).width(120)
              Text(item.detail).fontSize(11).fontColor(COLOR_MUTED).layoutWeight(1)
            }.width('100%').padding({ top: 3, bottom: 3 })
          }, (item: SelfTestResult) => item.name)

          Divider().margin({ top: 10, bottom: 6 })

          Text('选择要发送的测试用例：').fontSize(12).fontColor(COLOR_MUTED).width('100%')
          ForEach(this.testCases, (item: SelfTestCase) => {
            Row({ space: 8 }) {
              Radio({ value: item.key, group: 'testCase' })
                .checked(this.selectedCaseKey === item.key)
                .onChange((checked: boolean) => {
                  if (checked) {
                    this.selectedCaseKey = item.key;
                  }
                })
              Text(item.name).fontSize(14).layoutWeight(1)
            }.width('100%')
          }, (item: SelfTestCase) => item.key)

          Button('发送测试消息到 Bark')
            .fontSize(14).width('100%').margin({ top: 10 })
            .enabled(!this.busy)
            .onClick(() => { this.onSendTest(); })

          if (this.sendNotice.length > 0) {
            Text(this.sendNotice)
              .fontSize(12)
              .fontColor(this.sendOk ? COLOR_OK : COLOR_BAD)
              .width('100%')
          }

          Divider().margin({ top: 12, bottom: 8 })

          this.statusRow({
            label: '待投递队列',
            value: `${this.queueDepth} 条`,
            ok: this.queueDepth === 0
          })
          this.statusRow({
            label: '最近成功送达',
            value: formatClock(this.lastSuccessAt),
            ok: this.lastSuccessAt > 0
          })

          Row({ space: 10 }) {
            Button('立即投递')
              .fontSize(13).layoutWeight(1)
              .enabled(!this.busy)
              .onClick(() => { this.onDrainNow(); })
            Button('清空诊断')
              .fontSize(13).layoutWeight(1)
              .backgroundColor(COLOR_MUTED)
              .enabled(!this.busy)
              .onClick(() => { this.onClearDiagnostics(); })
          }.width('100%').margin({ top: 10, bottom: 4 })

          if (this.diagnostics.length === 0) {
            Text('暂无诊断记录。').fontSize(12).fontColor(COLOR_MUTED).width('100%')
          } else {
            ForEach(this.diagnostics, (item: DiagnosticEntry) => {
              Row({ space: 6 }) {
                Text(formatClock(item.createdAt)).fontSize(11).fontColor(COLOR_MUTED).width(58)
                Text(item.outcome).fontSize(11).width(96)
                Text(item.bundleName.length > 0 ? item.bundleName : item.eventId)
                  .fontSize(10).fontColor(COLOR_MUTED).layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (item.detailCode !== 0) {
                  Text(item.detailCode.toString()).fontSize(10).fontColor(COLOR_BAD)
                }
              }.width('100%').padding({ top: 2, bottom: 2 })
            }, (item: DiagnosticEntry) => `${item.eventId}-${item.createdAt}`)
          }
        }
        .width('100%').padding(12).backgroundColor(COLOR_CARD).borderRadius(10)
        .alignItems(HorizontalAlign.Start)

        Blank().height(24)
      }
      .width('100%').padding({ left: 20, right: 20, top: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%').height('100%').scrollBar(BarState.Auto)
  }
}
