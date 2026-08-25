# Calibration inputRow 自适应布局实施记录

## 实施结果

已按确认方案优化 `LightSensorTargetSensorValueView` 的 `inputRow`：

- 移除 `Target value` 输入框的 152pt 固定宽度。
- 移除 `Use sensor reading` 按钮的 114pt 固定宽度。
- 使用 `UIButton.Configuration` 为按钮提供左右各 12pt 的自适应内容内边距。
- 按钮和 `LX` 设置 required 水平 hugging 与 compression resistance，优先保证文字完整。
- 输入框设置 defaultLow 水平 hugging 与 compression resistance，取得全部剩余宽度并在极窄空间下优先收缩。
- 保留现有 8pt 间距、32pt 行高、按钮 1pt 边框、15pt 圆角和原有点击逻辑。
- 未修改文案、本地化文件、传感器读取、输入校验或 Calibration 状态流程。

## 实现调整

初版使用旧式 `UIButton.contentEdgeInsets` 提供按钮内边距。SunSmart 构建虽然成功，但 Xcode 对 iOS 15+ 报告该属性弃用警告。

随后将按钮迁移为 `UIButton.Configuration.plain()`：

- 使用 configuration 的 directional content insets。
- 使用 configuration 的 title attributes transformer 保持原有 12pt light 字体。
- 使用 base foreground color 保持原有按钮文字颜色。
- 保留原有 target/action、边框和圆角。

修订后重新构建通过，没有保留本次引入的弃用警告。

## 回归测试

扩展 `SensorCalibrationWorkflowContractTests`，约束以下规则：

- 输入框和按钮不得恢复原固定宽度。
- 按钮必须使用 configuration content insets，不得恢复旧式 `contentEdgeInsets`。
- 按钮和 `LX` 必须保持 required 水平 hugging 与 compression resistance。
- 输入框必须保持 defaultLow 水平 hugging 与 compression resistance。

测试在布局实现前按预期失败，实施后通过；切换现代按钮 configuration 时再次先建立失败检查，再修复至通过。

## 自动化验证

- `scripts/check_sensor_calibration_workflow.sh`：通过。
- `git diff --check`：通过。
- SunSmart，Debug，iphoneos，关闭签名：构建通过。
- Archipelago，Debug，iphoneos，关闭签名：构建通过。
- SLG Sync Plus，Debug，iphoneos，关闭签名：构建通过。
- SylSmart，Debug，iphoneos，关闭签名：构建通过。

四品牌构建期间 workspace 当前解析到本地 `NordicSigMeshSDK`；本次没有修改 SDK 或依赖配置。

## 实际布局验收状态

执行 `xcrun xctrace list devices` 时返回没有可用设备，因此本轮无法在实际 iPhone 上进入 Calibration 页面完成 English 与简体中文布局测试。

以下项目仍为未完成验收，不能由源码契约或四品牌构建替代：

- `Use sensor reading` 与 `使用传感器读数` 是否完整单行显示。
- `LX` 是否完整且未被拉伸或压缩。
- 320pt、375pt 及更宽窗口下输入框是否正确取得剩余宽度。
- 三项是否无重叠且保持两个 8pt 间距。
- 输入、按钮点击、传感器读数回填和键盘交互是否保持正常。

连接真机后需要完成上述验收，才能将该 UI 修改视为完整验证。

## 工作区保护

本次保留了已有未提交改动，包括：

- `AGENTS.md` 的 UI 实际布局测试要求。
- Dim level 加号按钮约束修复及其回归检查。
- 用户已调整的按钮 1pt 边框、15pt 圆角与 32pt 高度。
- 先前生成的 Dim level 修复记录和本次需求计划。
