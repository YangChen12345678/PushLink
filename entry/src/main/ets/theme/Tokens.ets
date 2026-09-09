/**
 * 设计令牌。所有视觉常量的唯一出处。
 *
 * 颜色一律走 $r('app.color.*') 而非字面量：只有资源引用才会跟随系统深浅色切换。
 * 此前颜色写死在页面里，深色模式下卡片与提示底色不会变，与系统组件割裂——
 * 令牌化的同时补齐了 dark 目录，那个缺陷随之修复。
 *
 * 阶段 F 接入 HDS 时，材质与主题色会从这里替换，页面代码不需要再动。
 */
export class Color {
  /** 次要文字、标签、说明。 */
  static readonly muted: Resource = $r('app.color.pl_text_muted');
  /** 状态：正常。 */
  static readonly ok: Resource = $r('app.color.pl_status_ok');
  /** 状态：异常。 */
  static readonly error: Resource = $r('app.color.pl_status_error');
  /** 状态：需要注意但非失败。 */
  static readonly warn: Resource = $r('app.color.pl_status_warn');
  /** 强调色，用于链接与主要动作。 */
  static readonly accent: Resource = $r('app.color.pl_accent');
  /** 卡片与分区容器底色。 */
  static readonly card: Resource = $r('app.color.pl_card_bg');
  /** 错误提示条底色。 */
  static readonly errorBg: Resource = $r('app.color.pl_error_bg');
  /** 强调色之上的前景色。 */
  static readonly onAccent: Resource = $r('app.color.pl_on_accent');
  /** 页面底色。显式声明而非依赖系统默认，材质模糊才有确定的衬底。 */
  static readonly pageBg: Resource = $r('app.color.pl_page_bg');
  /** 顶部光晕。极淡的一层，给材质模糊提供可透出的层次。 */
  static readonly glow: Resource = $r('app.color.pl_glow');
  /** 流光的高光色。 */
  static readonly flowLight: Resource = $r('app.color.pl_flow_light');
  /** 底部标签栏底色。半透明，让内容透过材质模糊隐约可见。 */
  static readonly barBg: Resource = $r('app.color.pl_bar_bg');
}

/** 字号。单位 fp，跟随系统字体缩放。 */
export class FontSize {
  static readonly display: number = 28;
  static readonly title: number = 16;
  static readonly body: number = 15;
  static readonly label: number = 14;
  static readonly caption: number = 13;
  static readonly footnote: number = 12;
  static readonly micro: number = 11;
  static readonly tiny: number = 10;
}

/** 间距。保持 4 的倍数，避免出现视觉上对不齐的奇数值。 */
export class Space {
  static readonly xs: number = 4;
  static readonly sm: number = 8;
  static readonly md: number = 12;
  static readonly lg: number = 16;
  static readonly xl: number = 20;
  static readonly xxl: number = 24;
}

/** 圆角。 */
export class Radius {
  static readonly card: number = 10;
  static readonly chip: number = 8;
  static readonly pill: number = 9;
}

/** 分区容器的统一内边距。 */
export const CARD_PADDING: number = 12;

/**
 * 内容底部要为标签栏让出的高度。
 *
 * 标签栏开了 barOverlap 后浮在内容之上，滚动内容必须自己留出这段距离，
 * 否则最后一个元素会被永久压在栏下面、怎么滚都露不出来。
 */
export const TAB_BAR_OVERLAY: number = 92;

/**
 * 自绘悬浮胶囊栏的高度。
 * 图标 22 + 间距 3 + 标签行高约 14 + 上下留白各 8，取整到 56。
 * 圆角取它的一半，胶囊两端才是正圆。
 */
export const BAR_HEIGHT: number = 56;

/**
 * 悬浮胶囊两侧的留白。
 * 必须显式给死：透明拦截层要按同一个值把触点挪进胶囊坐标系，
 * 用系统默认值的话这个数拿不到，命中就对不齐。
 */
export const BAR_SIDE_MARGIN: number = 20;

/**
 * 顶部固定标题块占的高度：上边距 + 标题行高 + 下边距。
 * 标题从滚动区里提出来固定住之后，内容的初始位置要让开这段（再加上状态栏高度）。
 * 只是初始位置——内容往上滚时照样会盖到标题下面，那部分交给渐变模糊处理。
 */
export const TITLE_BLOCK: number = 76;

/** 顶部渐变模糊的半径。 */
export const TOP_BLUR_RADIUS: number = 28;

/**
 * 满模糊保持到哪个位置。标题底部约在 0.125（上边距 24 + 状态栏 39 + 行高 38，
 * 除以约 809vp 的屏高），所以这里取 0.14 —— 标题整行背后都是满模糊，
 * 背景的字彻底认不出来，不会跟标题抢读。
 */
export const TOP_BLUR_HOLD: number = 0.14;

/**
 * 模糊完全消失的位置，占滚动区高度的比例。
 *
 * 从 TOP_BLUR_HOLD 开始过渡到这里。两段式而不是一路渐变：
 * 一路渐变的话标题所在那一行只剩三成模糊，字还认得出。
 *
 * 按屏高比例给而不是绝对值——linearGradientBlur 的 fractionStops 本身就是比例。
 * 不同屏幕上标题块占比略有出入，阶段 G 做多端适配时再按断点算。
 */
export const TOP_BLUR_END: number = 0.22;
