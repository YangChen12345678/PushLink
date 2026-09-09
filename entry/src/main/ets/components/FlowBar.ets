import { Color as Tok } from '../theme/Tokens';
import { FLOW_DURATION_MS } from '../theme/Motion';

/** 渐变色标：颜色 + 位置（0~1）。 */
type ColorStop = [ResourceColor, number];

/**
 * 健康卡左侧的状态色条。
 *
 * 链路正常且允许动画时，一道高光在色条上来回缓行；
 * 异常或需要省电时退回静态纯色。
 *
 * 让视效承载信息、而不是单纯装饰——「在动」本身就说明链路是活的，
 * 这是它值得存在的唯一理由。
 */
@Component
export struct FlowBar {
  /** 是否播放流光。链路异常或需要省电时为 false。 */
  @Prop @Watch('onActiveChange') active: boolean = false;
  @Prop baseColor: ResourceColor = Tok.muted;
  /** 高光在色条上的位置，0~1。 */
  @State private phase: number = 0.5;

  aboutToAppear(): void {
    this.sync();
  }

  onActiveChange(): void {
    this.sync();
  }

  private sync(): void {
    if (!this.active) {
      // duration 为 0 立即落到静止位置，同时也终止正在跑的循环动画。
      this.getUIContext().animateTo({ duration: 0 }, () => {
        this.phase = 0.5;
      });
      return;
    }
    // Alternate 让高光来回扫，而不是到头后跳回起点造成突兀的闪断。
    this.getUIContext().animateTo({
      duration: FLOW_DURATION_MS,
      iterations: -1,
      curve: Curve.EaseInOut,
      playMode: PlayMode.Alternate
    }, () => {
      this.phase = 1;
    });
  }

  private stops(): ColorStop[] {
    if (!this.active) {
      return [[this.baseColor, 0], [this.baseColor, 1]];
    }
    return [[this.baseColor, 0], [Tok.flowLight, this.phase], [this.baseColor, 1]];
  }

  build() {
    Row()
      .width(4)
      // 用 alignSelf 拉伸而不是 height('100%')：后者要问父容器要高度，
      // 而父容器的高度本该由内容决定，两边互相等对方，结果卡片被撑满整屏。
      .alignSelf(ItemAlign.Stretch)
      .linearGradient({
        angle: 180,
        colors: this.stops()
      })
  }
}
