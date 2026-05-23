# Battery Power Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 支持 PID `0x2A01`、`0x2A02` Battery Power Switch 设备作为 Switch 添加、展示、计数和连接控制；仅允许 Add 与 BLE Direct OTA 连接，Add 成功和 OTA 成功后主动断开 BLE。

**Architecture:** 以现有 `devices_config.json` 与 `Node.DeviceType` 映射为入口，将新 PID 配置为 `Switches`，复用 Switch 默认命名与页面计数规则；SDK 侧先审计已有 Battery Power Switch 能力，只在缺失时补齐，避免重复接口；App 层补齐添加前 16 个上限拦截、添加成功生成 Switch 数据、连接断开与 OTA 完成断开。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Xcode workspace `SunSmart.xcworkspace`。

---

## Implementation Tasks

- [ ] 1. SDK 能力审计

  先确认 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk` 是否已经支持 Battery Power Switch，不允许直接新增重复 SDK 接口。

  执行：

  ```bash
  rg -n "BatteryPowerSwitch|batteryPowerSwitch|2A01|2A02|RequiredConfiguration|shouldFailBattery|lowPower" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK SunSmart -g '!user-temp/**'
  ```

  重点检查：

  - `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`
  - `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshFastAddDeviceManager.swift`
  - `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshLibManager.swift`
  - `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/NetworkConnection.swift`
  - SDK Vendor message 文件中 Battery Power Switch capability/key config/LED/reset 相关实现。

  验收：

  - 如果已经存在 `batteryPowerSwitchRequiredModels`、`isBatteryPowerSwitchRequiredConfigurationSupported`、Battery Power Switch key bind 失败处理、Low Power proxy 过滤，则不修改 SDK 接口。
  - 如果发现缺失，只补缺失的模型配置能力，不新增与现有命名或语义重复的 API。
  - 在实现提交说明中明确写出 SDK 审计结论。

- [ ] 2. 添加设备配置

  修改 `SunSmart/devices_config.json`，新增两个设备配置，分类必须落到现有 Switch 体系。

  配置要求：

  ```json
  {
      "companyId": "0A78",
      "productId": "2A01",
      "categoryName": "Battery Power Switch",
      "elementCount": 8,
      "iconCategory": "BatteryPowerSwitch",
      "deviceCategory": "Switches",
      "modelName": "SR-BL2422K8N-4SC(US)"
  }
  ```

  ```json
  {
      "companyId": "0A78",
      "productId": "2A02",
      "categoryName": "Battery Power Switch",
      "elementCount": 8,
      "iconCategory": "BatteryPowerSwitch",
      "deviceCategory": "Switches",
      "modelName": "SR-BL2422K8N-4DIM(US)"
  }
  ```

  验收：

  ```bash
  rg -n "\"2A01\"|\"2A02\"|\"BatteryPowerSwitch\"" SunSmart/devices_config.json
  ```

  - `deviceCategory` 是 `"Switches"`，保证解析为 `Node.DeviceType.switches`。
  - `iconCategory` 是 `"BatteryPowerSwitch"`，匹配现有 `device_BatteryPowerSwitch.imageset` 资源命名规则。

- [ ] 3. 增加 Battery Power Switch 判定 helper

  在 App 侧新增集中判定，避免在多个控制器里散落 PID 字符串。

  建议修改：

  - `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - `SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift`

  目标：

  - `Node` 可通过 company ID + product ID 判断 `isBatteryPowerSwitch`。
  - `ProvisioningDevice` 可通过扫描到的 PID 判断 `isBatteryPowerSwitch`。
  - PID 集合只维护一份，包含 `2A01`、`2A02`。

  验收：

  ```bash
  rg -n "isBatteryPowerSwitch|2A01|2A02" SunSmart/Common SunSmart/Main/Device -g '!user-temp/**'
  ```

  - 后续 Add、OTA、断开逻辑都使用 helper，不直接重复比较字符串。

