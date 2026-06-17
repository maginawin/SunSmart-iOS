# EFC Feature Buttons 设计

## 背景

`EmerFireAlarmMoniView` 当前只支持最多三个横排 action 按钮，默认使用白色圆形背景和浅蓝边框。Figma 中的 EFC feature buttons 组要求改为上方 Identify、下方三个 mock 按钮的组合，并统一使用 Group 页面 AUTO 按钮点击后的旋转 loading 效果。

本设计仅覆盖 `EmerFireAlarmMoniView` 和 `EmerFireAlarmMonitorVC` 的 UI 与手动控制动作，不修改 EFC 编辑页、同步流程、SDK 协议解析或 desired configuration。

## UI 设计

EFC feature buttons 组采用竖向布局：

- Identify 独立一行，图片使用 `efc_identify`。
- Identify 背景透明、无边框。
- Identify 顶部距离 groups 区域底部 28px。
- Identify 底部距离 mock 按钮组顶部 28px。
- mock 按钮组一行展示三个 40x40 按钮：
  - Mock fire alarm 使用 `mock_fire_alarm`。
  - Mock power loss 使用 `mock_power_loss`。
  - Mock restore 使用 `mock_restore`。
- 三个 mock 按钮横向间隔 24px。
- mock 按钮背景透明、无边框。
- 四个按钮点击后统一使用 `group_auto_progress` / `group_auto_progress_big` 加 `Bar_Color` tint 和旋转动画。

`EmerFireAlarmMoniView` 继续只负责布局、图片展示、loading 和点击回调，不承载 Mesh 命令逻辑。Controller 仍通过 action item 注入按钮行为。

## 动作设计

`EmerFireAlarmMonitorVC` 注入四个动作：

- Identify：保持现有逻辑，向 EFC 绑定节点的 Health Model 发送 `AttentionSet(attentionTimer: 6)`。
- Mock fire alarm：读取当前配置的 `fireAlarmSettings.triggerBrightness`，转换为 Mesh lightness，向 EFC internal publish group 发送 `LightLightnessSetUnacknowledged`。
- Mock power loss：读取当前配置的 `powerLossSettings.triggerBrightness`，转换为 Mesh lightness，向 EFC internal publish group 发送 `LightLightnessSetUnacknowledged`。
- Mock restore：读取 `restoreSettings.actionType`：
  - `restoreAuto`：向 EFC internal publish group 发送和 Group 页面 AUTO 同语义的 `LightLCLightOnOffSetUnacknowledged(true)`。
  - `setBrightness`：读取 `restoreSettings.brightness`，转换为 Mesh lightness，发送 `LightLightnessSetUnacknowledged`。
  - `none`：不发送 Mesh 命令，不提示失败，保留一次点击 loading 反馈。

所有 mock 动作目标地址只使用 EFC 的 `publishGroupAddress`，不直接遍历普通关联 Group。这样能模拟 EFC 触发后对内部 publish group 的控制效果，同时避免改变普通 Group 页面状态或本地缓存。

## 状态与错误处理

- 权限不足时沿用现有 `"no_permission"` HUD，并且不进入 loading。
- 缺少 EFC publish group 时沿用 `publishGroupAddressForAction()` 的错误提示，并且不进入 loading。
- Identify 缺少绑定节点 Health Model 时沿用现有 failed HUD，并且不进入 loading。
- Mock restore 为 `none` 时视为有效点击：不发命令、不弹提示、进入 1 秒 loading。
- 每个按钮 loading 期间忽略该按钮重复点击，不锁定其它按钮。
- mock 操作不写入配置、不刷新同步状态、不更新本地 group/node 亮度缓存。

## 实现边界

预期改动范围：

- `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmMoniView.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`
- 必要时更新 `EmergencyFireControllerIconName.swift` 中的 action 图标常量。

不纳入本次范围：

- EFC 编辑页字段或保存逻辑。
- EFC sync planner。
- SDK vendor `0x4D/07` action config 编解码。
- 关联 Group 的本地开关/亮度缓存刷新。
- 其它 brand target 的资源复制，除非编译或 target 配置显示必须同步。

## 验证计划

- 检查 `efc_identify`、`mock_fire_alarm`、`mock_power_loss`、`mock_restore` 资源在 `SunSmart/Assets.xcassets/FireAlarm1.5` 中可用，并确认 target 影响范围。
- 检查按钮布局符合 Figma：28px、28px、24px，按钮透明背景、无边框。
- 检查命令链路：
  - fire alarm / power loss / restore set brightness 都向 EFC publish group 发亮度命令。
  - restore auto 向 EFC publish group 发 LC ON 命令。
  - restore none 不发 Mesh 命令。
- 运行 `git diff --check`。
- 运行 iPhoneOS build：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 自检

- 无未决事项。
- UI、动作、错误处理和验证范围一致。
- 范围聚焦在 EFC 监控页 feature buttons，不包含无关重构。
- `Mock restore none` 的行为已明确为不发命令但保留点击反馈。
