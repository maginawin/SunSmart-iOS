# Battery Power Switch BLE OTA 离线图标优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Site → Space → More → Firmware update via BLE 页面中的 Battery Power Switch 在未被扫描到时展示 `device_offline_BatteryPowerSwitch`，并保持其他设备行为不变。

**Architecture:** 在现有 `BleFirmwareUpdateDeviceCell` 的 RSSI 离线分支内增加 Battery Power Switch 窄特判。继续复用 `Node.isBatteryPowerSwitch`、`Node.offlineIconName` 和现有在线图标逻辑，不引入新的状态层、资源或依赖。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Asset Catalog、Xcode `xcodebuild`

## Global Constraints

- 仅修改 Battery Power Switch 在 BLE Firmware Update 设备 Cell 中的离线图标。
- 在线时继续展示 `device_BatteryPowerSwitch`。
- 离线时展示 `device_offline_BatteryPowerSwitch`；资源加载失败时回退到当前灰色在线图标。
- AC Power Switch 和其他设备维持现有逻辑。
- 不改变 RSSI 扫描、设备选择、排序、升级状态或 OTA 流程。
- 不新增或修改图片资源、本地化、target 配置、依赖或 NordicSigMeshSDK。
- 保持改动聚焦，不重构同文件其他 UI。
- 验证使用 SunSmart Debug、iPhoneOS、关闭代码签名；不使用 Simulator。

---

## 文件结构

- 修改：`SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift`
  - 仅负责在既有离线分支选择 Battery Power Switch 离线图标，并保留资源失败回退。
- 创建：`docs/260721_1654_battery_power_switch_ble_ota_offline_icon_implementation_summary.md`
  - 记录实施范围、验证结果和未覆盖的真机验收项。

### Task 1: 实现 Battery Power Switch 离线图标窄特判

**Files:**

- Modify: `SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift:786-798`
- Test: 源代码契约检查、Asset Catalog JSON 检查、SunSmart iPhoneOS 构建

**Interfaces:**

- Consumes: `Node.rssi: Int?`、`Node.isBatteryPowerSwitch: Bool`、`Node.bleFirmwareIconName: String`、`Node.offlineIconName: String`
- Produces: `BleFirmwareUpdateDeviceCell.deviceImageView.image` 的 Battery Power Switch 离线选择行为；不新增公开接口

- [ ] **Step 1: 记录失败的离线资源契约基线**

运行：

```bash
rg -n "device\.offlineIconName" SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift
```

预期：退出码为 1 且无匹配，证明当前 BLE OTA 设备 Cell 没有使用离线资源。

同时确认当前离线回退基线：

```bash
rg -n "UIImage\(named: device\.bleFirmwareIconName\)\?\.withTintColor\(SubText_Color\)" SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift
```

预期：匹配现有离线分支，证明当前使用灰色在线图标。

- [ ] **Step 2: 确认 Battery Power Switch 资源与配置链路有效**

运行：

```bash
test -d SunSmart/Assets.xcassets/Device/device_BatteryPowerSwitch.imageset
test -d SunSmart/Assets.xcassets/Device/device_offline_BatteryPowerSwitch.imageset
jq empty SunSmart/Assets.xcassets/Device/device_BatteryPowerSwitch.imageset/Contents.json
jq empty SunSmart/Assets.xcassets/Device/device_offline_BatteryPowerSwitch.imageset/Contents.json
rg -n '"iconCategory": "BatteryPowerSwitch"' SunSmart/devices_config.json
```

预期：所有命令退出码为 0；两个资源目录存在、JSON 合法，Battery Power Switch 配置映射存在。

- [ ] **Step 3: 写入最小实现**

在 `device.rssi == nil` 的现有分支中，保留名称、RSSI、选择状态处理，只替换图标赋值部分：

```swift
let tintedOnlineImage = UIImage(named: device.bleFirmwareIconName)?.withTintColor(SubText_Color)
if device.isBatteryPowerSwitch {
    deviceImageView.image = UIImage(named: device.offlineIconName) ?? tintedOnlineImage
} else {
    deviceImageView.image = tintedOnlineImage
}
```

不要修改在线分支的 `UIImage(named: device.bleFirmwareIconName)`，也不要将 AC Power Switch 纳入特判。

