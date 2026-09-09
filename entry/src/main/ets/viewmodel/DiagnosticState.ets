import { common } from '@kit.AbilityKit';
import { OutboxStore } from '../service/OutboxStore';
import { DiagnosticEntry, DiagnosticStore } from '../service/DiagnosticStore';
import { ForwardPipeline } from '../service/ForwardPipeline';

/** 待投递队列与脱敏诊断记录。 */
@Observed
export class DiagnosticState {
  queueDepth: number = 0;
  lastSuccessAt: number = 0;
  entries: DiagnosticEntry[] = [];

  async refresh(ctx: common.Context): Promise<void> {
    this.queueDepth = await OutboxStore.depth(ctx);
    this.lastSuccessAt = await DiagnosticStore.lastSuccessAt(ctx);
    this.entries = await DiagnosticStore.recent(ctx, 12);
  }

  async clear(ctx: common.Context): Promise<void> {
    await DiagnosticStore.clear(ctx);
    await this.refresh(ctx);
  }

  async drainNow(ctx: common.Context): Promise<void> {
    await ForwardPipeline.drain(ctx, undefined, 'ui-manual');
    await this.refresh(ctx);
  }
}

/** 时间戳转 HH:MM:SS，0 表示还没有过。 */
export function formatClock(timestamp: number): string {
  if (timestamp === 0) {
    return '尚无';
  }
  const date: Date = new Date(timestamp);
  const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
  return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}
