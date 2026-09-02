import { util } from '@kit.ArkTS';

/** Bark 标题上限，UTF-8 字节。 */
export const TITLE_MAX_BYTES: number = 256;
/** Bark 正文上限，UTF-8 字节。留出余量避免加密 + Base64 后超过 APNs 载荷。 */
export const BODY_MAX_BYTES: number = 1500;

/**
 * 按 UTF-8 字节数截断，且不切坏字符。
 *
 * 必须按码点推进而不是按 UTF-16 单元：Emoji 是代理对，从中间切断会产生非法序列，
 * 加密后在 iPhone 上表现为乱码或解码失败。
 */
export function truncateUtf8(text: string, maxBytes: number): string {
  const encoder: util.TextEncoder = new util.TextEncoder();
  if (encoder.encodeInto(text).length <= maxBytes) {
    return text;
  }

  let result: string = '';
  let used: number = 0;
  let i: number = 0;
  while (i < text.length) {
    const code: number = text.charCodeAt(i);
    // 高代理项后面必须跟着低代理项，两个 UTF-16 单元合起来才是一个码点。
    const isHighSurrogate: boolean = code >= 0xd800 && code <= 0xdbff && i + 1 < text.length;
    const step: number = isHighSurrogate ? 2 : 1;
    const piece: string = text.substring(i, i + step);
    const pieceBytes: number = encoder.encodeInto(piece).length;
    if (used + pieceBytes > maxBytes) {
      break;
    }
    result += piece;
    used += pieceBytes;
    i += step;
  }
  return result;
}

/** 返回字符串的 UTF-8 字节长度。 */
export function utf8Length(text: string): number {
  return new util.TextEncoder().encodeInto(text).length;
}
