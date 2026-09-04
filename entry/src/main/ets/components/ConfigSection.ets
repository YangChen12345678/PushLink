import { Color as Tok, FontSize, Radius, Space } from '../theme/Tokens';
import { DEFAULT_BARK_SERVER } from '../service/ConfigStore';
import { ConfigState } from '../viewmodel/ConfigState';
import { GroupTitle, SectionCard } from './Common';

/**
 * maskedField 的参数必须包成对象。
 * @Builder 传简单类型时是按值传递，掩码点数在「显示→编辑→隐藏」后会停在旧值。
 */
interface MaskedFieldParam {
  text: string;
  hint: string;
}

/** 隐藏状态下的密钥占位。不暴露真实长度以外的任何信息。 */
function maskSecret(value: string): string {
  if (value.length === 0) {
    return '未填写';
  }
  const dots: number = value.length > 20 ? 20 : value.length;
  let masked: string = '';
  for (let i = 0; i < dots; i++) {
    masked += '•';
  }
  return masked;
}

/** 区 4：Bark 服务地址与两个密钥。 */
@Component
export struct ConfigSection {
  @ObjectLink config: ConfigState;
  @Prop busy: boolean = false;
  onSave: () => void = () => {};

  /** 隐藏态的密钥字段。做成输入框的样子，点一下即可切换为可编辑。 */
  @Builder
  maskedField($$: MaskedFieldParam) {
    Row() {
      Text($$.text).fontSize(FontSize.label).fontColor(Tok.muted)
    }
    .width('100%')
    .height(40)
    .padding({ left: Space.md, right: Space.md })
    .border({ width: 1, color: Tok.muted, radius: Radius.chip })
    .onClick(() => { this.config.reveal = true; })
    .accessibilityText($$.hint)
  }

  build() {
    Column() {
      GroupTitle({ text: 'Bark 服务' })
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
        if (this.config.reveal) {
          // 一律用 Normal 而不是 Password：密码输入框会唤起安全键盘，
          // 而安全键盘禁用剪贴板，导致粘贴不了从 Bark App 复制来的 Key。
          TextInput({ text: this.config.deviceKey, placeholder: '在 Bark App 首页复制' })
            .fontSize(FontSize.label)
            .type(InputType.Normal)
            .accessibilityText('Bark Device Key')
            .onChange((value: string) => {
              this.config.deviceKey = value;
              this.config.dirty = true;
            })
        } else {
          this.maskedField({ text: maskSecret(this.config.deviceKey), hint: 'Device Key 已隐藏，点击显示并编辑' })
        }

        Row() {
          Text('加密 Key').fontSize(FontSize.footnote).fontColor(Tok.muted).layoutWeight(1)
          Text(this.config.encryptKey.length.toString() + ' / 32')
            .fontSize(FontSize.footnote)
            .fontColor(this.config.encryptKey.length === 32 ? Tok.ok : Tok.error)
        }.width('100%').margin({ top: Space.sm })
        if (this.config.reveal) {
          TextInput({
            text: this.config.encryptKey,
            placeholder: '32 个 ASCII 字符，与 Bark App 完全一致'
          })
            .fontSize(FontSize.label)
            .type(InputType.Normal)
            .accessibilityText(`加密密钥，当前 ${this.config.encryptKey.length} 个字符，需要 32 个`)
            .onChange((value: string) => {
              this.config.encryptKey = value;
              this.config.dirty = true;
            })
        } else {
          this.maskedField({ text: maskSecret(this.config.encryptKey), hint: '加密密钥已隐藏，点击显示并编辑' })
        }

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
