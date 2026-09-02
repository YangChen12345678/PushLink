import { Color as Tok, FontSize, Radius, Space, CARD_PADDING } from '../theme/Tokens';

/**
 * 区块标题。
 *
 * 编号是真实的操作顺序（先订阅、再授权、后配置），不是装饰，所以保留。
 */
@Component
export struct SectionHeader {
  // 这两个当前传的是字面量常量，不加 @Prop 也不会出错；
  // 加上是为了统一规则，避免以后有人传变量时踩同样的坑。
  @Prop index: number = 0;
  @Prop title: string = '';

  build() {
    Row({ space: Space.sm }) {
      Text(this.index.toString())
        .fontSize(FontSize.footnote)
        .fontColor(Tok.onAccent)
        .backgroundColor(Tok.muted)
        .borderRadius(Radius.pill)
        .width(18)
        .height(18)
        .textAlign(TextAlign.Center)
      Text(this.title).fontSize(FontSize.title).fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .margin({ top: 18, bottom: Space.sm })
    // 编号对读屏无意义，让整行作为一个标题朗读
    .accessibilityGroup(true)
    .accessibilityText(`第 ${this.index} 部分，${this.title}`)
  }
}

/**
 * 一行「标签 — 值」状态。
 *
 * 做成 @Component 而不是 @Builder：@Builder 传简单类型时是按值传递，
 * 状态变化不会触发内部刷新，页面上会出现一半新值一半旧值的假象。
 * 组件的成员变量则是真正响应式的。
 */
@Component
export struct StatusRow {
  // 必须是 @Prop。@Component 的普通成员变量只在首次创建时赋值，
  // 父组件重渲染时不会同步——那会让状态行永远停在初始值，
  // 页面上出现「订阅已登记：否」却同时显示订阅设备地址这种自相矛盾的画面。
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop ok: boolean = false;

  build() {
    Row() {
      Text(this.label).fontSize(FontSize.label).fontColor(Tok.muted).layoutWeight(1)
      Text(this.value).fontSize(FontSize.label).fontColor(this.ok ? Tok.ok : Tok.error)
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
    .accessibilityGroup(true)
    .accessibilityText(`${this.label}：${this.value}`)
  }
}

@Builder
function emptyContent() {
}

/**
 * 分区容器。用 @BuilderParam 承载内容，让卡片外观集中在一处——
 * 阶段 F 接入 HDS 材质时只改这里，五个区块不用动。
 */
@Component
export struct SectionCard {
  /** 是否让子项左对齐。配置类区块需要，纯状态列表不需要。 */
  @Prop alignStart: boolean = false;
  @Prop gap: number = 0;
  @BuilderParam content: () => void = emptyContent;

  build() {
    Column({ space: this.gap }) {
      this.content()
    }
    .width('100%')
    .padding(CARD_PADDING)
    .backgroundColor(Tok.card)
    .borderRadius(Radius.card)
    .alignItems(this.alignStart ? HorizontalAlign.Start : HorizontalAlign.Center)
  }
}
