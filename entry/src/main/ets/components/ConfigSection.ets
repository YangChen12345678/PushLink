import { Color as Tok, FontSize, Space } from '../theme/Tokens';
import { DEFAULT_BARK_SERVER } from '../service/ConfigStore';
import { ConfigState } from '../viewmodel/ConfigState';
import { SectionCard, SectionHeader } from './Common';

/** 区 4：Bark 服务地址与两个密钥。 */
@Component
export struct ConfigSection {
  @ObjectLink config: ConfigState;
  @Prop busy: boolean = false;
  onSave: () => void = () => {};

  build() {
    Column() {
      SectionHeader({ index: 4, title: 'Bark 服务与加密配置' })
      SectionCard({ alignStart: true, gap: Space.xs + 2 }) {
        Text('Device Key 与加密 Key 只存在本机加密数据库里，不进日志、不进备份。')
          .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%')

        Text('服务地址')
          .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%').margin({ top: Space.sm })
        TextInput({ text: this.config.server, placeholder: DEFAULT_BARK_SERVER })
          .fontSize(FontSize.label)
          .accessibilityText('Bark 服务地址')
          .onChange((value: string) => {
            this.config.server = value;
            this.config.dirty = true;
          })

        Text('Device Key')
          .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%').margin({ top: Space.sm })
        TextInput({ text: this.config.deviceKey, placeholder: '在 Bark App 首页复制' })
          .fontSize(FontSize.label)
          .type(this.config.reveal ? InputType.Normal : InputType.Password)
          .accessibilityText('Bark Device Key')
          .onChange((value: string) => {
            this.config.deviceKey = value;
            this.config.dirty = true;
          })

        Row() {
          Text('加密 Key').fontSize(FontSize.footnote).fontColor(Tok.muted).layoutWeight(1)
          Text(this.config.encryptKey.length.toString() + ' / 32')
            .fontSize(FontSize.footnote)
            .fontColor(this.config.encryptKey.length === 32 ? Tok.ok : Tok.error)
        }.width('100%').margin({ top: Space.sm })
        TextInput({
          text: this.config.encryptKey,
          placeholder: '32 个 ASCII 字符，与 Bark App 完全一致'
        })
          .fontSize(FontSize.label)
          .type(this.config.reveal ? InputType.Normal : InputType.Password)
          .accessibilityText(`加密密钥，当前 ${this.config.encryptKey.length} 个字符，需要 32 个`)
          .onChange((value: string) => {
            this.config.encryptKey = value;
            this.config.dirty = true;
          })

        if (this.config.dirty) {
          Text('有改动尚未保存，离开本页前请先点保存')
            .fontSize(FontSize.footnote).fontColor(Tok.warn).width('100%').margin({ top: Space.sm })
        }

        Row({ space: 10 }) {
          Text(this.config.reveal ? '隐藏密钥' : '显示密钥')
            .fontSize(FontSize.caption).fontColor(Tok.accent)
            .onClick(() => { this.config.reveal = !this.config.reveal; })
          Blank()
          Button(this.config.dirty ? '保存 *' : '保存')
            .fontSize(FontSize.label)
            .enabled(!this.busy)
            .onClick(() => { this.onSave(); })
        }.width('100%').margin({ top: Space.md })

        if (this.config.notice.length > 0) {
          Text(this.config.notice)
            .fontSize(FontSize.footnote)
            .fontColor(this.config.notice === '已保存。' ? Tok.ok : Tok.error)
            .width('100%')
        }
      }
    }
    .width('100%')
  }
}
