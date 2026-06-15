# Power Switch 删除确认提示统一设计

## 背景

在 `Site - Space - Main - Switches` 中，用户点击底部删除按钮进入编辑态后，再点击 switch 控件右上角删除按钮时，Battery Power Switch 与 AC Power Switch 需要展示各自的删除确认提示。用户确认该规则需要统一到所有相关 Battery/AC Power Switch 删除入口，而不是只改 Main - Switches 列表。

当前代码中，部分 8-key power switch 删除入口复用了 Kinetic Switch 的 `switchs_delete_message`，部分未关联虚拟 Battery Power Switch 存在直接删除路径。该行为会导致 Battery/AC 类型提示不准确，且真实设备与虚拟设备的确认体验不一致。

## 目标

- Kinetic Switch 保持现状，不改现有删除提示与删除行为。
- Battery Power Switch 真实设备和虚拟设备删除前都提示：`Are you sure to delete the battery power switch?`
- AC Power Switch 真实设备和虚拟设备删除前都提示：`Are you sure to delete the AC power switch?`
- Battery/AC 删除确认弹窗使用 `CANCEL` 和 `CONFIRM` buttons。
- 不改变删除后的 sync、cache delete、通知刷新、权限判断和页面关闭流程。

## 范围

本次统一覆盖以下 Battery/AC Power Switch 删除入口：

- `Site - Space - Main - Switches` 底部删除进入编辑态后，点击 cell 右上角删除按钮。
- Battery/AC Power Switch 详情页右上角删除按钮。
- Battery/AC Power Switch Edit / PreAdd 页面删除按钮。
- Group Power Switch 页面中的删除按钮。

不覆盖：

- Kinetic Switch 删除提示调整。
- 删除命令、Mesh sync、云端保存、导入导出逻辑调整。
- 与删除确认无关的 UI、布局、资源或 target 配置调整。

## 设计

新增 Battery/AC 专用本地化 key，并在 8-key power switch 相关代码中通过 `PJEightKeyPowerSwitchKind` 选择删除确认文案。判断依据使用现有 `PJEightKeySwitchData.powerSwitchKind`，不通过真实/虚拟状态分叉。

新增 key：

- `power_switch_battery_delete_message` = `Are you sure to delete the battery power switch?`
- `power_switch_ac_delete_message` = `Are you sure to delete the AC power switch?`

为避免各入口重复写判断，在 `PJEightKeyPowerSwitchKind` 增加 `deleteConfirmationMessage` 计算属性。所有 Battery/AC 删除确认弹窗从该属性获取 message。Kinetic Switch 仍继续使用现有 `switchs_delete_message` 或 `switch_delete_message`。

## 入口行为

`DeviceSwitchesViewController`：

- 编辑态 cell 右上角删除时，如果能识别为 `PJEightKeySwitchData`，先按 `powerSwitchKind` 弹 Battery/AC 专用确认。
- 用户点击 `CONFIRM` 后继续执行现有删除逻辑。
- 现有未关联虚拟 Battery Power Switch 直接删除路径改为确认后再删除，删除动作本身不变。
- 非 8-key power switch 继续使用现有 Kinetic 删除确认。

`PJEightKeySwitchMonitorVC`：

- 详情页右上角删除时，Battery/AC 均先展示对应专用文案。
- 未关联虚拟 switch 仍执行原本的本地删除动作，但必须在确认后执行。
- 真实设备继续通过原 `deleteSwitchAction` 回调进入现有删除流程。

`PJPreAddEightKeySwitchesVC`：

- Edit / PreAdd 页面删除 source switch 时，Battery/AC 使用对应专用文案。
- 现有非 Battery/AC 或无法识别为 8-key power switch 的删除回调保持原行为。

`GroupPowerSwitchesViewController`：

- Group Power Switch 页面删除 Battery/AC 时，真实和虚拟都先展示对应专用文案。
- 虚拟 switch 原本的 detach 行为和真实 switch 原本的 delete group sync 行为不变。

## 本地化

英文文案按用户指定精确落地：

- `Are you sure to delete the battery power switch?`
- `Are you sure to delete the AC power switch?`

中文本地化补齐对应 key，避免中文环境显示 key 或 fallback 异常。中文可采用语义一致的翻译：

- `确定删除该电池供电开关？`
- `确定删除该 AC 供电开关？`

按钮继续复用现有 `.cancelAction` 与 `confirm.localizedString`，英文环境显示 `CANCEL` / `CONFIRM`。

## 测试与验证

- 静态检查所有 `switchs_delete_message` 在 8-key power switch 删除入口中的使用点，确认 Battery/AC 不再复用 Kinetic 删除文案。
- 验证 Main - Switches 编辑态删除真实 Battery、虚拟 Battery、真实 AC、虚拟 AC 都出现对应确认弹窗。
- 验证详情页、Edit / PreAdd 页、Group Power Switch 页的 Battery/AC 删除提示一致。
- 验证 Kinetic Switch 删除提示保持现状。
- 运行 iPhoneOS 构建：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 风险

- 当前代码存在多个删除入口，遗漏入口会导致提示不统一。实施时需要用全文搜索确认所有 Battery/AC 删除路径。
- 如果某个 `DeviceSwitchData` 无法转换为 `PJEightKeySwitchData`，应保持旧 Kinetic 路径，避免误判普通 switch。
- 不应修改 Kinetic 的 `switch_delete_message` 与 `switchs_delete_message`，否则会影响用户明确要求保持现状的旧流程。
