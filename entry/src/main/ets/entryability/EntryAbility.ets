import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Logger } from '../common/Logger';
import { HealthMonitor } from '../service/HealthMonitor';

const SCOPE: string = 'Ability';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      const e: Error = err as Error;
      Logger.e(SCOPE, `setColorMode failed: ${e.message}`);
    }
    // 监听挂在 Ability 上而不是页面上：页面销毁后监听就没了，
    // 而用户往往是退出界面之后才去关蓝牙的。
    HealthMonitor.start();
    Logger.i(SCOPE, 'onCreate');
  }

  onDestroy(): void {
    HealthMonitor.stop();
    Logger.i(SCOPE, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Logger.e(SCOPE, `loadContent failed code=${err.code}`);
        return;
      }
      Logger.i(SCOPE, 'content loaded');
    });
  }

  onWindowStageDestroy(): void {
    Logger.i(SCOPE, 'onWindowStageDestroy');
  }

  onForeground(): void {
    Logger.i(SCOPE, 'onForeground');
  }

  onBackground(): void {
    Logger.i(SCOPE, 'onBackground');
  }
}
