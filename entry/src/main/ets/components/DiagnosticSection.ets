import { Color as Tok, FontSize, Space } from '../theme/Tokens';
import { SelfTestCase, SelfTestResult } from '../crypto/CryptoSelfTest';
import { DiagnosticEntry } from '../service/DiagnosticStore';
import { ConfigState } from '../viewmodel/ConfigState';
import { DiagnosticState, formatClock } from '../viewmodel/DiagnosticState';
import { SectionCard, SectionHeader, StatusRow } from './Common';

/**
 * 区 5：加密自检、测试发送、队列与诊断记录。
 *
 * 这一区同时依赖 ConfigState（自检与发送）和 DiagnosticState（队列与记录）——
 * 说明当前的区块划分把两件事混在了一起。阶段 F 改标签页时会拆开，
 * 此处保持原样以满足「重构不改变视觉」。
 */
@Component
export struct DiagnosticSection {
  @ObjectLink config: ConfigState;
  @ObjectLink diag: DiagnosticState;
  @Prop busy: boolean = false;
  /** 测试用例是常量，由页面传入，避免 ForEach 每帧重建数组。 */
  @Prop cases: SelfTestCase[] = [];
  onSelfTest: () => void = () => {};
  onSendTest: () => void = () => {};
  onDrain: () => void = () => {};
  onClearDiagnostics: () => void = () => {};

  build() {
    Column() {
      SectionHeader({ index: 5, title: '加密自检与测试发送' })
      SectionCard({ alignStart: true, gap: Space.xs + 2 }) {
        Text('互操作验证通过前，只有内置虚构测试消息会走网络，真实通知不会外发。')
          .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%')

        Button('本地加解密自检（含 100 条 IV 唯一性）')
          .fontSize(FontSize.label).width('100%').margin({ top: 10 })
          .enabled(!this.busy)
          .onClick(() => { this.onSelfTest(); })

        ForEach(this.config.selfTestResults, (item: SelfTestResult) => {
          Row({ space: Space.xs + 2 }) {
            Text(item.passed ? '通过' : '失败')
              .fontSize(FontSize.footnote)
              .fontColor(item.passed ? Tok.ok : Tok.error)
              .width(30)
            Text(item.name).fontSize(FontSize.caption).width(120)
            Text(item.detail).fontSize(FontSize.micro).fontColor(Tok.muted).layoutWeight(1)
          }
          .width('100%').padding({ top: 3, bottom: 3 })
          .accessibilityGroup(true)
          .accessibilityText(`${item.name}，${item.passed ? '通过' : '失败'}，${item.detail}`)
        }, (item: SelfTestResult) => item.name)

        Divider().margin({ top: 10, bottom: Space.xs + 2 })

        Text('选择要发送的测试用例：')
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
          .fontSize(FontSize.label).width('100%').margin({ top: 10 })
          .enabled(!this.busy)
          .onClick(() => { this.onSendTest(); })

        if (this.config.sendNotice.length > 0) {
          Text(this.config.sendNotice)
            .fontSize(FontSize.footnote)
            .fontColor(this.config.sendOk ? Tok.ok : Tok.error)
            .width('100%')
        }

        Divider().margin({ top: Space.md, bottom: Space.sm })

        StatusRow({
          label: '待投递队列',
          value: `${this.diag.queueDepth} 条`,
          ok: this.diag.queueDepth === 0
        })
        StatusRow({
          label: '最近成功送达',
          value: formatClock(this.diag.lastSuccessAt),
          ok: this.diag.lastSuccessAt > 0
        })

        Row({ space: 10 }) {
          Button('立即投递')
            .fontSize(FontSize.caption).layoutWeight(1)
            .enabled(!this.busy)
            .onClick(() => { this.onDrain(); })
          Button('清空诊断')
            .fontSize(FontSize.caption).layoutWeight(1)
            .backgroundColor(Tok.muted)
            .enabled(!this.busy)
            .onClick(() => { this.onClearDiagnostics(); })
        }.width('100%').margin({ top: 10, bottom: Space.xs })

        if (this.diag.entries.length === 0) {
          Text('暂无诊断记录。').fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%')
        } else {
          ForEach(this.diag.entries, (item: DiagnosticEntry) => {
            Row({ space: Space.xs + 2 }) {
              Text(formatClock(item.createdAt))
                .fontSize(FontSize.micro).fontColor(Tok.muted).width(58)
              Text(item.outcome).fontSize(FontSize.micro).width(96)
              Text(item.bundleName.length > 0 ? item.bundleName : item.eventId)
                .fontSize(FontSize.tiny).fontColor(Tok.muted).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (item.detailCode !== 0) {
                Text(item.detailCode.toString()).fontSize(FontSize.tiny).fontColor(Tok.error)
              }
            }
            .width('100%').padding({ top: 2, bottom: 2 })
            .accessibilityGroup(true)
            .accessibilityText(`${formatClock(item.createdAt)}，${item.outcome}`)
          }, (item: DiagnosticEntry) => `${item.eventId}-${item.createdAt}`)
        }
      }
    }
    .width('100%')
  }
}
