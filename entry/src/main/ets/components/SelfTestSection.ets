import { Color as Tok, FontSize, Space } from '../theme/Tokens';
import { SelfTestCase, SelfTestResult } from '../crypto/CryptoSelfTest';
import { ConfigState } from '../viewmodel/ConfigState';
import { GroupTitle, SectionCard } from './Common';

/**
 * 加密自检与测试发送。
 *
 * 和 Bark 配置同处「配置」页：它们是同一类事——装的时候用，之后基本不再碰。
 */
@Component
export struct SelfTestSection {
  @ObjectLink config: ConfigState;
  @Prop busy: boolean = false;
  @Prop cases: SelfTestCase[] = [];
  onSelfTest: () => void = () => {};
  onSendTest: () => void = () => {};

  /** 自检整体是否通过。折叠成一行，展开才看明细。 */
  private allPassed(): boolean {
    if (this.config.selfTestResults.length === 0) {
      return false;
    }
    for (const item of this.config.selfTestResults) {
      if (!item.passed) {
        return false;
      }
    }
    return true;
  }

  build() {
    Column() {
      GroupTitle({ text: '加密自检' })
      SectionCard({ alignStart: true, gap: Space.xs + 2 }) {
        Text('往返测试证明不了互操作性——密文与标签拼错位置时，加解密两边会错得一模一样。'
          + '只有比对 NIST 标准向量才能验证输出格式。')
          .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%')

        Button('运行本地自检')
          .fontSize(FontSize.label).width('100%').margin({ top: Space.sm })
          .enabled(!this.busy)
          .onClick(() => { this.onSelfTest(); })

        if (this.config.selfTestResults.length > 0) {
          Row() {
            Text('自检结果').fontSize(FontSize.caption).fontColor(Tok.muted).layoutWeight(1)
            Text(this.allPassed() ? '全部通过' : '存在失败项')
              .fontSize(FontSize.caption)
              .fontColor(this.allPassed() ? Tok.ok : Tok.error)
          }.width('100%').margin({ top: Space.sm })

          ForEach(this.config.selfTestResults, (item: SelfTestResult) => {
            Row({ space: Space.xs + 2 }) {
              Text(item.passed ? '通过' : '失败')
                .fontSize(FontSize.footnote)
                .fontColor(item.passed ? Tok.ok : Tok.error)
                .width(30)
              Text(item.name).fontSize(FontSize.footnote).width(116)
              Text(item.detail).fontSize(FontSize.micro).fontColor(Tok.muted).layoutWeight(1)
            }
            .width('100%').padding({ top: 3, bottom: 3 })
            .accessibilityGroup(true)
            .accessibilityText(`${item.name}，${item.passed ? '通过' : '失败'}`)
          }, (item: SelfTestResult) => item.name)
        }
      }

      GroupTitle({ text: '测试发送' })
      SectionCard({ alignStart: true, gap: Space.xs + 2 }) {
        Text('发送一条内置虚构消息，用于验证与 iPhone 的互通。真实通知不经此入口。')
          .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%')

        ForEach(this.cases, (item: SelfTestCase) => {
          Row({ space: Space.sm }) {
            Radio({ value: item.key, group: 'testCase' })
              .checked(this.config.selectedCaseKey === item.key)
              .onChange((checked: boolean) => {
                if (checked) {
                  this.config.selectedCaseKey = item.key;
                }
              })
            Text(item.name).fontSize(FontSize.label).layoutWeight(1)
          }.width('100%')
        }, (item: SelfTestCase) => item.key)

        Button('发送测试消息到 Bark')
          .fontSize(FontSize.label).width('100%').margin({ top: Space.sm })
          .enabled(!this.busy)
          .onClick(() => { this.onSendTest(); })

        if (this.config.sendNotice.length > 0) {
          Text(this.config.sendNotice)
            .fontSize(FontSize.footnote)
            .fontColor(this.config.sendOk ? Tok.ok : Tok.error)
            .width('100%')
        }
      }

      Blank().height(Space.xxl)
    }
    .width('100%')
  }
}
