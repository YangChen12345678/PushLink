# PushLink

把 HarmonyOS 手机的通知加密后转发到 iPhone 的 Bark。单机自用工具，
签名有效期至 **2027-09-01**（到期在 DevEco 重新签名覆盖安装即可续）。

本文只记录**改代码前必须知道、且读代码看不出来**的事。项目背景见 `docs/`。

---

## 构建与调试

机器上并存两套 DevEco，**PATH 不可信**，一律用绝对路径：

```bash
export npm_config_cache="<某个可写目录>"          # 见下方坑 5
export DEVECO_SDK_HOME="E:/Program Files/Huawei/DevEco Studio/sdk"
"E:/Program Files/Huawei/DevEco Studio/tools/node/node.exe" \
  "E:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" \
  assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

- **API 26 那套**：`E:\Program Files\Huawei\DevEco Studio`（SDK 26.0.0.105）
- **别用**：`E:\DevEco Studio`（只到 API 21）、PATH 里的 `hdc`（API 20，会抢端口）
- hdc：`E:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`
- **签名包只能在 DevEco 里出**：口令由 DevEco 加密存储，命令行 `SignHap` 必然失败，
  这是已确认无解的（手动签名模式下口令仍是密文）。命令行编译只用于验证 `CompileArkTS`。

抓日志**必须加 `-t app`**，默认的 core 类型抓不到应用日志：

```bash
hdc shell hilog -t app | grep PushLink      # 实时（缓冲区仅 512K，冲得很快，别指望事后补抓）
hdc shell hilog -r                          # 清空
```

`hdc install` 的路径参数按**相对 cwd** 解析，传绝对路径会被拼成 `E:\PushLink\E:/...` 而失败。

---

## 五个会造成真实故障的坑

### 1. ArkUI 的参数默认不是响应式的

两种形态，本项目**各踩过一次**，症状相同：**页面上一半数据是新的、一半停在初始值**。

```typescript
// 错误 ①：@Builder 的简单类型参数是按值传递
@Builder row(label: string, ok: boolean) { ... }
// 错误 ②：@Component 的无装饰器成员只在首次创建时赋值
@Component struct Row { label: string = ''; ok: boolean = false; }

// 正确：@Builder 用单个对象参数；@Component 用 @Prop
@Component struct Row { @Prop label: string = ''; @Prop ok: boolean = false; }
```

**诊断特征**：界面出现自相矛盾的画面（"订阅已登记：否"却同时显示订阅设备地址）——
`build()` 里的 `if`/`ForEach` 会正常重新求值，只有子结构内部的值凝固了。**日志才是真相。**

配套规则：页面用 `@State` 持有 `@Observed` 对象时，**只观察引用变化，读不到对象内部属性**。
所以 `busy` 这类要驱动页面自身渲染的标志必须放页面的 `@State` 上，不能塞进状态类。
子组件观察对象属性用 `@ObjectLink`。

### 2. ValuesBucket 不接受枚举成员

只收 `number | string | boolean | Uint8Array | null`。传枚举（哪怕调 `.valueOf()`）
会以 **401** 拒掉整条 insert。字符串枚举改用 `class` + `static readonly string`。

**401 会报在最先失败的调用上，未必是真正有问题的地方。** 排查时日志要同时记 `e.message`，
只记 `e.code` 定位不到（本项目正是靠 `msg=Parameter error.Illegal context.` 一步找到真凶）。

### 3. `DELETE ... WHERE id IN (SELECT ... LIMIT ?)` 会清空整表

参数没绑上时 SQLite 把 `LIMIT` 当无限制，子查询返回全表。
**改用谓词接口**：查出第 N 条的时间戳作边界，再 `lessThan('created_at', cutoff)`。

### 4. 懒加载单例会缓存住失败的 Promise

```typescript
if (Database.opening === undefined) { Database.opening = Database.open(ctx); }
return Database.opening;   // open 失败后，这里永远返回同一个已拒绝的 Promise
```

**必须在 catch 里清掉缓存再抛**，否则一次瞬时故障变成永久故障（进程存活期间再也打不开库）。
这个模式与 RDB 无关，任何"懒加载 + Promise 缓存"都适用。

### 5. npm 缓存目录不可写

首次构建要装 pnpm，默认缓存 `D:\NodeJs\node_cache` 写入被拒（EPERM）。
构建前 `export npm_config_cache=<可写目录>` 即可，无需提权。

---

## 不可违反的约束

- **日志绝不出现通知标题、正文、Device Key、加密密钥。** 一律走 `Logger` + `Redact`，
  只输出长度（`Redact.len`）或掩码（`Redact.addr`）。有测试覆盖。
- **白名单默认拒绝。** 未在系统授权列表中的来源、查询失败、名单为空 —— 一律丢弃。
  系统授权列表是唯一白名单，应用内不得另设开关。
  （实测系统层也会过滤，应用侧是第二道保险，但不能因此删掉。）
- **投递成功即删。** 队列只存未送出的，不留已发送通知的历史。
- **加密改动必须跑 NIST 向量。** 往返测试证明不了互操作性——tag 拼错位置时
  加解密两边会错得一模一样。`CryptoSelfTest.checkStandardVectors()` 是唯一的真实校验。

---

## 运行时事实（实测，非推测）

- **蓝牙开关必须打开，但不需要连接任何设备。** 关闭蓝牙后系统停止投递回调，
  而 `getSubscribeInfo()` 仍返回已订阅——所以健康状态必须是「订阅 ∧ 授权 ∧ 蓝牙」三者与。
- **扩展进程会被系统反复回收**（观察到 5 个不同进程号），任何内存状态都不可靠，必须落盘。
- **重启后订阅自动恢复**，不需要开机自启逻辑。
- `hashCode` 形如 `__100_20020072_com.tencent.wechat__1288282963`，**发布与取消时一致**，
  可安全作为 eventId 基础。`eventId = SHA-256(hashCode)` 前 32 位——
  **不能掺 bundleName**，因为取消回调只给 hashCodes，掺了就算不出该撤回哪条。
- 应用分身的 `appIndex` 非 0（实测微信分身为 1），白名单键必须是 `bundleName#appIndex`。

---

## 目录约定（阶段 E 建立）

```
theme/       设计令牌，颜色一律 $r('app.color.*')，不写字面量
viewmodel/   @Observed 状态类，业务逻辑
components/  UI 组件，参数一律 @Prop
service/     数据与网络，UI 无关
pages/       只做组装与跨状态编排
```

新增颜色要**同时**加进 `resources/base/element/color.json` 和 `resources/dark/`，
否则深色模式下会与系统组件割裂。

---

## 提交前

`build-profile.json5` 含签名口令，提交前必须：

```bash
sh scripts/stage-clean-build-profile.sh
```

它把 `signingConfigs` 清空的版本放进暂存区，工作区不动（DevEco 编译不受影响）。
忘了也没关系，pre-commit hook 会拦。
