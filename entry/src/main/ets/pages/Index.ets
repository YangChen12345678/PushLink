import { common } from '@kit.AbilityKit';
import { UIContext, window, uiMaterial } from '@kit.ArkUI';
import { Color as Tok, FontSize, Radius, Space, TAB_BAR_OVERLAY,
  TITLE_BLOCK, TOP_BLUR_RADIUS, TOP_BLUR_HOLD, TOP_BLUR_END, BAR_HEIGHT, BAR_SIDE_MARGIN } from '../theme/Tokens';
import { Glass } from '../theme/Glass';
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
import { Toast } from '../components/Toast';
import { Logger } from '../common/Logger';

const SCOPE: string = 'Index';

const APP_VERSION: string = '1.0.0';

interface TabItem {
  title: string;
  index: number;
  /** 未激活时的空心图标。 */
  icon: Resource;
  /** 激活时的着色图标。 */
  iconOn: Resource;
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
    { title: '状态', index: 0, icon: $r('app.media.tab_status'), iconOn: $r('app.media.tab_status_on') },
    { title: '配置', index: 1, icon: $r('app.media.tab_config'), iconOn: $r('app.media.tab_config_on') },
    { title: '诊断', index: 2, icon: $r('app.media.tab_diag'), iconOn: $r('app.media.tab_diag_on') },
    { title: '我', index: 3, icon: $r('app.media.tab_mine'), iconOn: $r('app.media.tab_mine_on') }
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
    this.readSafeArea();
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
      // 这里直接弹：它是提前返回的分支，走不到收尾处的 flushNotices。
      Toast.show(this.getUIContext(), '无法获取页面上下文，请重新打开应用');
      return;
    }
    this.busy = true;
    try {
      await action(ctx);
    } finally {
      this.busy = false;
      this.flushNotices();
    }
  }

  /**
   * 把状态类里攒下的提示统一弹成浮层，然后清空。
   *
   * 放在 run() 的收尾处而不是每个动作里各写一遍：所有操作都经过 run，
   * 漏掉某一处的可能性就没有了。
   */
  private flushNotices(): void {
    const ui: UIContext = this.getUIContext();
    if (this.link.notice.length > 0) {
      Toast.show(ui, this.link.notice);
      this.link.notice = '';
    }
    if (this.config.notice.length > 0) {
      Toast.show(ui, this.config.notice);
      this.config.notice = '';
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
    await ForwardPipeline.drain(ctx, undefined, 'ui-foreground');
    await this.diag.refresh(ctx);
  }

  /** 材质对象构造一次复用：重新布局时不该反复 new 一个新的。 */
  private material: uiMaterial.ImmersiveMaterial | undefined = Glass.floatingBar();
  /** 小白条占的高度（vp）。悬浮栏要抬到它之上。 */
  @State private bottomInset: number = 0;
  /**
   * 状态栏占的高度（vp）。
   *
   * 窗口铺满全屏后 Tabs 的 height('100%') 就是整个屏幕，而一旦调用 expandSafeArea，
   * ArkUI 原本加在根节点上的避让 padding 也不再兜底。
   * 底部要穿过去、顶部要避开，只能自己把这段高度让出来。
   */
  @State private topInset: number = 0;
  /** 拖动中手指压在哪一格。-1 表示当前没有拖动。 */
  @State private dragIndex: number = -1;
  /** 这次切换是我们自己按落点发起的，onContentWillChange 要放行。 */
  private ownSwitch: boolean = false;
  /** 内置栏刚报过一次落点，它接着发起的切换要否决——它的判定整格偏移。 */
  private barSwitch: boolean = false;
  /** 悬浮栏的实际宽度（vp）。触点要靠它换算成第几格。 */
  @State private barWidth: number = 0;

  /** 该点亮哪一格：拖动时跟着手指走，松手后回到当前页。 */
  private litIndex(): number {
    return this.dragIndex >= 0 ? this.dragIndex : this.activeTab;
  }

  /**
   * 触点落在第几格。TouchObject.x 是相对本组件的局部坐标，除以格宽即可。
   *
   * 这一步之所以自己算，是因为 Tabs 自带的 barFloatingStyle 命中判定整格偏移——
   * 在第 N 格松手会选中第 N-1 格，与起点和方向都无关。
   * 逐个摘掉 adaptToHandedness、barSideMargin、材质的 interactive 都不解决，
   * 而关掉 barOverlap 会让整页无法滚动（它和悬浮栏是耦合的）。
   */
  private hitTest(e: TouchEvent): number {
    const pts: TouchObject[] = e.changedTouches.length > 0 ? e.changedTouches : e.touches;
    if (pts.length === 0 || this.barWidth <= 0) {
      return -1;
    }
    // 覆盖层是整屏宽，而胶囊两侧各缩进 BAR_SIDE_MARGIN，
    // 所以要先把触点挪进胶囊的坐标系再除格宽，否则边缘会差一格。
    const inner: number = this.barWidth - BAR_SIDE_MARGIN * 2;
    if (inner <= 0) {
      return -1;
    }
    const cell: number = inner / this.tabs.length;
    let idx: number = Math.floor((pts[0].x - BAR_SIDE_MARGIN) / cell);
    if (idx < 0) {
      idx = 0;
    }
    if (idx > this.tabs.length - 1) {
      idx = this.tabs.length - 1;
    }
    return idx;
  }

  /** 按下与拖动只挪高亮，抬手才真正切页——拖到哪松手就去哪。 */
  private onBarTouch(e: TouchEvent): void {
    if (e.type === TouchType.Down || e.type === TouchType.Move) {
      this.dragIndex = this.hitTest(e);
      return;
    }
    if (e.type === TouchType.Up) {
      const idx: number = this.hitTest(e);
      this.dragIndex = -1;
      if (idx >= 0 && idx !== this.activeTab) {
        this.ownSwitch = true;
        this.controller.changeIndex(idx);
      }
      return;
    }
    // Cancel：手势被系统接管（例如从边缘划入的返回手势）。只收回高亮，不切页。
    this.dragIndex = -1;
  }

  /**
   * 读出上下两端被系统占掉的高度：上边让开状态栏，下边把悬浮栏抬到小白条之上。
   *
   * 只能在窗口就绪后异步取，所以初值先按 0 渲染一帧再修正。
   */
  private async readSafeArea(): Promise<void> {
    const ctx: common.UIAbilityContext | undefined = this.hostContext();
    if (ctx === undefined) {
      return;
    }
    try {
      const win: window.Window = await window.getLastWindow(ctx);

      // TYPE_SYSTEM 的 topRect 就是状态栏。
      const sys: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = px2vp(sys.topRect.height);

      const nav: window.AvoidArea =
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.bottomInset = px2vp(nav.bottomRect.height);
      Logger.i(SCOPE, `safe area top=${this.topInset}vp bottom=${this.bottomInset}vp`);
    } catch (err) {
      const e: Error = err as Error;
      Logger.w(SCOPE, `read safe area failed: ${e.message}`);
    }
  }

  @Builder
  pageTitle(text: string) {
    Text(text)
      .fontSize(FontSize.display)
      .fontWeight(FontWeight.Bold)
      .width('100%')
      // 只有标题需要躲开状态栏。内容不躲——它滚上去正好被顶部那层渐变模糊糊掉，
      // 和时间、信号图标叠在一起反而是想要的沉浸效果。
      .padding({ left: Space.xl, right: Space.xl, top: Space.xxl + this.topInset })
  }

  @Builder
  tabBar(item: TabItem) {
    Column({ space: 3 }) {
      // 两套 SVG 换图而不是给一套图换色：图标颜色写死在 SVG 里，
      // 深浅色各放一份到 base/ 和 dark/ 由资源系统自己挑。
      // 不用 fillColor 是因为它只作用于 fill，而这些图标主要靠 stroke 成形。
      Image(this.litIndex() === item.index ? item.iconOn : item.icon)
        .width(22).height(22)
        .draggable(false)
      Text(item.title)
        .fontSize(FontSize.tiny)
        .fontColor(this.litIndex() === item.index ? Tok.accent : Tok.muted)
        .fontWeight(this.litIndex() === item.index ? FontWeight.Medium : FontWeight.Normal)
    }
    .width('100%')
    .padding({ top: Space.sm, bottom: Space.sm })
    .accessibilityText(item.title)
  }

  /**
   * 盖在悬浮栏上的透明拦截层，只做一件事：接管命中判定。
   *
   * 外观与材质仍交给官方的 barFloatingStyle——systemMaterial 虽然声明在 CommonMethod 上，
   * 但实测挂到自绘的 Row 上完全不出效果（栏整个透明），
   * 它似乎只对系统预置的浮层类组件生效。而 barFloatingStyle 自己的命中判定整格偏移，
   * 所以取两者之长：材质用它的，命中用自己的。
   *
   * 几何必须和胶囊严格对齐，因此 barSideMargin 显式设成 BAR_SIDE_MARGIN，两边用同一个值。
   *
   * 命中模式必须是 Transparent 而不是 Block：Block 会把事件全吃掉，下层的悬浮栏
   * 收不到触摸，lightEffect 那道跟手高光就不亮了。Transparent 让两边都收到——
   * 内置栏照常发它的光，同时也会按自己那套错误判定切一次页；
   * 我们的 changeIndex 随后把它纠正过来，最终落点以我们的为准。
   */
  @Builder
  floatingBar() {
    Row()
      .width('100%')
      .height(BAR_HEIGHT)
      .margin({ bottom: this.bottomInset > 0 ? this.bottomInset : Space.md })
      .hitTestBehavior(HitTestMode.Transparent)
      .onAreaChange((_old: Area, now: Area) => {
        this.barWidth = Number(now.width);
      })
      .onTouch((e: TouchEvent) => {
        this.onBarTouch(e);
      })
  }

  build() {
    // 胶囊栏叠在 Tabs 之上而不是交给 Tabs 渲染：内置栏的命中判定整格偏移。
    // Tabs 只负责翻页，栏的外观与命中都归自己管。
    Stack({ alignContent: Alignment.Bottom }) {
    // 不把 index 绑成受控属性：当前页由 Tabs 自己管，activeTab 只用于驱动高亮。
    // 两者都绑会让「内部切换 → 回调 → 状态更新 → 重新渲染」形成一圈多余的往返。
    Tabs({ barPosition: BarPosition.End, controller: this.controller }) {

      // ---------- 状态 ----------
      TabContent() {
        // 标题必须待在滚动区外面：留在里面它会跟着滚，也就跟着被自己那层模糊糊掉。
        Stack({ alignContent: Alignment.Top }) {
          Scroll() {
            Column() {
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
                  // 应用无权直接开蓝牙，只能引导。这类提示不经过 run()，直接弹浮层。
                  Toast.show(this.getUIContext(), '请在控制中心或系统设置里打开蓝牙，然后返回本页');
                },
                onGotoSubscribe: () => {
                  Toast.show(this.getUIContext(), '请在下方「蓝牙与订阅」中选择一台设备并点订阅');
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
            .width('100%')
            .padding({
              left: Space.xl,
              right: Space.xl,
              top: TITLE_BLOCK + this.topInset,
              bottom: TAB_BAR_OVERLAY
            })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%').height('100%').scrollBar(BarState.Auto)
          // Spring 是官方的弹性回弹；alwaysEnabled 让内容不满一屏时照样能回弹，
          // 否则「我」这种短页面滑到底是死的，四个标签手感不一致。
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          // 顶部一段渐变模糊：内容滚到标题下方时糊掉，往下迅速恢复清晰。
          // fractionStops 是 [模糊度, 位置] 的二元组，位置必须严格升序。
          .linearGradientBlur(TOP_BLUR_RADIUS, {
            fractionStops: [[1, 0], [1, TOP_BLUR_HOLD], [0, TOP_BLUR_END]],
            direction: GradientDirection.Bottom
          })

          this.pageTitle('PushLink')
        }
      }
      .tabBar(this.tabBar(this.tabs[0]))

      // ---------- 配置 ----------
      TabContent() {
        // 标题必须待在滚动区外面：留在里面它会跟着滚，也就跟着被自己那层模糊糊掉。
        Stack({ alignContent: Alignment.Top }) {
          Scroll() {
            Column() {
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
            .width('100%')
            .padding({
              left: Space.xl,
              right: Space.xl,
              top: TITLE_BLOCK + this.topInset,
              bottom: TAB_BAR_OVERLAY
            })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%').height('100%').scrollBar(BarState.Auto)
          // Spring 是官方的弹性回弹；alwaysEnabled 让内容不满一屏时照样能回弹，
          // 否则「我」这种短页面滑到底是死的，四个标签手感不一致。
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          // 顶部一段渐变模糊：内容滚到标题下方时糊掉，往下迅速恢复清晰。
          // fractionStops 是 [模糊度, 位置] 的二元组，位置必须严格升序。
          .linearGradientBlur(TOP_BLUR_RADIUS, {
            fractionStops: [[1, 0], [1, TOP_BLUR_HOLD], [0, TOP_BLUR_END]],
            direction: GradientDirection.Bottom
          })

          this.pageTitle('配置')
        }
      }
      .tabBar(this.tabBar(this.tabs[1]))

      // ---------- 诊断 ----------
      TabContent() {
        // 标题必须待在滚动区外面：留在里面它会跟着滚，也就跟着被自己那层模糊糊掉。
        Stack({ alignContent: Alignment.Top }) {
          Scroll() {
            Column() {
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
            .width('100%')
            .padding({
              left: Space.xl,
              right: Space.xl,
              top: TITLE_BLOCK + this.topInset,
              bottom: TAB_BAR_OVERLAY
            })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%').height('100%').scrollBar(BarState.Auto)
          // Spring 是官方的弹性回弹；alwaysEnabled 让内容不满一屏时照样能回弹，
          // 否则「我」这种短页面滑到底是死的，四个标签手感不一致。
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          // 顶部一段渐变模糊：内容滚到标题下方时糊掉，往下迅速恢复清晰。
          // fractionStops 是 [模糊度, 位置] 的二元组，位置必须严格升序。
          .linearGradientBlur(TOP_BLUR_RADIUS, {
            fractionStops: [[1, 0], [1, TOP_BLUR_HOLD], [0, TOP_BLUR_END]],
            direction: GradientDirection.Bottom
          })

          this.pageTitle('诊断')
        }
      }
      .tabBar(this.tabBar(this.tabs[2]))

      // ---------- 我 ----------
      TabContent() {
        // 标题必须待在滚动区外面：留在里面它会跟着滚，也就跟着被自己那层模糊糊掉。
        Stack({ alignContent: Alignment.Top }) {
          Scroll() {
            Column() {
              MineSection({
                version: APP_VERSION,
                onPendingTap: (label: string) => {
                  Toast.show(this.getUIContext(), `「${label}」尚未开放`);
                }
              })
            }
            .width('100%')
            .padding({
              left: Space.xl,
              right: Space.xl,
              top: TITLE_BLOCK + this.topInset,
              bottom: TAB_BAR_OVERLAY
            })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%').height('100%').scrollBar(BarState.Auto)
          // Spring 是官方的弹性回弹；alwaysEnabled 让内容不满一屏时照样能回弹，
          // 否则「我」这种短页面滑到底是死的，四个标签手感不一致。
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          // 顶部一段渐变模糊：内容滚到标题下方时糊掉，往下迅速恢复清晰。
          // fractionStops 是 [模糊度, 位置] 的二元组，位置必须严格升序。
          .linearGradientBlur(TOP_BLUR_RADIUS, {
            fractionStops: [[1, 0], [1, TOP_BLUR_HOLD], [0, TOP_BLUR_END]],
            direction: GradientDirection.Bottom
          })

          this.pageTitle('我')
        }
      }
      .tabBar(this.tabBar(this.tabs[3]))
    }
    .barPosition(BarPosition.End)
    // 外观与材质交给官方悬浮栏；命中由上面那层透明拦截层接管。
    .barFloatingStyle({
      barSideMargin: BAR_SIDE_MARGIN,
      barBottomMargin: this.bottomInset > 0 ? this.bottomInset : Space.md,
      adaptToHandedness: false,
      systemMaterial: this.material
    })
    // barOverlap 必须开：内容要能滚到悬浮栏下方，材质才有东西可透。
    // 实测关掉它整页都无法滚动——它和悬浮栏是耦合的，不能单独摘。
    .barOverlap(true)
    .animationDuration(200)
    .onTabBarClick(() => {
      // 内置栏认下了一次落点。它紧接着发起的切换要在 onContentWillChange 里挡掉。
      this.barSwitch = true;
    })
    .onContentWillChange((currentIndex: number, comingIndex: number) => {
      // 三种来源要区别对待：
      //   自己按落点发起的 —— 放行，这是唯一正确的那次；
      //   内置栏发起的     —— 否决，它的命中判定整格偏移；
      //   内容区左右滑动等 —— 放行，与 tabBar 无关。
      // 两种触发顺序都成立：内置栏先报也好、我们先报也好，
      // 各自的标志只会放行/否决自己那一次。
      if (this.ownSwitch) {
        this.ownSwitch = false;
        this.barSwitch = false;
        return true;
      }
      if (this.barSwitch) {
        this.barSwitch = false;
        return false;
      }
      return true;
    })
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
    // pageBg 此前只定义没使用，页面一直是系统默认白，小白条那块自然也是白的。
    .backgroundColor(Tok.pageBg)

      this.floatingBar()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}