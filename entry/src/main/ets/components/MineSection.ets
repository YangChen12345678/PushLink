import { Color as Tok, FontSize, Radius, Space } from '../theme/Tokens';
import { SectionCard } from './Common';

/** 签名到期日。到这天应用会无法启动，需在 DevEco 重新签名覆盖安装。 */
const SIGNATURE_EXPIRY: string = '2027-09-01';
const SIGNATURE_EXPIRY_MS: number = new Date('2027-09-01T00:00:00').getTime();
/** 提前多久开始提醒续签。 */
const EXPIRY_WARN_DAYS: number = 60;

interface MineRowParam {
  label: string;
  value: string;
  /** 尚未实现的功能标记为预留，点击只给一句说明。 */
  pending: boolean;
  /** 值是否需要用告警色强调。 */
  alert: boolean;
}

/**
 * 「我」页面：与转发本身无关的功能。
 *
 * 大部分是为将来预留的位置（账号、备份、更新），现在就能用的只有两项——
 * 版本号和签名有效期。后者值得早点放上来：2027-09-01 到期时应用会直接
 * 打不开，而那时多半已经想不起来原因了。
 */
@Component
export struct MineSection {
  @Prop version: string = '';
  onPendingTap: (label: string) => void = () => {};

  /** 距签名到期还剩多少天。到期后为负数。 */
  private daysToExpiry(): number {
    return Math.floor((SIGNATURE_EXPIRY_MS - Date.now()) / 86400000);
  }

  private expiryValue(): string {
    const days: number = this.daysToExpiry();
    if (days < 0) {
      return '已过期';
    }
    if (days <= EXPIRY_WARN_DAYS) {
      return `${SIGNATURE_EXPIRY}（剩 ${days} 天）`;
    }
    return SIGNATURE_EXPIRY;
  }

  @Builder
  mineRow($$: MineRowParam) {
    Row({ space: Space.sm }) {
      Text($$.label).fontSize(FontSize.label).layoutWeight(1)
      if ($$.pending) {
        Text('预留')
          .fontSize(FontSize.tiny)
          .fontColor(Tok.muted)
          .border({ width: 1, color: Tok.muted, radius: 4 })
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
      }
      if ($$.value.length > 0) {
        Text($$.value)
          .fontSize(FontSize.caption)
          .fontColor($$.alert ? Tok.warn : Tok.muted)
      }
      Text('›').fontSize(FontSize.title).fontColor(Tok.muted)
    }
    .width('100%')
    .padding({ top: Space.sm, bottom: Space.sm })
    .onClick(() => {
      if ($$.pending) {
        this.onPendingTap($$.label);
      }
    })
    .accessibilityGroup(true)
    .accessibilityText($$.pending ? `${$$.label}，功能尚未开放` : `${$$.label}，${$$.value}`)
  }

  build() {
    Column() {
      SectionCard({ alignStart: true }) {
        Row({ space: Space.md }) {
          Text('◔')
            .fontSize(20)
            .fontColor(Tok.muted)
            .width(46)
            .height(46)
            .borderRadius(23)
            .backgroundColor(Tok.card)
            .textAlign(TextAlign.Center)
          Column() {
            Text('未登录').fontSize(FontSize.title).fontWeight(FontWeight.Medium).width('100%')
            Text('登录后可在多设备间同步配置')
              .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Text('预留')
            .fontSize(FontSize.tiny).fontColor(Tok.muted)
            .border({ width: 1, color: Tok.muted, radius: 4 })
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        }
        .width('100%')
        .padding({ top: Space.xs, bottom: Space.xs })
        .onClick(() => { this.onPendingTap('账号'); })
      }

      Text('数据')
        .fontSize(FontSize.micro).fontColor(Tok.muted).width('100%')
        .margin({ top: Space.md, bottom: Space.xs, left: Space.xs })
      SectionCard({ alignStart: true }) {
        this.mineRow({ label: '备份与恢复', value: '', pending: true, alert: false })
        Divider()
        this.mineRow({ label: '导出配置二维码', value: '', pending: true, alert: false })
      }

      Text('应用')
        .fontSize(FontSize.micro).fontColor(Tok.muted).width('100%')
        .margin({ top: Space.md, bottom: Space.xs, left: Space.xs })
      SectionCard({ alignStart: true }) {
        this.mineRow({ label: '检查更新', value: this.version, pending: true, alert: false })
        Divider()
        this.mineRow({
          label: '签名有效期',
          value: this.expiryValue(),
          pending: false,
          alert: this.daysToExpiry() <= EXPIRY_WARN_DAYS
        })
      }
      if (this.daysToExpiry() <= EXPIRY_WARN_DAYS) {
        Text('签名即将到期。到期后应用无法启动，需在 DevEco Studio 重新签名并覆盖安装。')
          .fontSize(FontSize.footnote).fontColor(Tok.warn).width('100%')
          .margin({ top: Space.sm, left: Space.xs })
      }

      Text('关于')
        .fontSize(FontSize.micro).fontColor(Tok.muted).width('100%')
        .margin({ top: Space.md, bottom: Space.xs, left: Space.xs })
      SectionCard({ alignStart: true }) {
        this.mineRow({ label: '关于 PushLink', value: '', pending: true, alert: false })
        Divider()
        this.mineRow({ label: '隐私政策', value: '', pending: true, alert: false })
        Divider()
        this.mineRow({ label: '开源许可', value: '', pending: true, alert: false })
      }

      Blank().height(Space.xxl)
    }
    .width('100%')
  }
}