- [ ] 4. 添加前执行 16 个 Switch 上限拦截

  修改：

  - `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

  行为：

  - 扫描阶段识别到 Battery Power Switch 且当前 `MeshNetworkManager.instance.switchs.count >= 16` 时，将该设备置为不可选或不可添加状态。
  - 用户点击添加前再次检查，避免扫描后数量变化导致绕过。
  - 提示文案复用现有 Switch 上限提示，例如 `switchs_overrun_message`。

  实现入口定位：

  ```bash
  rg -n "checkDeviceAddressesAreSufficient|selectedState|addDevice|switchs_overrun_message|candidateDevices" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
  ```

  验收：

  - `switchs.count == 16` 时，Battery Power Switch 不能进入 provisioning。
  - 普通 Light、Sensor、Gateway 添加行为不变化。
  - 此拦截发生在添加前，不等到添加成功后失败。

- [ ] 5. 添加成功后创建 Switch 数据

  修改：

  - `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 如需要，补充 `MeshNetworkManager` 或 Switch 数据 helper。

  行为：

  - Battery Power Switch 添加成功后，自动创建一个默认 Switch 数据，沿用现有 Switch 默认命名规则。
  - 新 Switch 计入 `MeshNetworkManager.instance.switchs`，并参与主页 Switch 页面 16 个上限。
  - 刷新 Site / Space / Home 的 Switch 分类计数与列表。

  注意：

  - 实现前必须检查 `DeviceSwitchData`、`PJEightKeySwitchData`、`PJEightKeySwitchRepository` 当前字段语义。
  - 如果使用 `proxyNodeAddress` 关联真实 Battery Power Switch 节点，会与现有 kinetic switch proxy 语义发生冲突，则改为新增专用元数据映射，不能破坏现有 kinetic switch 绑定状态。
  - 不为了这两个 PID 改动无关 Switch 页面 UI。

  验收：

  ```bash
  rg -n "createDefaultSwitch|getNextSwitchName|PJEightKeySwitch|proxyNodeAddress|switchsRefreshNotificationName" SunSmart -g '!user-temp/**'
  ```

  - 添加成功后新建 Switch 名称与已有 Switch 规则一致。
  - 重复回调不会重复创建多个 Switch 数据。
  - Space 的 Switch 数量与 `MeshNetworkManager.instance.switchs.count` 一致。

- [ ] 6. 添加配置过程绑定当前 Space AppKey

  基于 SDK 审计结果处理。

  预期 SDK 已支持：

  - Battery Power Switch required models 集合。
  - `getConfigMessageHandles` 会为 Battery Power Switch profile/client/battery 相关 models 绑定 AppKey。
  - required configuration 失败时 Fast Add 会失败。

  App 侧需要确认：

  - Add 流程传入的是当前 Space 的 AppKey。
  - Battery Power Switch 不走会跳过 Model AppKey bind 的特殊分支。
  - 所有 Modes 对应 Models 的 bind 失败会导致 Add 失败，不会静默添加成功。

  验收：

  - 审计代码路径能从 Add controller 追踪到 SDK `MeshFastAddDeviceManager` 配置消息。
  - 如果 SDK 已完整支持，仅记录结论，不新增 SDK 接口。
  - 如果发现当前 Space AppKey 未传入，优先修 App 调用参数。

