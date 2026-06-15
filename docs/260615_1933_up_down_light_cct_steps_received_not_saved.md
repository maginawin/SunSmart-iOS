# Up/Down Light CCT Default Steps 收到但未展示 6500K 分析

## 现象

删除 Up/Down Light 后重新添加，日志中能看到：

`Optional(NordicSigMeshSDK.FunctionParameters.upDownLightDefaultCctSteps(6)))) received from: 0072, to: 0023`

但 Device Parameter Settings 中 `Absolute CCT Range` 仍展示 `2700K...5000K`。

## 结论

不是单纯的 `effectiveCctRange` 计算公式问题，而是存在保存链路漏洞：

- SDK 已经解析到了 `.upDownLightDefaultCctSteps(6)`，所以日志能打印出来。
- 但原先只有 `UpDownLightDefaultCctStepsReader` 的 `MeshAPI.sendMessage` 回调会把 steps 保存到 `node.upDownLightDefaultCctSteps`。
- `MeshAPI.sendMessage(message:model:)` 底层 wait callback 只按 `SunricherVendorStatus` 的 opcode 和 source address 等待，不按 vendor function 过滤。
- 如果同一个节点先返回了其他 vendor status，reader 可能会把这次回调当成无效结果并保存 fallback `5`。
- 后续真正的 `.upDownLightDefaultCctSteps(6)` 仍会被 AccessLayer 打印日志，但因为 `Node.updateNodeStatus(message:)` 没有处理这个参数，所以不会落库。

因此会出现“日志看到了 steps=6，但节点缓存仍是 5，页面仍显示 2700K...5000K”的情况。

## 修复

在本地 `NordicSigMeshSDK` 增加通用接收路径保存：

- 文件：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift`
- 在 `Node.updateNodeStatus(message:source:)` 的 `SunricherVendorStatus` 分支中处理 `.upDownLightDefaultCctSteps(let steps)`。
- 收到该 status 后直接写入 `node.upDownLightDefaultCctSteps = steps`，并复用原有 `savePropertys()` 落库。

这样只要日志中确实收到 `.upDownLightDefaultCctSteps(6)`，即使 reader 的 callback 没命中，节点也会保存 steps `6`，后续默认 `Absolute CCT Range` 可以计算为 `2700K...6500K`。

## 补充测试规格

新增 SDK 测试规格：

- 文件：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`
- 用例：`testUpDownLightDefaultCctStepsStatusUpdatesNodeCachedSteps`

覆盖场景：

1. 构造 `CID 0x0A78 / PID 0x2491` 节点。
2. 模拟收到 `[0x53, 0x01, 0x00, 0x06]` vendor status。
3. 调用 `node.updateNodeStatus(message:source:)`。
4. 期望 `node.upDownLightDefaultCctSteps == 6`，且默认范围为 `2700...6500`。

## 验证

- `swift test --filter NodeCctDefaultValueTests/testUpDownLightDefaultCctStepsStatusUpdatesNodeCachedSteps`
  - 当前 SDK 的 SPM 测试环境仍在编译阶段失败于 `no such module 'UIKit'`，未进入断言；这是既有 package test 环境限制。
- `git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check`
  - 通过。
- `git diff --check`
  - 通过。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
  - 通过，输出 `** BUILD SUCCEEDED **`。
