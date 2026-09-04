import { Color as Tok, FontSize, Space } from '../theme/Tokens';
import { PairedDevice } from '../service/BluetoothService';
import { LinkState } from '../viewmodel/LinkState';
import { GroupTitle, SectionCard, StatusRow } from './Common';

/** 区 2：蓝牙权限、已配对设备选择、订阅登记。 */
@Component
export struct BluetoothSection {
  @ObjectLink link: LinkState;
  @Prop busy: boolean = false;
  onRequestPermission: () => void = () => {};
  onSubscribe: () => void = () => {};
  onUnsubscribe: () => void = () => {};

  build() {
    Column() {
      GroupTitle({ text: '蓝牙与订阅' })
      SectionCard() {
        StatusRow({
          label: '蓝牙权限',
          value: this.link.btGranted ? '已授予' : '未授予',
          ok: this.link.btGranted
        })
        StatusRow({
          label: '蓝牙开关',
          value: this.link.btEnabled ? '已开启' : '未开启',
          ok: this.link.btEnabled
        })

        if (!this.link.btGranted) {
          Button('申请蓝牙权限')
            .fontSize(FontSize.label).width('100%').margin({ top: 10 })
            .enabled(!this.busy)
            .onClick(() => { this.onRequestPermission(); })
        } else if (!this.link.btEnabled) {
          Text('请在系统里打开蓝牙后返回本页。')
            .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%').margin({ top: Space.sm })
        } else if (this.link.devices.length === 0) {
          Text(this.link.deviceError === 0
            ? '没有已配对设备。请先在系统设置里完成配对，本应用不发起配对。'
            : '读取配对列表失败，错误码 ' + this.link.deviceError.toString() + '。')
            .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%').margin({ top: Space.sm })
        } else {
          Text('选择一台设备作为订阅登记对象：')
            .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%')
            .margin({ top: 10, bottom: Space.xs })
          ForEach(this.link.devices, (item: PairedDevice) => {
            Row({ space: Space.sm }) {
              Radio({ value: item.addr, group: 'pairedDevices' })
                .checked(this.link.selectedAddr === item.addr)
                .onChange((checked: boolean) => {
                  if (checked) {
                    this.link.selectedAddr = item.addr;
                  }
                })
              Column() {
                Text(item.name).fontSize(FontSize.label).width('100%')
                Text(item.maskedAddr).fontSize(FontSize.micro).fontColor(Tok.muted).width('100%')
              }.layoutWeight(1)
            }
            .width('100%').padding({ top: Space.xs, bottom: Space.xs })
            .accessibilityGroup(true)
            .accessibilityText(`设备 ${item.name}，${this.link.selectedAddr === item.addr ? '已选中' : '未选中'}`)
          }, (item: PairedDevice) => item.addr)

          Row({ space: 10 }) {
            Button('订阅')
              .fontSize(FontSize.label).layoutWeight(1)
              .enabled(!this.busy && this.link.selectedAddr.length > 0)
              .onClick(() => { this.onSubscribe(); })
            Button('退订')
              .fontSize(FontSize.label).layoutWeight(1)
              .backgroundColor(Tok.muted)
              .enabled(!this.busy && this.link.snap.subscribed)
              .onClick(() => { this.onUnsubscribe(); })
          }
          .width('100%').margin({ top: Space.md })
        }
      }
    }
    .width('100%')
  }
}
