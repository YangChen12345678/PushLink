import { Color as Tok, FontSize, Space } from '../theme/Tokens';
import { DiagnosticEntry } from '../service/DiagnosticStore';
import { DiagnosticState, formatClock } from '../viewmodel/DiagnosticState';
import { GroupTitle, SectionCard, StatusRow } from './Common';

/**
 * 队列深度与投递记录。
 *
 * 记录里只有元数据——事件 ID、来源包名、结果、耗时、错误码。
 * 通知的标题与正文从未落盘（投递成功即删），所以这里看不到消息内容，
 * 这是隐私设计的直接结果，不是尚未实现。
 */
@Component
export struct DiagnosticSection {
  @ObjectLink diag: DiagnosticState;
  @Prop busy: boolean = false;
  onDrain: () => void = () => {};
  onClearDiagnostics: () => void = () => {};

  build() {
    Column() {
      SectionCard({ alignStart: true }) {
        StatusRow({
          label: '待投递队列',
          value: `${this.diag.queueDepth} 条`,
          ok: this.diag.queueDepth === 0
        })
        Divider()
        StatusRow({
          label: '最近成功送达',
          value: formatClock(this.diag.lastSuccessAt),
          ok: this.diag.lastSuccessAt > 0
        })
      }

      Row({ space: 10 }) {
        Button('立即投递')
          .fontSize(FontSize.caption).layoutWeight(1)
          .enabled(!this.busy)
          .onClick(() => { this.onDrain(); })
        Button('清空记录')
          .fontSize(FontSize.caption).layoutWeight(1)
          .backgroundColor(Tok.muted)
          .enabled(!this.busy)
          .onClick(() => { this.onClearDiagnostics(); })
      }.width('100%').margin({ top: Space.md })

      GroupTitle({ text: '最近记录' })
      SectionCard({ alignStart: true }) {
        if (this.diag.entries.length === 0) {
          Text('暂无记录。').fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%')
        } else {
          ForEach(this.diag.entries, (item: DiagnosticEntry) => {
            Row({ space: Space.xs + 2 }) {
              Text(formatClock(item.createdAt))
                .fontSize(FontSize.micro).fontColor(Tok.muted).width(52)
              Text(item.outcome).fontSize(FontSize.micro).width(92)
              Text(item.bundleName.length > 0 ? item.bundleName : item.eventId)
                .fontSize(FontSize.tiny).fontColor(Tok.muted).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (item.detailCode !== 0) {
                Text(item.detailCode.toString()).fontSize(FontSize.tiny).fontColor(Tok.error)
              }
            }
            .width('100%').padding({ top: 3, bottom: 3 })
            .accessibilityGroup(true)
            .accessibilityText(`${formatClock(item.createdAt)}，${item.outcome}`)
          }, (item: DiagnosticEntry) => `${item.eventId}-${item.createdAt}`)
        }
      }

      Text('记录只含来源与结果，不含通知内容——正文从未在本机落盘。')
        .fontSize(FontSize.footnote).fontColor(Tok.muted).width('100%')
        .margin({ top: Space.sm, left: Space.xs })

      Blank().height(Space.xxl)
    }
    .width('100%')
  }
}
