# Bugly 场景列表与传感器校准崩溃分析及修复计划

## 范围

本次分析覆盖 Bugly 中的 2 类崩溃：

- Bug 1：`ScenesViewController.reloadCollectionItem(scene:)` 触发 `UICollectionView` invalid batch updates。
- Bug 2：`NordicSigMeshSDK.MeshSensorCalibrateManager.setCalibrateRate()` 触发 `SIGTRAP`。

本次仅分析与规划，不修改业务代码。

## Bug 1：场景列表 invalid batch updates

### 崩溃现象

Bugly 栈显示崩溃发生在 `ScenesViewController.reloadCollectionItem(scene:)`，UIKit 认为正在执行一次局部刷新，但 data source 的 item 数量从 4 变成 1：

- 更新前：1 个 section，4 个 item。
- 更新后：1 个 section，1 个 item。
- UIKit 看到的操作：删除 item 0，再插入 item 0。

这类异常说明 `reloadItems(at:)` 执行期间，collection view 认为只是刷新一个 cell，但 data source 实际返回的列表数量已经变化。

### 根因

原始风险模式是：列表 data source 直接读取全局场景数据，通知回调里对单个 scene 调用 `reloadItems(at:)`。如果同一轮通知/同步导致场景集合发生新增、删除、过滤变化，UIKit 的局部刷新校验就会失败。

本次 Bugly 栈来源于 `SceneSettingsViewController.saveAction()` 发出的 `sceneDataUpdateNotificationName`，理论上是场景内容更新，但实际全局场景数据在通知处理前后可能已经从 4 个变成 1 个，因此单 cell reload 不成立。

### 当前是否已修复

在当前工作区中，Bug 1 已经被现有改动覆盖。

证据：

- `SunSmart/Main/Scene/Controller/ScenesViewController.swift`
  - 第 46 行维护页面快照 `scenes`。
  - 第 225-226 行 `updateUI()` 用 `visibleScenes` 更新快照。
  - 第 315-339 行 `reloadCollectionItem(scene:)` 在局部刷新前校验：
    - 旧快照中存在该 scene。
    - 新快照中存在该 scene。
    - old/new index 一致。
    - 旧快照数量与新快照数量一致。
    - collection view 当前 item 数与旧快照一致。
    - 不满足时走 `updateUI()` 全量刷新。
  - 第 401-410 行 data source 使用快照 `scenes`，而不是直接读取全局场景数组。

这会覆盖 Bugly 中“更新前 4 个 item，更新后 1 个 item，却执行 reloadItems”的崩溃条件：数量变化时不会再进入 `reloadItems(at:)`，会改走全量 `reloadData()`。

### 剩余风险

- 如果线上版本未包含该快照改动，仍会复现。
- 如果还有其他 collection view 复用类似“全局数组 data source + 局部 reload”的模式，也可能发生同类崩溃，需要按列表页继续审计。

### 建议验证

- 进入场景列表，保留 4 个以上普通场景。
- 在场景设置页保存场景成员或名称，确认场景列表刷新正常。
- 在同步、过滤或删除导致场景数量变化的场景下触发 `sceneDataUpdateNotificationName`，确认不会崩溃并能全量刷新。
- 编译验证主 target。

## Bug 2：传感器校准 SIGTRAP

### 崩溃现象

Bugly 栈显示崩溃在线程 7，类型为 `SIGTRAP`：

- `NordicSigMeshSDK.MeshSensorCalibrateManager.setCalibrateRate()`
- 上一层来自 `setLightingAndSensorInflectionPoint()` 的 async 任务闭包。

Swift 中 `SIGTRAP` 常见于运行时前置条件失败，例如 `UInt16` 溢出/下溢。

### 根因

当前 SDK 中 `setCalibrateRate()` 使用 `UInt16` 直接做减法：

- `ambientLightOnLux - ambientLightOffLux`
- `lightOnLux - lightOffLux`

其中 `lightOnLux - lightOffLux` 前面已有 `onPoint.lux >= offPoint.lux` 防护，风险较低。

