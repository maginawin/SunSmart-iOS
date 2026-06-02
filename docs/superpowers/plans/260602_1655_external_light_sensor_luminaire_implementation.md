# External Light Sensor Capable Luminaire Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `0x0A78` 下指定 Product ID 的可外接光照传感器灯设备增加集中能力标记，并在 Calibration 的 `Select daylight sensor` 启用前提示用户确认外接传感器已连接。

**Architecture:** 设备能力判断集中放在 `Node` 扩展中，Calibration UI 继续由 `LightSensorCalibrationSelectView` 上报开关意图，`LightSensorCalibrationViewController` 负责业务拦截、弹窗和复用现有 enable 流程。新增弹窗 title、message、button 都通过专用本地化 key 提供，并在中英文资源里保持需求指定的英文原文。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, SRAlertView, Xcode workspace `SunSmart.xcworkspace`

---

## File Structure

- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 增加 `Node.isExternalLightSensorCapableLuminaire(companyIdentifier:productIdentifier:)`
  - 增加实例 getter `node.isExternalLightSensorCapableLuminaire`
- Modify: `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
  - 在 `didSelectDaylightSensor` 的现有流程前加 loading guard 和特殊设备确认弹窗
  - 将原有选择逻辑抽到私有 helper，确保 `CONFIRM` 后复用原流程
- Modify: `SunSmart/en.lproj/Localizable.strings`
  - 增加外接光照传感器确认提示 title、message、button key
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 增加同一组 key，值保持英文需求原文

当前仓库未发现明显 XCTest target，本计划不新增测试 target，验证以静态检查和项目指定 iPhoneOS build 为准。

---

### Task 1: Add Node Capability Getter

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: 定位现有产品能力 helper**

Run:

```bash
rg -n "isEmergencySignController|isPowerSwitch|batteryPowerSwitchProductIdentifiers" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: 能看到 `Node.isEmergencySignController(companyIdentifier:productIdentifier:)` 和实例 getter `var isEmergencySignController`。

- [ ] **Step 2: 增加静态产品判断**

在 `private static let emergencySignControllerCompanyIdentifier` 附近增加：

```swift
private static let externalLightSensorCapableLuminaireCompanyIdentifier: UInt16 = 0x0A78
private static let externalLightSensorCapableLuminaireProductIdentifiers: Set<UInt16> = [
    0x2121,
    0x2122,
    0x2132,
    0x2133,
    0x2491,
    0x2492,
    0x2493,
    0x2494
]

static func isExternalLightSensorCapableLuminaire(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
    guard companyIdentifier == externalLightSensorCapableLuminaireCompanyIdentifier,
          let productIdentifier else {
        return false
    }
    return externalLightSensorCapableLuminaireProductIdentifiers.contains(productIdentifier)
}
```

- [ ] **Step 3: 增加实例 getter**

在 `var isEmergencySignController: Bool` 附近增加：

```swift
var isExternalLightSensorCapableLuminaire: Bool {
    return Node.isExternalLightSensorCapableLuminaire(
        companyIdentifier: companyIdentifier,
        productIdentifier: productIdentifier
    )
}
```

- [ ] **Step 4: 静态检查 getter 定义**

Run:

```bash
rg -n "externalLightSensorCapableLuminaire|isExternalLightSensorCapableLuminaire" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: 输出包含静态 company 常量、Product ID 集合、静态方法和实例 getter。

---

### Task 2: Add Localized Message

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: 确认通用 title 和 button key 不能满足所有语言**

Run:

```bash
rg -n '"notification"|"cancel"|"confirm"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 英文资源中 `notification = Notification`、`cancel = CANCEL`、`confirm = CONFIRM` 已存在；中文资源中这些 key 为中文，因此本功能需要专用 key 才能保证所有语言下都显示需求指定英文。

- [ ] **Step 2: 在英文资源增加专用弹窗 key**

在 `sensor_calibration_minimum_version_message` 附近增加：

```text
"external_light_sensor_capable_luminaire_calibration_title" = "Notification";
"external_light_sensor_capable_luminaire_calibration_message" = "This device has the ability to connect to an external light sensor. Before calibration, please ensure that the sensor is connected.";
"external_light_sensor_capable_luminaire_calibration_cancel" = "CANCEL";
"external_light_sensor_capable_luminaire_calibration_confirm" = "CONFIRM";
```

