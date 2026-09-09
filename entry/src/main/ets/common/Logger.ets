import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';

const DOMAIN: number = 0x9527;
const TAG: string = 'PushLink';

/**
 * 全项目统一日志出口。
 *
 * 硬性约束：通知标题、正文、Bark Device Key、加密密钥一律禁止进入日志。
 * 需要体现"有没有内容"时，用 Redact.len() 只记录长度；需要体现"是哪台设备"时，
 * 用 Redact.addr() 输出掩码。调用方负责保证传入 msg 已经脱敏。
 */
/** 落盘日志的路径。attachFile 之前为空，此时只走 hilog。 */
let sinkPath: string = '';
/** 进程角色（ui / ext / work）。三个进程写同一个文件，靠它分辨来源。 */
let sinkRole: string = '';
/** 单个日志文件的上限。超了就轮转到 .1，最多留两代。 */
const SINK_MAX_BYTES: number = 1024 * 1024;

export class Logger {
  /**
   * 把日志同时写进沙箱文件。
   *
   * hilog 的缓冲区只有几百 K，几分钟就被系统日志冲没；它的落盘文件又是半二进制格式，
   * 解压出来也 grep 不到应用自己的记录（domain A09527 零命中）。
   * 偶发问题必须留证据，所以自己写一份纯文本的。
   *
   * 三个进程（UI、通知扩展、兜底任务）都会调用它，写的是同一个文件、
   * 以追加方式打开——每行都带角色前缀，交错也分得清谁写的。
   */
  static attachFile(filesDir: string, role: string): void {
    sinkPath = `${filesDir}/diag.log`;
    sinkRole = role;
  }

  /** 日志写盘失败绝不能影响主流程，所以整段吞掉异常。 */
  private static append(level: string, scope: string, msg: string): void {
    if (sinkPath.length === 0) {
      return;
    }
    try {
      try {
        const stat: fileIo.Stat = fileIo.statSync(sinkPath);
        if (stat.size > SINK_MAX_BYTES) {
          // 轮转：旧的一代直接被覆盖，只留最近两个文件。
          const backup: string = `${sinkPath}.1`;
          try {
            fileIo.unlinkSync(backup);
          } catch (err) {
            // 备份不存在，正常。
          }
          fileIo.renameSync(sinkPath, backup);
        }
      } catch (err) {
        // 文件还不存在，下面的 CREATE 会建。
      }
      const d: Date = new Date();
      const stamp: string = `${d.getHours()}`.padStart(2, '0') + ':' +
        `${d.getMinutes()}`.padStart(2, '0') + ':' +
        `${d.getSeconds()}`.padStart(2, '0') + '.' +
        `${d.getMilliseconds()}`.padStart(3, '0');
      const line: string = `${stamp} ${sinkRole} ${level} [${scope}] ${msg}
`;
      const file: fileIo.File = fileIo.openSync(sinkPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.APPEND);
      fileIo.writeSync(file.fd, line);
      fileIo.closeSync(file);
    } catch (err) {
      // 写不进去就算了，hilog 那份还在。
    }
  }

  static i(scope: string, msg: string): void {
    hilog.info(DOMAIN, TAG, '[%{public}s] %{public}s', scope, msg);
    Logger.append('I', scope, msg);
  }

  static w(scope: string, msg: string): void {
    hilog.warn(DOMAIN, TAG, '[%{public}s] %{public}s', scope, msg);
    Logger.append('W', scope, msg);
  }

  static e(scope: string, msg: string): void {
    hilog.error(DOMAIN, TAG, '[%{public}s] %{public}s', scope, msg);
    Logger.append('E', scope, msg);
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
