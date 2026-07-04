# Lab Light / Group Control TTL 规划方案

## 目标

在 Lab 功能中增加一个可配置项，用于修改手机下发 Light / Group 灯控命令时使用的 TTL。

该功能只影响 App 手机端主动发送的灯控命令，不修改设备自身 Default TTL，不发送 `ConfigDefaultTtlSet`，不修改 SDK 全局 `networkParameters.defaultTtl`。

## 覆盖范围

纳入范围：

- Light 页面
  - 单灯 on/off
  - 单灯 brightness / lightness
  - 单灯 CCT
  - 单灯 Identify
  - Lights 列表中的单灯 on/off
  - Lights 页面中的 All lights on/off
  - Lights 页面中的 All lights brightness
- Group 页面
  - Group 列表 on/off
  - Group 详情 on/off
  - Group 详情 brightness / lightness
  - Group 详情 CCT
  - Group 详情里控制 group member 单灯 on/off

不纳入范围：

- Energy 页面中的灯控
- Schedule / Timed 相关灯控
- Device Parameter / Rated Power Calibration 相关灯控
- Switch / Fire Alarm / Gateway / EFC / Sync 等其他功能页面
- Light Sensor Calibration、Path Sequence Test 等借用 group address 的调试或配置流程
- 设备自身 Default TTL 读写或配置

## Lab 设置设计

新增 Lab 设置项：

- `Override Light/Group Control TTL`
  - 类型：开关
  - 默认：关闭
  - 关闭时：完全沿用当前行为，发送层 `defaultTTL` 传 `nil`
  - 打开时：Light / Group 灯控命令显式使用用户设置的 TTL
- `Light/Group Control TTL`
  - 类型：数值输入或 stepper
  - 范围：`0...127`
  - 默认显示值：`5`

Lab 中需要明确说明影响范围：

英文建议：

`Affects Light and Group control commands only. Other features are not affected.`

简体中文建议：

`仅影响 Light 和 Group 灯控命令，其他功能不受影响。`

## 数据与配置

在 `LabSettings` 中新增 UserDefaults 配置：

- TTL override 开关，例如 `lab_override_light_group_control_ttl`
- TTL 数值，例如 `lab_light_group_control_ttl`

对外暴露一个统一读取入口：

- `lightGroupControlTTLOverride: UInt8?`
  - 开关关闭时返回 `nil`
  - 开关打开时返回当前 TTL 值

这样调用点只需要关心是否有 override，不需要重复读取开关和值。

## 发送链路设计

推荐新增一个轻量发送 helper，用于 Light / Group 控制命令：

- Node on/off
- Node lightness
- Node CCT
- Node identify
- Group on/off
- Group lightness
- Group CCT
- All lights on/off
- All lights lightness

helper 内部逻辑：

1. 从 `LabSettings.lightGroupControlTTLOverride` 获取 TTL
2. 按原有 ACK / unack 逻辑构造同样的 Mesh message
3. 调用现有 `MeshAPI.sendMessage(..., defaultTTL: ttlOverride)`

不建议直接修改现有 `MeshAPI.setNodeOnOffState` 等通用接口的默认行为，因为这些接口被其他页面复用。直接在通用接口内读取 Lab 设置，会让 Energy、Schedule、Device Parameter 等页面也被影响，不符合本次范围。

## Identify 处理

单灯 Identify 纳入 TTL override：

- 普通 Identify：`AttentionSet` / `AttentionSetUnacknowledged`
- 支持 vendor identify 的灯：`SunricherVendorSet(function: .identify(...))`

处理原则：

- 只覆盖 Light 页面触发的单灯 Identify
- 不覆盖 Add Device、Firmware、Energy、Parameter、Gateway 等其他页面的 Identify

## ACK 详情模式

现有 `Display light ACK details` 打开时，灯控会走 `LightAckProgressTracker`。

需要同步调整：

- `LightAckProgressTracker.send(...)` 增加可选 `defaultTTL`
- Light / Group 灯控的 ACK 详情路径传入同一个 Lab TTL override
- Lab 关闭 TTL override 时仍传 `nil`

这样 ACK 详情模式和普通模式使用同一套 TTL 规则。

## 国际化

新增所有用户可见文案时，需要同步 English 和简体中文：

- `Override Light/Group Control TTL`
- `Light/Group Control TTL`
- `Affects Light and Group control commands only. Other features are not affected.`

如果已有 Lab 文案 key 风格可复用，应按现有命名风格新增 key。

## 验证计划

代码验证：

- `git diff --check`
- iPhoneOS build：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

功能验证：

- Lab TTL override 关闭：Light / Group 控制行为保持现状
- Lab TTL override 开启，TTL = 0：验证直连 Proxy 场景下单灯、All lights、Group 控制
- Lab TTL override 开启，TTL = 2 或 5：验证需要 relay 的场景
- 单灯 Identify 验证普通 Identify 和 vendor Identify
- Energy、Schedule、Device Parameter、Switch、Fire Alarm 等非覆盖范围页面确认不走 Lab TTL override

## 风险与边界

- TTL = 0 只适合直连 Proxy 或单跳验证；需要 relay 的设备可能收不到命令。
- All lights 和 Group address 是多播/广播类控制，TTL 设置过低时影响会更明显。
- 不修改 SDK 全局默认 TTL，可以避免影响非灯控流程，但需要确保所有纳入范围的调用点都改走 helper。
