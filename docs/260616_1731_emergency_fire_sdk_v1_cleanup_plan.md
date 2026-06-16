# Emergency Fire SDK V1 残留清理方案

## 背景

- 当前 App 已完成 Emergency Fire Controller v2 协议迁移。
- 本地 SDK 路径：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- 设备范围：Company ID `0x0A78`，Product ID `0x2131`。
- 协议范围：vendor opcode `0x4D` 的 Emergency Fire v2 编解码、测试命名、SDK Scene 常量和历史文档语义。

## 当前结论

SDK 当前可用协议 API 层没有保留 V1 调用入口：

- 当前 `Sources` / `Tests` 中没有 `EmergencyControllerMode`、`EmergencyControllerSceneIndex`、`EmergencyControllerResendParameters`、`EmergencyControllerCurrentModeStatus`。
- 当前 `Sources` / `Tests` 中没有 `emergencyMode`、`emergencyCurrentModeStatus`。
- `SunricherVendorGet`、`SunricherVendorSet`、`SunricherVendorStatus` 已使用 v2 的 `EmergencyFireStateIndex`、`EmergencyFireResendParameters`、`EmergencyFireComprehensiveStatus`、`EmergencyFireActionConfig`。
- `EmergencyControllerVendorMessageTests` 虽然仍使用旧测试类名，但测试内容已经是 v2，并包含旧 `mode + active` payload 的负向断言。

仍需清理的残留集中在命名和历史语义：

- 测试文件名和测试类名仍带 `EmergencyController`。
- `Group+LightLCScenes.swift` 中仍暴露 `fireAlarmStartScene`、`fireAlarmEndScene`、`emergencyStartScene`、`emergencyEndScene` 四个 V1 start/end 语义常量。
- `docs/260407_1540_scene_number_usage_analysis.md` 仍把 `0xFF20...0xFF23` 描述成火警/应急 start/end 四段分配，与 v2 三状态语义冲突。

## 目标

1. SDK 不再暴露 Emergency Fire V1 start/end Scene 常量。
2. SDK 对 Emergency Fire 的 public 命名统一倾向 `EmergencyFire`，避免新调用方误解为旧 `EmergencyController` 协议模型。
3. 文档明确 `0xFF20...0xFF22` 的 v2 三状态分配，`0xFF23` 不再绑定 Emergency Fire 语义。
4. 保留通用事件触发 Scene 段能力：`0xFF20...0xFF3F` 仍作为 SDK 内部特殊场景段，不进入用户场景列表。
5. 保留旧 payload 负向测试，防止 `0x4D/0x04` 回退到 V1 `mode + active` 解析。

## 非目标

- 不恢复 V1 兼容 API。
- 不改 App UI、App 数据库、App 同步模型。
- 不改变 `0x4D` v2 payload 编解码。
- 不改设备 PID 识别和 App 中 `EmergencyController` 设备分类命名。
- 不扩大到其他设备族或其他 vendor opcode。

## 设计方案

采用“语义替换”方案：

1. 保留通用事件触发段常量：
   - `minEventTriggerScene = 0xFF20`
   - `maxEventTriggerScene = 0xFF3F`
   - `isEventTriggerScene`
2. 删除 V1 四段 start/end 常量：
   - `fireAlarmStartScene`
   - `fireAlarmEndScene`
   - `emergencyStartScene`
   - `emergencyEndScene`
3. 新增 Emergency Fire v2 三状态 Scene 常量，名称表达 v2 状态而不是 start/end：
   - Emergency trigger：`0xFF20`
   - Fire trigger：`0xFF21`
   - Restore：`0xFF22`
4. 不再给 `0xFF23` 命名为 Emergency Fire 常量。该值仅作为 `0xFF20...0xFF3F` 事件触发段的保留槽。
5. 将 `EmergencyControllerVendorMessageTests.swift` 和测试类名重命名为 `EmergencyFireVendorMessageTests`，测试断言保持 v2 wire format。
6. 更新 `docs/260407_1540_scene_number_usage_analysis.md`：
   - 删除 V1 start/end 分配表述。
   - 改为 v2 三状态分配。
   - 明确 Emergency Fire v2 动作配置以 `0x4D/0x07` 为准，Scene 常量只表达 v2 状态和特殊场景隔离，不代表旧 publication + stop scene 流程。

## 影响面

- SDK 源码：`Sources/NordicSigMeshSDK/MeshLib/Group/Group+LightLCScenes.swift`
- SDK 测试：`Tests/NordicSigMeshSDKTests/EmergencyControllerVendorMessageTests.swift`
- SDK 文档：`docs/260407_1540_scene_number_usage_analysis.md`
- App 仓库只需要更新 Swift Package 引用后的编译验证，不需要改 App 业务代码。

## 风险

- 如果外部调用方仍引用旧 Scene 常量，会出现编译错误。该错误是预期结果，可以暴露 V1 语义调用点。
- 如果 `docs/260407_1540_scene_number_usage_analysis.md` 中的旧段落没有全部同步，后续仍可能误导开发人员。
- 测试文件重命名可能需要确认 Xcode/SwiftPM 是否自动识别新文件名；Swift Package tests 通常按目录自动收集，但仍需用构建验证确认。

## 验证计划

1. 在 SDK 仓库中搜索旧 V1 协议符号，确认没有命中：
   - `EmergencyControllerMode`
   - `EmergencyControllerSceneIndex`
   - `EmergencyControllerResendParameters`
   - `EmergencyControllerCurrentModeStatus`
   - `emergencyMode`
   - `emergencyCurrentModeStatus`
2. 搜索旧 Scene 常量名，确认没有命中：
   - `fireAlarmStartScene`
   - `fireAlarmEndScene`
   - `emergencyStartScene`
   - `emergencyEndScene`
3. 搜索 `0xFF23`，确认它不再被描述为 Emergency Fire v2 场景。
4. 运行 SDK iPhoneOS 构建：
   - `xcodebuild -project /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
5. 运行 App iPhoneOS 构建：
   - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
6. 运行 `git diff --check`。

## 交付标准

- SDK 不再暴露 V1 Emergency Fire Scene 常量。
- SDK 文档不再保留 V1 start/end 四段语义。
- Emergency Fire v2 协议编解码不发生行为变化。
- SDK iPhoneOS 构建通过。
- App iPhoneOS 构建通过，或明确记录与本清理无关的阻塞原因。
