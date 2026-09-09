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

/**
 * 拼出带来源应用名的通知标题，如「[微信] 张三：晚上吃什么」。
 *
 * Bark 无法显示来源应用的图标——系统没有获取他人应用图标的公开接口，
 * 且 Bark 的 icon 参数只收公网 URL，把本地图标传上去等于泄露"哪个应用给你发了通知"。
 * 前缀是在不牺牲隐私的前提下解决辨识度的办法。
 *
 * 截断顺序很重要：先给前缀留出预算，再截断标题本体。
 * 反过来先截断再拼接会超出 Bark 的标题上限。
 */
export function composeTitle(appLabel: string, rawTitle: string): string {
  if (appLabel.length === 0) {
    return truncateUtf8(rawTitle, TITLE_MAX_BYTES);
  }
  const prefix: string = `[${appLabel}] `;
  const prefixBytes: number = utf8Length(prefix);
  // 应用名长到吃掉整个预算时放弃前缀——保住标题本体比标出来源重要。
  if (prefixBytes >= TITLE_MAX_BYTES) {
    return truncateUtf8(rawTitle, TITLE_MAX_BYTES);
  }
  return prefix + truncateUtf8(rawTitle, TITLE_MAX_BYTES - prefixBytes);
}

/**
 * 载荷指纹：不含任何内容，只统计那些肉眼看不见、却可能破坏 JSON 或编码的东西。
 *
 * 用来对照「同样都发成功了，为什么有的 iPhone 解得开、有的解不开」——
 * 应用侧的密文长度、IV、HTTP 状态全部正常时，剩下的差异只可能藏在明文的形状里。
 */
export function shapeOf(text: string): string {
  let nl: number = 0;      // 换行
  let ctrl: number = 0;    // 其他控制字符
  let astral: number = 0;  // 代理对（emoji 等增补平面字符）
  let bytes: number = 0;
  for (let i = 0; i < text.length; i++) {
    const c: number = text.charCodeAt(i);
    if (c === 10 || c === 13) {
      nl++;
    } else if (c < 32 || c === 127) {
      ctrl++;
    }
    if (c >= 0xD800 && c <= 0xDBFF) {
      astral++;
    }
    // UTF-8 字节数：代理对的低位不再单独计。
    if (c < 0x80) {
      bytes += 1;
    } else if (c < 0x800) {
      bytes += 2;
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      bytes += 0;
    } else if (c >= 0xD800 && c <= 0xDBFF) {
      bytes += 4;
    } else {
      bytes += 3;
    }
  }
  return `b=${bytes} nl=${nl} ctrl=${ctrl} astral=${astral}`;
}
