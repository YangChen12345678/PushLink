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
