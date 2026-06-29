# EFC Working Mode 设计方案

## 背景

EFC 设备为 `CID 0x0A78 / PID 0x2131`。固件协议更新后，Vendor Model 私有协议中的 `0x4D / 0x05` 不再表示旧的 Emergency Enabled，而是表示 Working Mode。

新的 Working Mode 协议值如下：

- `0`: Disabled
- `1`: Power Loss Only
- `2`: Fire Alarm Only
- `3`: Power Loss & Fire Alarm

本 App 尚未发布，不需要兼容已发布旧数据。App UI 只支持三种可选模式：`Power Loss Only`、`Fire Alarm Only`、`Power Loss & Fire Alarm`。SDK 数据层仍需识别 `Disabled`，但 App 不展示该选项。

## 已确认的关键决策

- `0x4D / 0x05` Working Mode 替换旧 `Emergency Enabled`，两者不并存。
- App 不再用 `0x4D / 0x04` 综合状态中的旧 `enabled` 字段决定 Disabled UI。
- 设备页如遇 Disabled mode，按 `Power Loss & Fire Alarm` 展示全部状态与控件。
- 入网后默认 Working Mode 为 `Power Loss Only`，不需要从设备读取。
- Working Mode 只影响 UI 展示，不影响 Save 时其他配置任务的生成和下发。
- 隐藏的 Power Loss 或 Fire Alarm 配置仍需保留，用户切换 Working Mode 后可以继续使用历史配置。

## 数据模型

App 侧新增 `EmergencyFireWorkingMode`，作为 EFC desired configuration 的一部分，落在 `EmergencyFireControllerConfiguration.workingMode`。

建议枚举值：

- `disabled = 0`
- `powerLossOnly = 1`
- `fireAlarmOnly = 2`
- `powerLossAndFireAlarm = 3`

`EmergencyFireControllerConfiguration.defaultValue` 使用 `.powerLossOnly`。

Working Mode 放进 `EmergencyFireControllerConfiguration` 后，会自动跟随现有链路：

- 本地 SQLite `configurationData`
- `DeviceEmerFireData.toConfig()`
- `LinkedEmerFireConfig`
- `LinkedEmerFireEditState`
- 云导出 `emergencyFireControllers[].configuration`
- 云导入和分享导入

不新增独立数据库列，不新增第二套 UI 状态字段。

## SDK 协议设计

SDK 侧将 `0x4D / 0x05` 从 `emergencyEnabled(Bool)` 替换为 Working Mode。

SET 编码：

- `Power Loss Only`: `4D 05 01`
- `Fire Alarm Only`: `4D 05 02`
- `Power Loss & Fire Alarm`: `4D 05 03`
- `Disabled`: `4D 05 00`

GET 编码：

- `4D 05`

SET response：

- `ret = 0`: Success
- `ret = 2`: Wrong length
- `ret = 4`: Wrong params
- 其他值按 Unknown error 处理

GET response：

- `ret`
- `mode`

SDK 需要新增或替换为类似以下语义的 API：

- `SunricherVendorSet(function: .emergencyWorkingMode(mode))`
- `SunricherVendorGet(function: .emergencyWorkingMode)`
- `FunctionParameters.emergencyWorkingMode(mode)`
- `FunctionParameters.emergencyWorkingModeAck(...)` 或统一的 status 类型

旧 `emergencyEnabled` 不保留 App 侧调用。若 SDK 为了兼容已有调用保留旧 case，也不能再让 App 使用旧 case。

## 同步任务设计

`DeviceEmerFireData.makeControllerSyncTasks(...)` 新增 Working Mode self task。

任务生成规则：

- 首次同步或修复同步：必须包含 Working Mode task，确保设备拿到默认 `.powerLossOnly`。
- Edit Save：只有 `oldConfiguration.workingMode != newConfiguration.workingMode` 时包含 Working Mode task。
- Working Mode task 属于 controller self sync。
- 同步失败时保留 `controllerSelfSyncPending = true`，并让 `isSynced = false`。
- Working Mode 不参与 associated-group subscription / cleanup。
- Working Mode 不影响 action config、resend、restore delay 等隐藏配置项的任务生成。
- 删除 EFC 时不额外下发 Disabled，继续沿用当前 delete cleanup/reset 流程。

`SyncDevicesViewController.isEmergencyFireControllerSelfTaskKind(...)` 需要把 Working Mode task 纳入 self task kind。

## Edit 与创建虚拟设备页

`LinkedEmerFireEditVC` 同时用于创建虚拟设备和 Edit。需要在 `Associate With Group(s)` 下新增独立展示区域：

- Title: `Emergency Mode`
- Detail: 当前模式

点击后展示选项弹窗：

- `Power Loss Only`
- `Fire Alarm Only`
- `Power Loss & Fire Alarm`

不展示 `Disabled`。

