import { common } from '@kit.AbilityKit';
import { Color as Tok, FontSize, Radius, Space } from '../theme/Tokens';
import { CryptoSelfTest, SelfTestCase } from '../crypto/CryptoSelfTest';
import { ForwardPipeline } from '../service/ForwardPipeline';
import { LinkState } from '../viewmodel/LinkState';
import { ConfigState } from '../viewmodel/ConfigState';
import { DiagnosticState } from '../viewmodel/DiagnosticState';
import { LinkSection } from '../components/LinkSection';
import { BluetoothSection } from '../components/BluetoothSection';
import { GrantSection } from '../components/GrantSection';
import { ConfigSection } from '../components/ConfigSection';
import { DiagnosticSection } from '../components/DiagnosticSection';

/**
 * 主页面。只做三件事：持有状态、编排跨状态的流程、组装区块。
 *
 * 具体的业务逻辑在 viewmodel/ 下，具体的渲染在 components/ 下。
 * 这样宽屏布局（阶段 G）可以换一套组装方式而复用同一份状态与流程。
 */
@Entry
@Component
struct Index {
  @State link: LinkState = new LinkState();
  @State config: ConfigState = new ConfigState();
  @State diag: DiagnosticState = new DiagnosticState();
  /**
   * 全局忙碌标志。刻意放在页面而不是各状态类里：
   * 页面用 @State 持有对象时只观察引用变化，读不到对象内部属性的变化，
   * 按钮的禁用态会失灵。busy 本来也是 UI 关注点，不属于业务状态。
   */
  @State busy: boolean = false;
  /** 测试用例是常量，取一次即可，避免 ForEach 每帧重建数组。 */
  private readonly testCases: SelfTestCase[] = CryptoSelfTest.cases();

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

  /** getHostContext() 在异常场景可能返回 undefined，调用方必须判空，避免真机上直接崩溃。 */
  private hostContext(): common.UIAbilityContext | undefined {
    return this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
  }

  /** 统一的忙碌包装：无论动作怎么失败，都要把按钮解锁，不能把界面卡死。 */
  private async run(action: (ctx: common.UIAbilityContext) => Promise<void>): Promise<void> {
    const ctx: common.UIAbilityContext | undefined = this.hostContext();
    if (ctx === undefined) {
      this.link.notice = '无法获取页面上下文，请重新打开应用。';
      return;
    }
    this.busy = true;
    try {
      await action(ctx);
    } finally {
      this.busy = false;
    }
  }

  private async loadConfig(): Promise<void> {
    const ctx: common.UIAbilityContext | undefined = this.hostContext();
    if (ctx !== undefined) {
      await this.config.load(ctx);
    }
  }

  private async refreshAll(): Promise<void> {
    this.link.refreshBluetooth();
    await this.link.refreshSubscription();

    const ctx: common.UIAbilityContext | undefined = this.hostContext();
    if (ctx === undefined) {
      return;
    }
    await this.link.syncWhitelist(ctx);
    // 回到前台顺带补投积压：断网期间攒下的队列在这里获得一次清空机会。
    await ForwardPipeline.drain(ctx);
    await this.diag.refresh(ctx);
  }

  build() {
    Scroll() {
      Column() {
        Text('PushLink').fontSize(FontSize.display).fontWeight(FontWeight.Bold).width('100%')
        Text('阶段 B · 通知订阅验证')
          .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%').margin({ top: 2 })

        if (this.link.notice.length > 0) {
          Text(this.link.notice)
            .fontSize(FontSize.caption)
            .fontColor(Tok.error)
            .width('100%')
            .padding(10)
            .backgroundColor(Tok.errorBg)
            .borderRadius(Radius.chip)
            .margin({ top: Space.md })
        }

        LinkSection({ link: this.link })

        BluetoothSection({
          link: this.link,
          busy: this.busy,
          onRequestPermission: () => {
            this.run(async (ctx: common.UIAbilityContext) => {
              await this.link.requestBluetooth(ctx);
            });
          },
          onSubscribe: () => {
            this.run(async (ctx: common.UIAbilityContext) => {
              await this.link.subscribe();
              await this.refreshAll();
            });
          },
          onUnsubscribe: () => {
            this.run(async (ctx: common.UIAbilityContext) => {
              await this.link.unsubscribe();
              await this.refreshAll();
            });
          }
        })

        GrantSection({
          link: this.link,
          busy: this.busy,
          onOpenSettings: () => {
            this.run(async (ctx: common.UIAbilityContext) => {
              await this.link.openSettings(ctx);
              // 半模态关闭后系统状态可能已变，整体重取而非只用返回值。
              await this.refreshAll();
            });
          }
        })

        ConfigSection({
          config: this.config,
          busy: this.busy,
          onSave: () => {
            this.run(async (ctx: common.UIAbilityContext) => {
              await this.config.save(ctx);
            });
          }
        })

        DiagnosticSection({
          config: this.config,
          diag: this.diag,
          busy: this.busy,
          cases: this.testCases,
          onSelfTest: () => {
            this.run(async (ctx: common.UIAbilityContext) => {
              await this.config.runSelfTest();
            });
          },
          onSendTest: () => {
            this.run(async (ctx: common.UIAbilityContext) => {
              await this.config.sendTest();
            });
          },
          onDrain: () => {
            this.run(async (ctx: common.UIAbilityContext) => {
              await this.diag.drainNow(ctx);
            });
          },
          onClearDiagnostics: () => {
            this.run(async (ctx: common.UIAbilityContext) => {
              await this.diag.clear(ctx);
            });
          }
        })

        Blank().height(Space.xxl)
      }
      .width('100%').padding({ left: Space.xl, right: Space.xl, top: Space.xxl })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%').height('100%').scrollBar(BarState.Auto)
  }
}
