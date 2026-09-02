import { Color as Tok, FontSize, Space } from '../theme/Tokens';
import { LinkState } from '../viewmodel/LinkState';
import { SectionCard, SectionHeader, StatusRow } from './Common';

/** 区 1：转发链路的综合状态。 */
@Component
export struct LinkSection {
  @ObjectLink link: LinkState;
  @Prop busy: boolean = false;
  onRequestNotify: () => void = () => {};

  build() {
    Column() {
      SectionHeader({ index: 1, title: 'ACL / 通知订阅状态' })
      SectionCard() {
        // 综合健康状态放在最前：单看"订阅已登记"会误导——
        // 蓝牙关闭时它照样是"是"，但一条通知都收不到。
        StatusRow({
          label: '转发链路',
          value: this.link.healthDetail(),
          ok: this.link.healthy()
        })
        StatusRow({
          label: '订阅已登记',
          value: this.link.snap.subscribed ? '是' : '否',
          ok: this.link.snap.subscribed
        })
        if (this.link.snap.subscribed && this.link.snap.subscribedAddrMasked.length > 0) {
          StatusRow({ label: '订阅设备', value: this.link.snap.subscribedAddrMasked, ok: true })
        }
        StatusRow({
          label: '允许读取本机通知',
          value: this.link.snap.userGranted ? '已开启' : '未开启',
          ok: this.link.snap.userGranted
        })
        StatusRow({
          label: '中断提醒',
          value: this.link.notifyEnabled ? '已开启' : '未开启',
          ok: this.link.notifyEnabled
        })
        if (!this.link.notifyEnabled) {
          // 没有这条提醒，蓝牙被关掉后用户只会在某天发现「iPhone 半天没消息了」，
          // 却不知道原因。所以值得专门引导开启。
          Text('开启后，蓝牙被关闭导致转发中断时会收到提示。')
            .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%')
            .margin({ top: Space.xs })
          Button('开启中断提醒')
            .fontSize(FontSize.label).width('100%').margin({ top: Space.sm })
            .enabled(!this.busy)
            .onClick(() => { this.onRequestNotify(); })
        }
        if (this.link.snap.lastError.length > 0) {
          Text(this.link.snap.lastError)
            .fontSize(FontSize.footnote)
            .fontColor(Tok.error)
            .width('100%')
            .margin({ top: Space.xs + 2 })
        }
      }
    }
    .width('100%')
  }
}