- [ ] 7. 避免 Battery Power Switch 走 Lighting 默认配置

  修改 Add 成功后 append message 逻辑，避免 `.switches` 设备误发 lighting 默认值。

  目标文件：

  - `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

  行为：

  - lighting 默认 on/off、level、CCT、sensor 等消息只发给 Light 或已有明确支持的设备。
  - Battery Power Switch 不发送 Light model 默认配置。

  验收：

  - Battery Power Switch 添加成功后不因为缺少 Light models 触发无效 message。
  - Light、Emergency、Dongle、Gateway 原有分支不变。

- [ ] 8. Add 成功后主动断开 Battery Power Switch BLE

  修改 Classic 与 Professional Add 流程收尾。

  行为：

  - Add 成功后，对 `addSuccessNodes` 中的 Battery Power Switch 执行 BLE 断开。
  - 断开应发生在添加成功状态、网络保存和必要通知之后，避免影响 Add 成功写入。
  - 仅断开 Battery Power Switch，不影响普通 Proxy 节点。

  可复用能力：

  - `MeshLibManager.manager.disconnectProxy(node:)`
  - SDK 已有 `NetworkConnection.disconnect(node:)`

  验收：

  ```bash
  rg -n "disconnectProxy|disconnect\\(node|addSuccessNodes|deviceAddCallback" SunSmart /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK -g '!user-temp/**'
  ```

  - Add 成功后主动断开这两个 PID。
  - Add 失败或取消时不引入额外异常。

- [ ] 9. 限制非 Add / BLE Direct OTA 场景连接 Battery Power Switch

  基于 SDK 审计结果补齐 App 层防护。

  预期 SDK 已支持：

  - `NetworkConnection.shouldSkipAutomaticProxy(macAddress:)` 跳过 Low Power enabled 节点。
  - `MeshLibManager.connectProxy(node:)` 拒绝 Low Power enabled 节点。

  App 侧检查：

  - 普通自动 Proxy 连接不会连接 Features Low Power enabled 节点。
  - 只有 Add 与 BLE Direct OTA 的扫描/连接路径允许 Battery Power Switch。
  - 其他页面直接连接或刷新 RSSI 时，如绕过 SDK Low Power 判断，需要加 `isBatteryPowerSwitch` guard。

  验收：

  - Battery Power Switch 添加后不会被后续自动 Proxy 连接选中。
  - 普通 Proxy 节点自动连接行为不变。
  - BLE Direct OTA 仍能连接 Battery Power Switch。

- [ ] 10. BLE Direct OTA 成功后主动断开 Battery Power Switch

  修改：

  - `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`

  行为：

  - `completeCallback` 中，对 `successfulList` 里的 Battery Power Switch 节点主动断开 BLE。
  - 只在 OTA 成功后按要求断开；失败节点保留现有失败处理，不引入额外副作用。
  - 使用与 Add 成功相同的断开 helper 或 `MeshLibManager.manager.disconnectProxy(node:)`。

  验收：

  ```bash
  rg -n "completeCallback|successfulList|disconnectProxy|FirmwareUpdateTarget" SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift SunSmart -g '!user-temp/**'
  ```

  - OTA 成功后这两个 PID 的 BLE 连接被主动断开。
  - 其他 OTA 节点行为不变。

- [ ] 11. 验证与构建

  代码验证：

  ```bash
  rg -n "\"2A01\"|\"2A02\"|BatteryPowerSwitch|isBatteryPowerSwitch" SunSmart /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK -g '!user-temp/**'
  ```

  SDK 验证，如 SDK 有可运行测试：

  ```bash
  swift test
  ```

  在 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk` 下执行。

  App 构建验证必须按项目规则直接执行：

  ```bash
  xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
  ```

  验收：

  - SunSmart Debug iphoneos 构建通过。
  - 如 SDK 未修改，说明未运行 SDK 测试的原因或审计结论。
  - 若构建失败，先判断是否由本任务改动导致；非本任务历史问题需在最终说明中明确。

---

## Commit Plan

- [ ] SDK 审计结论与 App 配置/helper 改动一个提交。
- [ ] Add 限制、Add 成功创建 Switch、Add 成功断开一个提交。
- [ ] OTA 成功断开与连接防护补齐一个提交。
- [ ] 构建修复或测试补充按实际情况单独提交。

提交时只包含本任务相关文件，不加入用户已有资源暂存文件，除非用户明确要求。
