import { common } from '@kit.AbilityKit';
import { Color as Tok, FontSize, Radius, Space } from '../theme/Tokens';
import { CryptoSelfTest, SelfTestCase } from '../crypto/CryptoSelfTest';
import { ForwardPipeline } from '../service/ForwardPipeline';
import { HealthMonitor } from '../service/HealthMonitor';
import { LinkState } from '../viewmodel/LinkState';
import { ConfigState } from '../viewmodel/ConfigState';
import { DiagnosticState } from '../viewmodel/DiagnosticState';
import { HealthCard } from '../components/HealthCard';
import { BluetoothSection } from '../components/BluetoothSection';
import { GrantSection } from '../components/GrantSection';
import { ConfigSection } from '../components/ConfigSection';
import { SelfTestSection } from '../components/SelfTestSection';
import { DiagnosticSection } from '../components/DiagnosticSection';
import { MineSection } from '../components/MineSection';
import { GroupTitle, SectionCard } from '../components/Common';

const APP_VERSION: string = '1.0.0';

interface TabItem {
  title: string;
  index: number;
}

/**
 * 主页面。分四个标签：状态、配置、诊断、我。
 *
 * 分屏的依据是使用频率：链路状态每天要看，Bark 配置和加密自检装完基本不再碰，
 * 诊断只在怀疑哪里不对时才来。之前五个区块堆成一条长滚动，视觉权重完全一样。
 *
 * 标签骨架用原生 Tabs 而不是 HdsTabs：骨架出问题会影响整个界面，
 * 而 HdsTabs 的增量能力（迷你栏、浮动样式）这里用不上。
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
  @State activeTab: number = 0;
  private readonly testCases: SelfTestCase[] = CryptoSelfTest.cases();
  private readonly tabs: TabItem[] = [
    { title: '状态', index: 0 },
    { title: '配置', index: 1 },
    { title: '诊断', index: 2 },
    { title: '我', index: 3 }
  ];
  private controller: TabsController = new TabsController();

  /**
   * 蓝牙状态一变就刷新界面。
   * 用箭头函数属性而非方法，是为了让 this 稳定绑定到实例，
   * 同时保证注册与注销传的是同一个引用——方法引用每次取值都是新对象，注销会失败。
   */
  private bluetoothWatcher: () => void = () => {
    this.link.refreshBluetooth();
  };

  /**
   * 配置只在页面创建时读一次。
   * 绝不能放进 onPageShow：那样每次回到前台都会用库里的旧值覆盖用户正在输入、
   * 尚未保存的 Device Key 和加密 Key，输入内容会凭空消失。
   */
  aboutToAppear(): void {
    this.loadConfig();
    HealthMonitor.addWatcher(this.bluetoothWatcher);
  }

  aboutToDisappear(): void {
    HealthMonitor.removeWatcher(this.bluetoothWatcher);
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

  @Builder
  tabBar(item: TabItem) {
    Column({ space: 3 }) {
      // 用色块而非图标：项目没有自己的图标集，随便找的图标反而拉低一致性。
      Row()
        .width(18).height(18).borderRadius(5)
        .backgroundColor(this.activeTab === item.index ? Tok.accent : Tok.muted)
        .opacity(this.activeTab === item.index ? 1 : 0.4)
      Text(item.title)
        .fontSize(FontSize.tiny)
        .fontColor(this.activeTab === item.index ? Tok.accent : Tok.muted)
        .fontWeight(this.activeTab === item.index ? FontWeight.Medium : FontWeight.Normal)
    }
    .width('100%')
    .padding({ top: Space.sm, bottom: Space.sm })
    .accessibilityText(item.title)
  }

  build() {
    // 不把 index 绑成受控属性：当前页由 Tabs 自己管，activeTab 只用于驱动 tabBar 高亮。
    // 两者都绑会让「内部切换 → 回调 → 状态更新 → 重新渲染」形成一圈多余的往返。
    Tabs({ barPosition: BarPosition.End, controller: this.controller }) {

      // ---------- 状态 ----------
      TabContent() {
        Scroll() {
          Column() {
            Text('PushLink')
              .fontSize(FontSize.display).fontWeight(FontWeight.Bold).width('100%')
              .margin({ bottom: Space.md })

            if (this.link.notice.length > 0) {
              Text(this.link.notice)
                .fontSize(FontSize.caption).fontColor(Tok.error).width('100%')
                .padding(10).backgroundColor(Tok.errorBg).borderRadius(Radius.chip)
                .margin({ bottom: Space.md })
            }

            HealthCard({
              link: this.link,
              busy: this.busy,
              onOpenGrantSettings: () => {
                this.run(async (ctx: common.UIAbilityContext) => {
                  await this.link.openSettings(ctx);
                  await this.refreshAll();
                });
              },
              onOpenBluetoothSettings: () => {
                this.link.notice = '请在控制中心或系统设置里打开蓝牙，然后返回本页。';
              },
              onGotoSubscribe: () => {
                this.link.notice = '请在下方「蓝牙与订阅」中选择一台设备并点订阅。';
              }
            })

            if (!this.link.notifyEnabled) {
              GroupTitle({ text: '中断提醒' })
              SectionCard({ alignStart: true }) {
                Text('开启后，蓝牙被关闭导致转发中断时会收到提示。'
                  + '否则链路断了不会有任何征兆。')
                  .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%')
                Button('开启中断提醒')
                  .fontSize(FontSize.label).width('100%').margin({ top: Space.sm })
                  .enabled(!this.busy)
                  .onClick(() => {
                    this.run(async (ctx: common.UIAbilityContext) => {
                      await this.link.requestNotifyPermission(ctx);
                    });
                  })
              }
            }

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
                  await this.refreshAll();
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
      .tabBar(this.tabBar(this.tabs[0]))

      // ---------- 配置 ----------
      TabContent() {
        Scroll() {
          Column() {
            Text('配置')
              .fontSize(FontSize.display).fontWeight(FontWeight.Bold).width('100%')
              .margin({ bottom: Space.sm })

            ConfigSection({
              config: this.config,
              busy: this.busy,
              onSave: () => {
                this.run(async (ctx: common.UIAbilityContext) => {
                  await this.config.save(ctx);
                });
              }
            })

            SelfTestSection({
              config: this.config,
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
              }
            })
          }
          .width('100%').padding({ left: Space.xl, right: Space.xl, top: Space.xxl })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%').height('100%').scrollBar(BarState.Auto)
      }
      .tabBar(this.tabBar(this.tabs[1]))

      // ---------- 诊断 ----------
      TabContent() {
        Scroll() {
          Column() {
            Text('诊断')
              .fontSize(FontSize.display).fontWeight(FontWeight.Bold).width('100%')
              .margin({ bottom: Space.md })

            DiagnosticSection({
              diag: this.diag,
              busy: this.busy,
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
          }
          .width('100%').padding({ left: Space.xl, right: Space.xl, top: Space.xxl })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%').height('100%').scrollBar(BarState.Auto)
      }
      .tabBar(this.tabBar(this.tabs[2]))

      // ---------- 我 ----------
      TabContent() {
        Scroll() {
          Column() {
            Text('我')
              .fontSize(FontSize.display).fontWeight(FontWeight.Bold).width('100%')
              .margin({ bottom: Space.md })

            MineSection({
              version: APP_VERSION,
              onPendingTap: (label: string) => {
                this.link.notice = `「${label}」尚未开放。`;
              }
            })
          }
          .width('100%').padding({ left: Space.xl, right: Space.xl, top: Space.xxl })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%').height('100%').scrollBar(BarState.Auto)
      }
      .tabBar(this.tabBar(this.tabs[3]))
    }
    .barPosition(BarPosition.End)
    .animationDuration(200)
    .onAnimationStart((index: number, targetIndex: number) => {
      // 高亮必须在动画「开始」时就跟上。
      // 官方文档对自定义 tabBar 有明确提示：只靠 onChange 会滞后，
      // 因为它是在切换动画结束之后才触发的——快速连点时高亮会明显落后于内容。
      this.activeTab = targetIndex;
    })
    .onChange((index: number) => {
      // 兜底：animationDuration 为 0 时 onAnimationStart 不会触发。
      // 重复赋同一个值没有副作用。
      this.activeTab = index;
    })
    .width('100%')
    .height('100%')
  }
}