- [ ] **Step 3: 在中文资源增加同名专用弹窗 key**

在 `sensor_calibration_minimum_version_message` 附近增加同样英文文案：

```text
"external_light_sensor_capable_luminaire_calibration_title" = "Notification";
"external_light_sensor_capable_luminaire_calibration_message" = "This device has the ability to connect to an external light sensor. Before calibration, please ensure that the sensor is connected.";
"external_light_sensor_capable_luminaire_calibration_cancel" = "CANCEL";
"external_light_sensor_capable_luminaire_calibration_confirm" = "CONFIRM";
```

- [ ] **Step 4: 检查专用 key 唯一且双语言都存在**

Run:

```bash
rg -n '"external_light_sensor_capable_luminaire_calibration_(title|message|cancel|confirm)"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 输出 8 行，英文和中文资源各包含 4 个专用 key。

---

### Task 3: Gate Special Device Enable With Confirmation

**Files:**
- Modify: `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`

- [ ] **Step 1: 定位现有选择入口**

Run:

```bash
rg -n "didSelectDaylightSensor|didDeselectDaylightSensor|sensorEnabled\\(" SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift
```

Expected: 能看到 delegate 入口 `func view(_:didSelectDaylightSensor:lastSelectSensor:)`、取消选择入口和 `sensorEnabled(sensor:resetCalibrated:result:)`。

- [ ] **Step 2: 新增确认弹窗 helper**

在 `LightSensorCalibrationViewController` 主 class 内、delegate extension 之前增加：

```swift
private func showExternalLightSensorConnectionAlert(confirmHandler: @escaping () -> Void) {
    SRAlertView(
        title: "external_light_sensor_capable_luminaire_calibration_title".localizedString,
        message: "external_light_sensor_capable_luminaire_calibration_message".localizedString,
        actions: [
            SRAlertAction(title: "external_light_sensor_capable_luminaire_calibration_cancel".localizedString, style: .cancel),
            SRAlertAction(title: "external_light_sensor_capable_luminaire_calibration_confirm".localizedString, actionHandler: { _ in
                confirmHandler()
            })
        ]
    ).show()
}
```

- [ ] **Step 3: 将现有选择逻辑抽到私有 helper**

把当前 `func view(_ view: LightSensorCalibrationSelectView, didSelectDaylightSensor selectSensor: Node, lastSelectSensor: Node?)` 中从 `var lastSelectSensorUnPublish: Bool = false` 开始到方法结束前的现有实现，移动到新的私有方法：

```swift
private func enableDaylightSensor(
    _ selectSensor: Node,
    lastSelectSensor: Node?,
    in view: LightSensorCalibrationSelectView
) {
    var lastSelectSensorUnPublish: Bool = false
    var selectSensorPublish: Bool = false

    if lastSelectSensor != nil {
        if let sensorModel = lastSelectSensor!.ambientLightSensorModel,
           sensorModel.publish?.publicationAddress == group.address {
            lastSelectSensorUnPublish = true
        }
    }

    if selectSensor.sensorCalibrated {
        selectSensorPublish = true
    }

    if let sensor = lastSelectSensor {
        if lastSelectSensorUnPublish {
            sensor.selectState = .loading
        } else {
            sensor.selectState = .switchOff
        }
        view.reloadSensorCell(sensor: sensor)
    }

    DispatchQueue.global().async {
        var disableLastSensor: Bool = true
        let semaphore = DispatchSemaphore(value: 0)
        if lastSelectSensorUnPublish, let sensor = lastSelectSensor {
            self.sensorDisable(sensor: sensor, lightConfig: !selectSensorPublish) { [weak self] result in
                disableLastSensor = result
                DispatchQueue.main.async {
                    sensor.selectState = result ? .switchOff : .switchOn
                    view.reloadSensorCell(sensor: sensor)
                    if result {
                        if self?.selectSensor == sensor {
                            self?.selectSensor = nil
                        }
                        self?.group.info.ambientLightSensorNodeAddress = nil
                        self?.updateGroupLightSensor()
                        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                    } else {
                        selectSensor.selectState = .switchOff
                        view.reloadSensorCell(sensor: selectSensor)
                        SRAlertView(title: "notification".localizedString, message: "sensor_calibration_disable_failed_message".localizedString, actions: [SRAlertAction(title: "ok".localizedString)]).show()
                    }
                }
                semaphore.signal()
            }
            semaphore.wait()
        }

        guard disableLastSensor else {
            return
        }

        DispatchQueue.main.async {
            if selectSensorPublish {
                selectSensor.selectState = .loading
            } else {
                selectSensor.selectState = .switchOn
                self.selectSensor = selectSensor
                self.updateCalibrationState()
            }
            view.reloadSensorCell(sensor: selectSensor)
        }

        if selectSensorPublish {
            self.sensorEnabled(sensor: selectSensor, resetCalibrated: true) { [weak self] result in
                DispatchQueue.main.async {
                    selectSensor.selectState = result ? .switchOn : .switchOff
                    view.reloadSensorCell(sensor: selectSensor)
                    if result {
                        self?.selectSensor = selectSensor
                        self?.onPointLuxView.measuredLightValue = nil
                        self?.offPointLuxView.measuredLightValue = nil
                        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                    }
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
        DispatchQueue.main.async {
            self.updateCalibrationState()
            self.updateManualCorrectionBtn()
        }
    }
}
```

Expected: 这段代码与现有选择逻辑行为一致，只是移动到 helper 中。

- [ ] **Step 4: 用确认 gate 包装 delegate 入口**

将 delegate 入口改为：

```swift
func view(_ view: LightSensorCalibrationSelectView, didSelectDaylightSensor selectSensor: Node, lastSelectSensor: Node?) {
    view.endEditing(true)
    if group.ambientLightSensorNodes.contains(where: { $0.selectState == .loading }) {
        return
    }

    guard selectSensor.isExternalLightSensorCapableLuminaire else {
        enableDaylightSensor(selectSensor, lastSelectSensor: lastSelectSensor, in: view)
        return
    }

    showExternalLightSensorConnectionAlert { [weak self, weak view] in
        guard let self,
              let view else {
            return
        }
        self.enableDaylightSensor(selectSensor, lastSelectSensor: lastSelectSensor, in: view)
    }
}
```

Expected:

- loading 中直接 return，不显示新弹窗。
- 普通 daylight sensor 直接进入原 enable 流程。
- 特殊设备 disabled -> enabled 先显示弹窗，`CONFIRM` 后进入原 enable 流程。
- `CANCEL` 不调用 `enableDaylightSensor`，因此不发送 enable 消息。

- [ ] **Step 5: 确认 disable 流程未改动**

Run:

```bash
sed -n '860,910p' SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift
```

Expected: `didDeselectDaylightSensor` 中没有新增外接传感器弹窗判断。

---

### Task 4: Static Verification And Build

**Files:**
- Verify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Verify: `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
- Verify: `SunSmart/en.lproj/Localizable.strings`
- Verify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: 检查 Product ID 列表完整性**

Run:

```bash
rg -n "0x2121|0x2122|0x2132|0x2133|0x2491|0x2492|0x2493|0x2494" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: 8 个 Product ID 都只出现在 `externalLightSensorCapableLuminaireProductIdentifiers` 附近。

- [ ] **Step 2: 检查 UI 只在 enable 入口弹窗**

Run:

```bash
rg -n "showExternalLightSensorConnectionAlert|isExternalLightSensorCapableLuminaire|didDeselectDaylightSensor" SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift
```

Expected:

- `isExternalLightSensorCapableLuminaire` 只在 `didSelectDaylightSensor` 路径使用。
- `didDeselectDaylightSensor` 路径没有调用 `showExternalLightSensorConnectionAlert`。

- [ ] **Step 3: 检查本地化 key**

Run:

```bash
rg -n '"external_light_sensor_capable_luminaire_calibration_(title|message|cancel|confirm)"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected:

- 4 个专用 key 在英文和中文资源中各出现一次。
- 两个语言资源中的 title、message、cancel、confirm 值均保持需求指定英文。

- [ ] **Step 4: 运行项目指定构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 检查最终 diff**

Run:

```bash
git diff -- SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: diff 只包含能力 getter、本地化 message、Calibration enable 前确认弹窗，不包含无关重构或大量格式化。

---

## Commit Plan

建议按两个提交执行：

1. `feat: mark external light sensor capable luminaires`
   - `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
2. `feat: confirm external sensor before calibration`
   - `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
   - `SunSmart/en.lproj/Localizable.strings`
   - `SunSmart/zh-Hans.lproj/Localizable.strings`

如果实现时改动非常小，也可以合并为一个提交：

`feat: confirm external light sensor before calibration`
