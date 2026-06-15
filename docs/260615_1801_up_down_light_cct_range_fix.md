# Up/Down Light 默认 CCT Steps 与 Absolute CCT Range 展示修复

## 问题现象

添加 Up/Down Light 时，设备回复：

`Optional(NordicSigMeshSDK.FunctionParameters.upDownLightDefaultCctSteps(6)))) received from: 1D58, to: 1D4E`

预期 Device Parameter / Absolute CCT Range 展示为 `2700K~6500K`，实际展示为 `2700K~5000K`。

## 根因

添加设备流程中，App 会先追加发送 `LightCTLTemperatureRangeGet`，并在收到返回后通过 `Node.updateData(message:)` 保存：

- `node.absoluteCctRange = message.range`
- `node.lightCTLTemperatureRange = message.range`

对 Up/Down Light 来说，后续 `UpDownLightDefaultCctStepsReader` 会读取 vendor `upDownLightDefaultCctSteps`。当设备返回 `6` 时，SDK 的 `defaultAbsoluteCctRange` 会推导为标准范围 `2700...6500`。

但 SDK 当前 `Node.effectiveCctRange` 的优先级是：

`absoluteCctRange ?? defaultAbsoluteCctRange`

因此如果早一步 `LightCTLTemperatureRangeGet` 已经把旧的五步范围 `2700...5000` 写入 `absoluteCctRange`，后续即使 `upDownLightDefaultCctSteps = 6`，展示层仍会优先使用 `absoluteCctRange`，导致显示 `2700K~5000K`。

## 修复方案

修改本地 `NordicSigMeshSDK`：

- 文件：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
- 在 `Node.effectiveCctRange` 中增加一个窄规则：
  - 仅当设备是 Up/Down Light default CCT steps 产品
  - 且 `upDownLightDefaultCctSteps == 6`
  - 且当前 `absoluteCctRange == NodeAbsoluteCctRange.singleWhiteDefaultRange`
  - 返回 `defaultAbsoluteCctRange`，即 `2700...6500`

这样只把配网阶段读到的 legacy five-step default range 让位给 steps=6 的标准范围。用户或配置流程设置的其他 absolute range，例如 `3000...4500`，仍然继续优先于默认范围。

## 测试规格

新增 SDK 测试：

- 文件：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`
- 用例：`testUpDownLightSixDefaultCctStepsIgnoresLegacyFiveStepAbsoluteRange`

该用例覆盖：

1. Up/Down Light 先存在 legacy five-step absolute range `2700...5000`
2. 设备随后回复并保存 `upDownLightDefaultCctSteps = 6`
3. `effectiveCctRange` 应返回标准范围 `2700...6500`

## 验证

- `swift test --filter NodeCctDefaultValueTests/testUpDownLightSixDefaultCctStepsIgnoresLegacyFiveStepAbsoluteRange`
  - 当前 SDK 的 SPM 测试环境在编译阶段失败于 `no such module 'UIKit'`，未能跑到断言；这是 SDK package 在 macOS test 环境引用 UIKit 的既有限制。
- `git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check`
  - 通过。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
  - 通过，输出 `** BUILD SUCCEEDED **`。