但 `ambientLightOnLux - ambientLightOffLux` 来自 App 用户输入或测量值。当前 App 入口只校验输入值是否在 `UInt16` 范围内，没有校验开灯照度是否大于关灯照度：

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
  - 第 231-235 行只校验 `onLux/offLux` 存在且在 `UInt16` 范围内。
  - 第 253 行将 `offLux/onLux` 转成 `UInt16` 传入 SDK。

如果用户输入或测量得到 `onLux < offLux`，SDK 执行 `ambientLightOnLux - ambientLightOffLux` 时会发生 `UInt16` 下溢，Swift 运行时触发 `SIGTRAP`。

另外，SDK 的拐点搜索中存在 `baseLux + threshold` 这类 `UInt16` 加法。极端高 lux 时也存在溢出风险，但本次 Bugly 栈落在 `setCalibrateRate()`，主因应优先按输入差值下溢处理。

### 当前是否已修复

当前工作区未完全修复 Bug 2。

证据：

- SDK 仍直接执行无保护的 `UInt16` 减法。
- App 校准入口未校验 `onLux > offLux` 或至少 `onLux >= offLux`。
- 当前 `LightSensorCalibrationViewController.swift` 有未提交改动，但改动内容是校准后恢复自动控制，与该 `SIGTRAP` 下溢无关。

### 修复原则

修复需要同时放在 App 入口和 SDK 内部：

- App 入口负责用户体验：输入不合法时提前提示，不启动校准。
- SDK 负责安全边界：即使调用方传入异常值，也不应因为 `UInt16` 算术崩溃。

只修 App 不够稳，因为 SDK 是共享依赖，未来其他调用方仍可能传入异常值；只修 SDK 则用户会等到校准中途才失败，体验较差。

## Bug 2 修复计划

### Task 1：补 App 入口校验

文件：

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`

步骤：

- 在 `calibrationBtnAction()` 中读取 `onLux/offLux` 后，增加开灯照度与关灯照度关系校验。
- 建议规则：`onLux > offLux` 才允许开始校准。
- 不满足时展示现有风格的失败提示，优先复用 `showCalibrationFailed(message:)` 或已有本地化文案。
- 如果没有合适本地化文案，先复用现有校准失败/检查失败文案，避免本次扩大本地化和多 target 资源改动。

验收：

- `onLux < offLux`：不进入 SDK，不崩溃，UI 给出提示。
- `onLux == offLux`：不进入 SDK，按无有效光照差处理。
- `onLux > offLux`：继续原有校准流程。

### Task 2：补 SDK 内部安全边界

文件：

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift`

步骤：

- 在 `setCalibrateRate()` 计算倍率前校验：
  - `ambientLightOnLux > ambientLightOffLux`。
  - `lightOnLux >= lightOffLux`。
- 不满足时设置合适的 `CalibrateError` 并走 `calibrateFailed()`，不要继续做无符号减法。
- 使用 `Int` 或 `Double` 进行差值计算，再 clamp 到 `UInt16`，避免所有中间态无符号下溢。

验收：

- SDK 即使收到 `ambientLightOnLux < ambientLightOffLux`，也只回调失败，不触发 `SIGTRAP`。
- SDK 收到 `lightOnLux < lightOffLux` 时回调拐点错误，不崩溃。
- 正常输入下倍率结果保持原逻辑。

### Task 3：补拐点搜索中的 UInt16 溢出防御

文件：

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift`

步骤：

- 将 `baseLux + threshold` 这类判断改为安全比较。
- 避免在 `UInt16` 上直接做可能溢出的加法。

验收：

- `baseLux` 接近 `UInt16.max` 时不会因为加法溢出崩溃。
- 正常 lux 值下拐点搜索行为不变。

### Task 4：验证

推荐验证命令：

- App 主工程：
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- SDK：
  - 在本地 SDK 仓库运行可用的 Swift 构建或相关测试。

手动回归：

- 校准页输入 `onLux < offLux`。
- 校准页输入 `onLux == offLux`。
- 校准页输入正常 `onLux > offLux`。
- 传感器离线、无响应、环境光不稳定等原有失败路径仍能正常弹出提示。

## 总结

- Bug 1：当前工作区已修复，核心是 `ScenesViewController` 使用快照并在数量变化时改走全量刷新。
- Bug 2：当前未完全修复，主因是 SDK `UInt16` 差值下溢；需要 App 入口校验加 SDK 内部防御两层处理。
