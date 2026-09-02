# ACL 权限申请驳回记录（2026-09）

保留原文，供后续申诉与续签时查阅。

## 驳回意见原文

> 尊敬的开发者：
>
> 您好，您的权限申请未通过。
>
> 未通过权限：
>
> 权限名称: ohos.permission.SUBSCRIBE_NOTIFICATION
>
> 审核意见: 开发者您好：受限权限仅少量符合特殊场景的应用可在通过审批后使用，
> ohos.permission.SUBSCRIBE_NOTIFICATION 权限为允许应用获取用户通知中心的通知，
> 当前只给穿戴类官方 app 开放，用于同步通知到手表/手环等穿戴类设备。
> 您的场景不符，不可授予此权限，感谢您的理解与支持！

## 与驳回理由矛盾的事实

驳回理由称该权限"当前只给穿戴类官方 app 开放"，但存在反例：

**HarkForward**（`com.harmonysendios.bark`）

- 开发者：王俊熙，**个人开发者**
- 分类：工具（非穿戴类）
- 简介：实现异地向苹果设备转发通知
- 上架：2026-08-27，当前版本 1.3.1（2026-08-31）
- 分发：华为应用市场

设备端 `bm dump -n com.harmonysendios.bark` 核验结果：

```
appDistributionType : app_gallery
installSource       : com.huawei.hmsapp.appgallery
appProvisionType    : release
debug               : false
releaseType         : Release

权限：
  ohos.permission.ACCESS_BLUETOOTH
  ohos.permission.GET_BUNDLE_INFO
  ohos.permission.GET_NETWORK_INFO
  ohos.permission.INTERNET
  ohos.permission.RUNNING_LOCK
  ohos.permission.SUBSCRIBE_NOTIFICATION
```

其六项权限与本项目申请的完全一致，技术路线相同
（同为 `NotificationSubscriberExtensionAbility` + 蓝牙订阅 + Bark 协议），
模块名与扩展类名亦相同（均为官方文档默认命名）。

**结论：驳回原因不是主体资质门槛，也不是用途表述问题，而是审核标准不一致。**

## 当前状态

- 使用 DevEco 自动生成的 debug 类型签名，有效期 **2026-09-01 → 2027-09-01**
- 通过 UDID 绑定单台设备（PLR-AL50），无法分发
- 功能完整可用，不受权限驳回影响

## 后续

见 [acl-appeal.md](acl-appeal.md)：以上述先例为依据的复核请求。
