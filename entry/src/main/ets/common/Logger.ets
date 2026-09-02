import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x9527;
const TAG: string = 'PushLink';

/**
 * 全项目统一日志出口。
 *
 * 硬性约束：通知标题、正文、Bark Device Key、加密密钥一律禁止进入日志。
 * 需要体现"有没有内容"时，用 Redact.len() 只记录长度；需要体现"是哪台设备"时，
 * 用 Redact.addr() 输出掩码。调用方负责保证传入 msg 已经脱敏。
 */
export class Logger {
  static i(scope: string, msg: string): void {
    hilog.info(DOMAIN, TAG, '[%{public}s] %{public}s', scope, msg);
  }

  static w(scope: string, msg: string): void {
    hilog.warn(DOMAIN, TAG, '[%{public}s] %{public}s', scope, msg);
  }

  static e(scope: string, msg: string): void {
    hilog.error(DOMAIN, TAG, '[%{public}s] %{public}s', scope, msg);
  }
}

/** 脱敏辅助：把敏感值折叠成不可还原的摘要形式。 */
export class Redact {
  /** 只暴露长度，不暴露内容。用于标题、正文、密钥。 */
  static len(value: string | undefined): string {
    return value === undefined ? 'null' : `len=${value.length}`;
  }

  /** 蓝牙地址掩码：仅保留首尾各 2 字符，足以区分设备又不泄露完整地址。 */
  static addr(value: string | undefined): string {
    if (value === undefined || value.length === 0) {
      return 'null';
    }
    if (value.length <= 4) {
      return '****';
    }
    return `${value.substring(0, 2)}****${value.substring(value.length - 2)}`;
  }
}
