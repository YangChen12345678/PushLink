import { Color as Tok, FontSize, Space } from '../theme/Tokens';
import { GrantedBundle } from '../common/Types';
import { LinkState } from '../viewmodel/LinkState';
import { SectionCard, SectionHeader } from './Common';

/** 区 3：系统通知白名单。系统授权列表是唯一来源，本应用不另设开关。 */
@Component
export struct GrantSection {
  @ObjectLink link: LinkState;
  @Prop busy: boolean = false;
  onOpenSettings: () => void = () => {};

  build() {
    Column() {
      SectionHeader({ index: 3, title: '系统通知白名单授权' })
      SectionCard() {
        Text('系统授权列表是唯一白名单，本应用不另设开关。未在列表中的来源一律丢弃。')
          .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%')
        Button('打开系统授权页')
          .fontSize(FontSize.label).width('100%').margin({ top: 10 })
          .enabled(!this.busy)
          .onClick(() => { this.onOpenSettings(); })

        Text('已授权应用：' + this.link.snap.grantedBundles.length.toString())
          .fontSize(FontSize.caption).width('100%').margin({ top: Space.md, bottom: Space.xs })
        if (this.link.snap.grantedBundles.length === 0) {
          Text('列表为空。在系统授权页里勾选需要转发的应用。')
            .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%')
        } else {
          ForEach(this.link.snap.grantedBundles, (item: GrantedBundle) => {
            Column() {
              Row({ space: Space.xs + 2 }) {
                Text(item.appName).fontSize(FontSize.label).layoutWeight(1)
                if (item.appIndex > 0) {
                  Text('分身 ' + item.appIndex.toString())
                    .fontSize(FontSize.micro).fontColor(Tok.muted)
                }
              }.width('100%')
              Text(item.bundleName).fontSize(FontSize.micro).fontColor(Tok.muted).width('100%')
            }
            .width('100%').padding({ top: Space.xs, bottom: Space.xs })
            .accessibilityGroup(true)
            .accessibilityText(item.appIndex > 0
              ? `${item.appName} 分身 ${item.appIndex}，已授权`
              : `${item.appName}，已授权`)
          }, (item: GrantedBundle) => item.key)
        }
      }
    }
    .width('100%')
  }
}
