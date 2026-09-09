import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Logger } from '../common/Logger';
import { HealthMonitor } from '../service/HealthMonitor';

const SCOPE: string = 'Ability';

export default class EntryAbility extends UIAbility {
    onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
        // 尽早挂上落盘，之后每条日志都会同时进文件。
        Logger.attachFile(this.context.filesDir, 'ui');
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
        this.enterImmersive(windowStage);
    }

    /**
     * 让窗口铺到状态栏与导航条之下。
     *
     * 沉浸材质管不到窗口边界之外：不开这个，内容区就止步于小白条上沿，
     * 那一条永远是系统底色，与上方的材质割裂成两截。
     *
     * 失败只记日志不阻断——铺不开顶多是回到有边界的常规布局，功能不受影响。
     */
    /**
     * 把状态栏与导航条的底色抹成全透明。
     *
     * 只开 setWindowLayoutFullScreen 是不够的：窗口铺过去了，但系统栏自己还带一层底色，
     * 小白条那一条会浮出一块与页面不同的色块。两步都做，材质才是连续的。
     *
     * 内容色留给系统按深浅色自行反色，不写死，免得深色模式下小白条看不见。
     */
    private clearSystemBars(win: window.Window): void {
        win.setWindowSystemBarProperties({
            statusBarColor: '#00000000',
            navigationBarColor: '#00000000'
        }).then(() => {
            Logger.i(SCOPE, 'system bars set transparent');
        }).catch((err: Error) => {
            Logger.w(SCOPE, `setWindowSystemBarProperties failed: ${err.message}`);
        });
    }

    private enterImmersive(windowStage: window.WindowStage): void {
        windowStage.getMainWindow().then((win: window.Window) => {
            win.setWindowLayoutFullScreen(true).then(() => {
                Logger.i(SCOPE, 'window layout fullscreen enabled');
                this.clearSystemBars(win);
            }).catch((err: Error) => {
                Logger.w(SCOPE, `setWindowLayoutFullScreen failed: ${err.message}`);
            });
        }).catch((err: Error) => {
            Logger.w(SCOPE, `getMainWindow failed: ${err.message}`);
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