- [ ] **Step 4: 运行通过的源码契约检查**

运行：

```bash
rg -n "let tintedOnlineImage|if device\.isBatteryPowerSwitch|UIImage\(named: device\.offlineIconName\)|deviceImageView\.image = tintedOnlineImage" SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift
```

预期：四个新实现要点均有匹配。

运行：

```bash
rg -n "deviceImageView\.image = UIImage\(named: device\.bleFirmwareIconName\)" SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift
```

预期：在线分支原有赋值仍有匹配。

运行：

```bash
rg -n "isACPowerSwitch|device_offline_ACPowerSwitch" SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift
```

预期：退出码为 1 且无匹配，证明没有扩大到 AC Power Switch。

- [ ] **Step 5: 审查改动范围和格式**

运行：

```bash
git diff -- SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift
git diff --check -- SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift
git status --short
```

预期：仅目标 Swift 文件发生业务改动，`git diff --check` 退出码为 0，未混入其他文件。

- [ ] **Step 6: 运行 iPhoneOS 构建**

运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：输出 `BUILD SUCCEEDED`；允许保留与本次改动无关的工程既有 warning。

- [ ] **Step 7: 提交业务实现**

运行：

```bash
git add SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift
git commit --only SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift -m "fix: show battery power switch offline icon in BLE OTA"
```

预期：生成仅包含目标 Swift 文件的实现提交。

### Task 2: 记录实施结果并完成提交后验证

**Files:**

- Create: `docs/260721_1654_battery_power_switch_ble_ota_offline_icon_implementation_summary.md`
- Verify: `SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift`

**Interfaces:**

- Consumes: Task 1 已提交的图标选择行为及验证输出
- Produces: 可审计的实施总结；不产生运行时接口

- [ ] **Step 1: 创建实施总结**

使用以下完整内容创建文档：

```markdown
# Battery Power Switch BLE OTA 离线图标优化实施总结

## 实施结果

- 仅调整 Firmware update via BLE 设备列表中的 Battery Power Switch 离线图标。
- 在线状态继续使用 `device_BatteryPowerSwitch`。
- 未被 BLE 扫描找到时使用 `device_offline_BatteryPowerSwitch`。
- 离线资源加载失败时回退到灰色在线图标。
- AC Power Switch、其他设备及 BLE OTA 流程保持不变。

## 改动范围

- `SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift`
- 未修改资源、本地化、target 配置、依赖或 NordicSigMeshSDK。

## 验证

- 在线、离线及非 Battery Power Switch 源码契约检查：通过。
- Battery Power Switch 在线/离线资源存在性和 Asset Catalog JSON 检查：通过。
- `git diff --check`：通过。
- SunSmart Debug iPhoneOS 构建：通过，输出 `BUILD SUCCEEDED`。

## 未覆盖项

- 未连接 Battery Power Switch 真机验证 BLE 扫描在线/离线切换效果；需要在具备对应设备的环境中完成运行时验收。
```

- [ ] **Step 2: 提交实施总结**

运行：

```bash
git add docs/260721_1654_battery_power_switch_ble_ota_offline_icon_implementation_summary.md
git commit --only docs/260721_1654_battery_power_switch_ble_ota_offline_icon_implementation_summary.md -m "docs: summarize battery power switch BLE OTA offline icon"
```

预期：生成仅包含实施总结的文档提交。

- [ ] **Step 3: 运行提交后的新鲜验证**

运行：

```bash
git diff --check HEAD^..HEAD
git status --short
rg -n "let tintedOnlineImage|if device\.isBatteryPowerSwitch|UIImage\(named: device\.offlineIconName\)" SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：文档提交无空白错误，工作树清洁，三个实现要点均有匹配，最终构建输出 `BUILD SUCCEEDED`。

- [ ] **Step 4: 记录运行时验收边界**

交付时明确说明：编译与静态契约已验证；由于本次没有连接 Battery Power Switch 真机，以下行为仍需设备验收：

- 扫描到 Battery Power Switch 时显示 `device_BatteryPowerSwitch`。
- 未扫描到 Battery Power Switch 时显示 `device_offline_BatteryPowerSwitch`。
- AC Power Switch 和其他设备展示与当前版本一致。