Working Mode 对 `When The Emergency Event Occurs:` 下的控件展示规则：

- `Power Loss Only`: 隐藏 `Fire Alarm Emergency` 相关控件，展示 Power Loss 和公共控件。
- `Fire Alarm Only`: 隐藏 `Power Loss Emergency` 相关控件，展示 Fire Alarm 和公共控件。
- `Power Loss & Fire Alarm`: 展示全部。
- `Disabled`: 按 `Power Loss & Fire Alarm` 处理。

实现时只过滤 `visibleRows`，不清空隐藏配置，不修改隐藏配置的 pending 状态。

当前页面虽只有一个 table section，但 row 本身已经按 card-like cell 展示。实现上优先通过 row/card 分组呈现独立 Section 的视觉效果，避免大改 table structure。

## 设备页 Status & Settings

底部弹窗从 `currentConfig.configuration.workingMode` 读取展示模式。

同一行状态控件展示规则：

- `Power Loss Only`: 只展示 Power Loss 相关状态控件。
- `Fire Alarm Only`: 只展示 Fire Alarm 相关状态控件。
- `Power Loss & Fire Alarm`: 展示全部。
- `Disabled`: 展示全部。

展开列表展示规则：

- 展开后的配置摘要不按 Working Mode 过滤。
- `Power supply fails`、`Fire alarm occurs`、`Emergency Event Ends` 等配置摘要继续展示。
- 这样用户可以看到当前保存的完整配置，并能理解切换 Working Mode 后仍会复用这些配置。

实时状态规则：

- 不再因为旧综合状态 `enabled == false` 显示 Disabled。
- 如果设备实际上报 `fireActive` 或 `emergencyActive`，仍按真实状态显示顶部 warning/status。
- Working Mode 只限制同一行状态控件和 mock 控件集合，不吞掉真实安全状态，也不隐藏展开后的配置摘要。

## Mock 按钮

`EmerFireAlarmMoniView` 需要支持按模式传入不同 action 集合，并让剩余 mock 按钮水平居中。

展示规则：

- Identify 始终保留。
- `Power Loss Only`: 隐藏 Fire Alarm mock，展示 Power Loss mock 和 Restore mock，二者居中。
- `Fire Alarm Only`: 隐藏 Power Loss mock，展示 Fire Alarm mock 和 Restore mock，二者居中。
- `Power Loss & Fire Alarm`: 展示全部 mock，保持当前布局。
- `Disabled`: 展示全部 mock，保持当前布局。

底层 `mockFireAlarmAction()`、`mockPowerLossAction()`、`mockRestoreAction()` 的权限和发送逻辑不需要因为 Working Mode 改变。

## 云同步与分享

Working Mode 放进 `EmergencyFireControllerConfiguration` 后，云端 payload 形态为：

```json
{
  "emergencyFireControllers": [
    {
      "id": "...",
      "spaceId": "...",
      "name": "...",
      "isSynced": false,
      "configuration": {
        "workingMode": 1,
        "powerLossSettings": {},
        "fireAlarmSettings": {},
        "restoreSettings": {}
      }
    }
  ]
}
```

导入时如缺少 `workingMode`，按 `.powerLossOnly` 处理，避免旧测试数据或半成品 payload 解码失败。

`isSynced` 继续沿用现有字段，不新增 sync hash 或独立云字段。

## 本地化

新增或复用本地化 key，至少覆盖 English 和简体中文：

- `Emergency Mode`
- `Power Loss Only`
- `Fire Alarm Only`
- `Power Loss & Fire Alarm`
- Working Mode 同步任务标题，例如 `Emergency Mode`

英文 UI 按产品要求使用：

- `Power Loss Only`
- `Fire Alarm Only`
- `Power Loss & Fire Alarm`

## 验收计划

SDK 验收：

- SET 编码测试：`4D 05 00/01/02/03`
- GET 编码测试：`4D 05`
- SET ACK 解析测试：`ret = 0`
- GET STATUS 解析测试：`ret = 0, mode = 1`
- Wrong params 解析测试：`ret = 4`

App 验收：

- Contract 脚本覆盖 Working Mode 配置字段。
- Contract 脚本确认 App sync 不再使用旧 `emergencyEnabled`。
- Contract 脚本确认 Working Mode task 属于 controller self sync。
- Contract 脚本确认三项 UI 文案存在。
- `git diff --check`
- iPhoneOS build：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

若 SDK focused test 被现有 test target 的 UIKit 或既有测试编译问题阻塞，则记录阻塞原因，并补跑 SDK demo iPhoneOS build。

## 非目标

- 不在 App UI 展示 Disabled 选项。
- 不从设备读取 Working Mode 作为入网默认值。
- 不因为 Working Mode 隐藏 UI 而跳过其他配置任务下发。
- 不新增 Auth 信息。
- 不重构 EFC 无关模块。
