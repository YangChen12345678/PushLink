/** 通知事件类型：新发布 / 被取消。 */
export enum ForwardEventKind {
  POST = 0,
  CANCEL = 1
}

/**
 * 从系统通知回调中提取出的标准事件，是 Extension 与投递链路之间的唯一数据契约。
 *
 * 关于 appIndex：同一个包名可以存在多个分身实例（主应用 appIndex=0，分身依次递增）。
 * 授权白名单与事件去重都必须带上 appIndex，否则主应用与分身会互相串味：
 * 一次授权会放行两个实例，且两者 hashCode 相同时会被误判成同一条通知而互相覆盖。
 */
export interface ForwardEvent {
  /** SHA-256(bundleName|appIndex|hashCode) 前 32 位十六进制；同一条通知的更新复用同一 ID。 */
  eventId: string;
  bundleName: string;
  appIndex: number;
  appName: string;
  title: string;
  body: string;
  /** 毫秒时间戳。系统未提供时回落到收到回调的时刻。 */
  deliveryTime: number;
  kind: ForwardEventKind;
}

/** 授权白名单的唯一键。系统授权列表是 v1 的唯一白名单来源。 */
export function grantKey(bundleName: string, appIndex: number): string {
  return `${bundleName}#${appIndex}`;
}

/** 系统授权白名单里的一个条目。这是 v1 唯一的白名单来源。 */
export interface GrantedBundle {
  bundleName: string;
  appIndex: number;
  appName: string;
  /** grantKey(bundleName, appIndex)，供 Extension 侧 O(1) 判定。 */
  key: string;
}
