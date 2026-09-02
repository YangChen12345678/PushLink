import { Color as Tok, FontSize, Space } from '../theme/Tokens';
import { LinkState } from '../viewmodel/LinkState';
import { SectionCard, SectionHeader, StatusRow } from './Common';

/** 区 1：转发链路的综合状态。纯展示，无动作。 */
@Component
export struct LinkSection {
  @ObjectLink link: LinkState;

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
