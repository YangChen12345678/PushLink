# 签名材料目录

本目录用于存放 HarmonyOS 签名材料，**目录内容默认不进版本库**
（见根 `.gitignore` 的 `/signing/*` 规则，仅放行本 README 与 `signing-configs.template.json5`）。

需要放这里的文件：

| 文件 | 说明 |
| --- | --- |
| `*.p12` | 密钥库 |
| `*.cer` | 调试/发布证书 |
| `*.p7b` | Profile（当前为试用 ACL Profile，正式 ACL 通过后替换） |

配置步骤见 `signing-configs.template.json5` 顶部注释。

## 提交前自检

DevEco 配置完签名后会改写根目录 `build-profile.json5`。提交前务必确认口令没有被带上：

```
git diff build-profile.json5
```

`app.signingConfigs` 应保持为 `[]`。
