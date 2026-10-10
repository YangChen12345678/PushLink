# PushLink

PushLink 是一款 HarmonyOS 通知转发工具：读取用户在系统设置中授权的应用通知，在本机加密后通过 [Bark](https://github.com/Finb/Bark) 发送到自己的 iPhone。项目使用 ArkTS 和原生 ArkUI 开发，面向个人双机使用场景。

## 功能

- 按 HarmonyOS 系统授权列表筛选通知；未授权的应用和应用分身不会转发。
- 使用 AES-256-GCM 在发送前加密通知内容，Bark 服务只接收密文。
- 断网时将待发消息保存在本机加密数据库中，恢复后重试；发送成功即删除待发记录。
- 提供链路状态、配置、诊断和「我」四个页面，可查看订阅状态、执行加密自检和发送测试消息。
- 日志与诊断信息不记录通知标题、正文或密钥。

## 使用前提

- 一台运行兼容 HarmonyOS API 26 的手机，以及一台安装了 Bark 的 iPhone。
- HarmonyOS 手机已配对至少一台蓝牙设备，并保持蓝牙开关开启。订阅后不需要一直连接该设备。
- 一个包含 `ohos.permission.SUBSCRIBE_NOTIFICATION` 受限权限 ACL 的有效签名 Profile。普通签名即使能编译、安装应用，也可能无法使用通知订阅功能。
- 用于编译项目的 DevEco Studio 和 HarmonyOS SDK API 26。

>
> 当前项目主要用于个人设备测试。受限权限的申请与签名背景见 [docs/acl-application.md](docs/acl-application.md) 和 [docs/acl-rejection-2026-09.md](docs/acl-rejection-2026-09.md)；不能假定普通用户下载源码后就能直接启用通知订阅。
>

## 构建与安装

1. 使用支持 API 26 的 DevEco Studio 打开项目根目录，等待依赖同步完成。
2. 在 **File → Project Structure → Signing Configs** 中配置自己的证书与 Profile。签名材料的放置和注意事项见 [signing/README.md](signing/README.md)。
3. 选择 `default` 产品，构建并安装 `entry` 模块到 HarmonyOS 手机。
4. 首次打开应用后，按下方步骤完成配置。


仓库不提供可复用的个人签名材料。`build-profile.json5` 中由 DevEco
写入的签名路径和口令属于本机配置，提交前须执行 `sh scripts/stage-clean-build-profile.sh`，并检查暂存区中的 `app.signingConfigs` 为 `[]`。

## 首次配置

1. 在 iPhone 的 Bark App 中取得 **Device Key**，启用加密并设置一个 **32 个 ASCII 字符**的加密 Key。
2. 打开 PushLink 的「配置」页，填写 Bark 服务地址（默认 `https://api.day.app`）、Device Key，以及与 iPhone 端完全一致的加密 Key，然后点击保存。
3. 回到「状态」页，授予蓝牙权限，从已配对设备中选择一台并登记订阅。蓝牙开关需要保持开启。
4. 从「状态」页打开系统通知授权设置，启用读取通知，并逐个勾选允许转发的应用。授权列表为空时，PushLink 不会转发任何通知。
5. 在「诊断」页运行加密自检；需要验证端到端链路时，在「配置」页发送测试消息，并在 iPhone 上查看 Bark。


Device Key 和加密 Key 保存在 HarmonyOS 手机的本机加密数据库中。请勿把自己的密钥写进源码、提交记录或公开问题报告。

## 项目结构


| 路径                                       | 内容                                                       |
|----------------------------------------------|--------------------------------------------------------------|
| `entry/src/main/ets/pages/`                  | 页面组装与交互                                        |
| `entry/src/main/ets/components/`             | ArkUI 组件                                                 |
| `entry/src/main/ets/viewmodel/`              | 页面状态与业务操作                                  |
| `entry/src/main/ets/service/`                | 通知筛选、订阅、待发队列、网络投递与存储 |
| `entry/src/main/ets/crypto/`                 | Bark 加密与自检                                         |
| `entry/src/main/ets/notificationsubscriber/` | 系统通知订阅扩展                                     |
| `entry/src/main/ets/workscheduler/`          | 待发消息重试任务                                     |
| `entry/src/test/`、`entry/src/ohosTest/`    | 单元测试与设备测试                                  |


## 已知限制

- `SUBSCRIBE_NOTIFICATION` 是受限权限；缺少相应 ACL 时，系统会拒绝订阅，即使应用本身安装成功。
- 关闭蓝牙后，系统可能停止投递通知回调；重新打开蓝牙后请在「状态」页确认链路状态。
- Bark 加密模式下的远程通知撤回不可靠，因此项目默认不向 Bark 发送撤回请求。
- 待发队列用于发送失败后的补投，不保存已经成功投递的通知历史。

开发中的实现约束和排障记录见 [CLAUDE.md](CLAUDE.md)。

 
