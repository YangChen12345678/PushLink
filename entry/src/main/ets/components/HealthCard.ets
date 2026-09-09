import { common } from '@kit.AbilityKit';
import { Color as Tok, FontSize, Radius, Space } from '../theme/Tokens';
import { LinkState } from '../viewmodel/LinkState';
import { Motion } from '../theme/Motion';
import { FlowBar } from './FlowBar';

/** 当前最该先解决的问题。蓝牙是前提，排最前。 */
export enum LinkIssue {
  NONE = 0,
  BLUETOOTH = 1,
  GRANT = 2,
  SUBSCRIBE = 3
}

export function primaryIssue(link: LinkState): LinkIssue {
  if (!link.btEnabled) {
    return LinkIssue.BLUETOOTH;
  }
  if (!link.snap.userGranted) {
    return LinkIssue.GRANT;
  }
  if (!link.snap.subscribed) {
    return LinkIssue.SUBSCRIBE;
  }
  return LinkIssue.NONE;
}

/**
 * 转发链路的健康状态卡。
 *
 * 设计意图：把「哪里坏了」和「怎么修」放在一起。改版前的流程是——
 * 顶部显示「蓝牙未开启」，然后用户得自己往下滚到区 2 去找按钮，
 * 信息和操作被隔开了。
 *
 * 正常时它是一行安静的绿字，只有出问题才变红并长出操作入口。
 */
@Component
export struct HealthCard {
  @ObjectLink link: LinkState;
  @Prop busy: boolean = false;
  /** 省电模式或低电量时不播放持续动画。只在组件创建时判定一次即可。 */
  private canAnimate: boolean = Motion.allowContinuousAnimation();
  onOpenGrantSettings: () => void = () => {};
  onOpenBluetoothSettings: () => void = () => {};
  onGotoSubscribe: () => void = () => {};

  private issueText(): string {
    switch (primaryIssue(this.link)) {
      case LinkIssue.BLUETOOTH:
        return '蓝牙未开启，通知不会转发到 iPhone';
      case LinkIssue.GRANT:
        return '未开启「允许读取本机通知」，系统不会投递回调';
      case LinkIssue.SUBSCRIBE:
        return '尚未登记订阅，请选择一台已配对设备';
      default:
        return '';
    }
  }

  private actionText(): string {
    switch (primaryIssue(this.link)) {
      case LinkIssue.BLUETOOTH:
        return '去开启蓝牙';
      case LinkIssue.GRANT:
        return '打开系统授权页';
      case LinkIssue.SUBSCRIBE:
        return '去订阅';
      default:
        return '';
    }
  }

  private fire(): void {
    switch (primaryIssue(this.link)) {
      case LinkIssue.BLUETOOTH:
        this.onOpenBluetoothSettings();
        break;
      case LinkIssue.GRANT:
        this.onOpenGrantSettings();
        break;
      case LinkIssue.SUBSCRIBE:
        this.onGotoSubscribe();
        break;
      default:
        break;
    }
  }

  build() {
    Row() {
      FlowBar({
        active: this.link.healthy() && this.canAnimate,
        baseColor: this.link.healthy() ? Tok.ok : Tok.error
      })
      this.content()
    }
    .width('100%')
    .backgroundColor(Tok.card)
    .borderRadius(Radius.card)
    // 裁掉溢出，让色条跟着卡片一起圆角。
    .clip(true)
    .accessibilityGroup(true)
    .accessibilityText(this.link.healthy()
      ? '转发链路正常'
      : `转发链路已中断，${this.issueText()}`)
  }

  @Builder
  content() {
    Column() {
      Text('转发链路')
        .fontSize(FontSize.micro)
        .fontColor(Tok.muted)
        .width('100%')

      Text(this.link.healthy() ? '正常' : '已中断')
        .fontSize(25)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.link.healthy() ? Tok.ok : Tok.error)
        .width('100%')
        .margin({ top: 3, bottom: 2 })

      if (this.link.healthy()) {
        Text(this.link.snap.subscribedAddrMasked.length > 0
          ? `订阅设备 ${this.link.snap.subscribedAddrMasked} · 中断提醒${this.link.notifyEnabled ? '已开启' : '未开启'}`
          : `中断提醒${this.link.notifyEnabled ? '已开启' : '未开启'}`)
          .fontSize(FontSize.footnote)
          .fontColor(Tok.muted)
          .width('100%')
      } else {
        Text(this.issueText())
          .fontSize(FontSize.footnote)
          .fontColor(Tok.muted)
          .width('100%')
        Button(this.actionText())
          .fontSize(FontSize.caption)
          .width('100%')
          .margin({ top: Space.md })
          .enabled(!this.busy)
          .onClick(() => { this.fire(); })
      }
    }
    .layoutWeight(1)
    .padding(Space.lg)
    .alignItems(HorizontalAlign.Start)
  }
}
