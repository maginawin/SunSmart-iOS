# Light OTA 后 Transition Time 未恢复问题分析与方案

## 1. 结论

测试反馈在当前源码下属实，且能够定位到 App 的设备恢复链路缺口。

当 BLE OTA 前后 Composition Hash 不一致时，App 会提示设备需要重置，并在倒计时结束后自动进入指定设备恢复流程；用户点击 Restore Now 也进入同一流程。该流程会重新配网并恢复旧 Node 的配置。

当前实现能够恢复多种旧参数，但 Transition Time 同时缺少以下三个环节：

1. 旧 Node 的 `defaultTransitionTime` 没有写入新 Node 的 `NodeRestoreData`；
2. 全量恢复差异计算没有把 `defaultTransitionTime` 生成 `DeviceParameterType.defaultTransitionTime`；
3. `needSync` 没有判断 Transition Time 是否仍与恢复目标不一致。

因此，即使升级前 App 本地缓存和云端数据里保存了 3 秒，恢复流程也不会发送 `Generic Default Transition Time Set` 把 3 秒写回新设备；若新固件重置后的默认值是 1 秒，最终页面读取到的就是 1 秒。与此同时，App 还可能把该设备判定为恢复成功。

该结论是源码静态证据确认的 App 缺陷。当前没有本次设备的 Mesh 收发日志，因此尚未独立证明固件 2.0.8 在重置时具体如何处理每一种属性；但“Transition Time 由 3 秒变为 1 秒、其他参数保持旧值”的现象与当前 App 实现完全一致。

## 2. 现象与源码链路

### 2.1 App 确实存在自动重新添加

- `BleFirmwareUpdateViewController` 在 OTA 完成后比较旧 `compositionHash` 与目标版本 Hash；不一致时将旧 Node 加入 `restoreNodes`。
- OTA 批次结束且 `restoreNodes` 非空时，页面展示自动恢复提示。
- 提示包含 60 秒倒计时；倒计时结束后调用自动恢复。
- 自动恢复和 Restore Now 都创建 `DeviceRestoreViewController(... restoreMode: .specified(nodes: restoreNodes))`。

关键位置：

- `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift:803-840`
- `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift:1217-1244`
- `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift:1311-1319`

### 2.2 旧 Node 会被用于生成新 Node 的恢复数据

重新配网完成后，`DeviceRestoreViewController` 找到对应旧 Node，并调用：

- `node.updateResoreData(oldNode: oldNode, resoreGroup: addToGroup)`

随后对新 Node 执行 `getSyncData(type: .all)`，再把生成的同步项转换成 Mesh 消息加入恢复队列。

关键位置：

- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:2204-2238`
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:2241-2306`
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:2338-2344`

### 2.3 Transition Time 的基础能力是完整的

当前 SDK 和 App 已具备下列能力：

- `NodeRestoreData` 已定义、编码和解码 `defaultTransitionTime`；
- Device Parameter Settings 能发送 `GenericDefaultTransitionTimeSet`；
- SET 使用 SIG Mesh opcode `0x820E`，参数为一字节 Transition Time；
- 响应为 `GenericDefaultTransitionTimeStatus`，opcode `0x8210`；
- SDK 收到 Status 后更新 `node.defaultTransitionTime` 并持久化；
- 同步任务以 Node 当前值与目标值的 `rawValue` 相等作为业务成功条件；
- App 的 Export/Import 已包含 `defaultTransitionTime`。

3 秒通过当前 `TransitionTime(3)` 编码为 `0x1E`，1 秒编码为 `0x0A`。因此真实验收应核对原始值，而不只看 UI 文案。

关键位置：

- 本地 SDK `Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift:1588-1675`
- 本地 SDK `Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/Generic/GenericDefaultTransitionTimeSet.swift:33-57`
- 本地 SDK `Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/Generic/GenericDefaultTransitionTimeStatus.swift:33-56`
- 本地 SDK `Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift:531-534`
- `SunSmart/Common/Data/Node+SyncData.swift:269-290`
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:1033-1051`
- `SunSmart/Common/Data/ExportData.swift:280-281,717-718`
- `SunSmart/Common/Data/ImportData.swift:1235-1236,1865-1866`

## 3. 根因

### 3.1 第一处断点：恢复快照漏存 Transition Time

`updateResoreData` 创建 `NodeRestoreData` 时只传入 Group、PWM 和 Photosensor Exception，之后补充 Rated Power 和 Motion Sensitivity Range，没有把 `oldNode.defaultTransitionTime` 写入 `restoreData.defaultTransitionTime`。

关键位置：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2619-2638`

SDK 虽然早已提供该字段，但 App 没有使用，因此恢复目标一开始就是空的。

### 3.2 第二处断点：全量差异计算漏生成 Transition Time 同步项

`getSyncData(type: .all)` 当前生成 PWM、Rated Power、Motion Sensitivity Range 和 Photosensor Exception 的恢复项，但没有比较：

- 新 Node 当前 `defaultTransitionTime`；
- `restoreData.defaultTransitionTime` 恢复目标。

所以即使只补上快照字段，恢复队列仍不会产生 `GenericDefaultTransitionTimeSet`。

关键位置：

- `SunSmart/Common/Data/Node+SyncData.swift:596-639`

另外，现有参数聚合被放在 `sunricherVendorModel != nil` 条件中，而 Transition Time 使用 SIG Generic Default Transition Time Model。修复时不能错误地让 SIG 参数依赖 Sunricher Vendor Model。

### 3.3 第三处断点：恢复结果判断看不到该差异

`getNeedSync()` 会检查 PWM、Rated Power、Motion Sensitivity Range 和 Photosensor Exception，但没有检查 Transition Time。

这会造成两个后果：

1. 自动恢复完成后，即使设备仍是 1 秒，也可能被标记为成功；
2. OTA 页面提供的后续 Sync 入口不会把这个设备选为待同步设备，因此用户无法通过现有恢复重试补回 3 秒。

关键位置：

- `SunSmart/Common/Data/Node+SyncData.swift:719-780`
- `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift:1327-1342`
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:2450-2473`
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:2780-2834`

### 3.4 为什么其他属性正常

当前源码不能单独证明每个“正常属性”是固件升级后自行保留，还是 App 重写恢复；两种情况都可能存在。但 App 明确为 PWM、Rated Power、Motion Sensitivity Range 和 Photosensor Exception 建立了恢复快照和 SET 任务，而 Transition Time 没有，因此只有它丢失并不矛盾。

本问题不是 Device Parameter Settings 保存功能或云端 Export/Import 的首要缺陷：正常设置时，SET/Status、本地持久化、Export/Import 都已存在；断点发生在 OTA 后指定设备恢复的数据迁移与差异同步阶段。

## 4. 修复方案比较

### 方案 A：补齐通用恢复数据链路（推荐）

在既有恢复框架内补齐 Transition Time：

1. 创建 `NodeRestoreData` 时保存旧 Node 的 Transition Time；
2. `.all` 差异计算把 Transition Time 纳入设备参数聚合；
3. 仅当新 Node 存在 Generic Default Transition Time Model、旧值有效且当前值不一致时生成同步项；
4. `getNeedSync()` 使用同一目标与能力条件判断未完成状态；
5. 继续复用现有 `DeviceParameterType` 的 SET、Status 缓存更新、成功判定和 Sync 重试。

优点：修复自动恢复、Restore Now、失败提示和后续 Sync 的完整闭环；不增加特殊 OTA 分支；不需要修改协议或 SDK 数据结构。

风险：需要确保 SIG 参数不受 Sunricher Vendor Model 条件限制，并避免生成两个分散的 `deviceParameterTypes` 同步块。

### 方案 B：在 DeviceRestoreViewController 中直接追加 SET

从旧 Node 读取 Transition Time，并在恢复 append messages 阶段直接追加 `GenericDefaultTransitionTimeSet`。

优点：表面改动较小。

缺点：绕过通用恢复差异计算；`needSync`、失败提示和手动重试仍然不完整；容易让恢复页面报告成功但实际 SET 失败。不推荐。

### 方案 C：重构为通用 Device Parameter 恢复描述表

把所有参数的快照、能力、差异判断、消息和成功验证统一为描述表。

优点：长期可减少新增参数时漏接恢复链路的概率。

缺点：当前问题只涉及一个遗漏字段，重构范围会扩展到多种参数和现有恢复行为，回归风险与验证成本过高。本次不建议采用。

## 5. 推荐设计

采用方案 A，并保持改动限定在 App 通用恢复层。

### 5.1 数据快照

在 `Node.updateResoreData(oldNode:resoreGroup:)` 中把 `oldNode.defaultTransitionTime` 原样保存到 `NodeRestoreData`。不使用 UI 默认值 1 秒，也不对秒数重新编码，保留原 `rawValue`。

### 5.2 差异计算

调整 `.all` 的设备参数聚合方式：

- Vendor 参数继续只在 Sunricher Vendor Model 存在时生成；
- Transition Time 独立按 Generic Default Transition Time Model 能力生成；
- 所有需要恢复的参数最终合并为一个 `deviceParameterTypes` 同步项；
- 目标为空、Model 不存在或当前值已等于目标时不发送 SET。

### 5.3 状态真值

`getNeedSync()` 添加与差异计算一致的 Transition Time 判断。SET 收到 `0x8210` 后，SDK 已会保存设备返回值；只有返回值与目标 `rawValue` 一致时才算恢复成功。

超时、无响应或设备返回 1 秒时，设备必须保留 Sync Failed/Needs Sync 状态，允许用户通过现有 Sync 入口重试，不能静默判定成功。

### 5.4 SDK 与 target 范围

- 当前本地 SDK 已具备 `NodeRestoreData.defaultTransitionTime`、编解码、SET/Status 和 Node 持久化能力，预计无需修改 SDK 源码。
- 当前工程中的 `NordicSigMeshSDK` 已是本地路径引用，四个 App target 均引用同一产品。
- App 公共代码修改后需验证 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 scheme。
- 不修改 UI、本地化、资源、target 配置、依赖版本或云端协议。

## 6. 实施范围

预计修改：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 补齐旧 Node → `NodeRestoreData` 的 Transition Time 快照。
- `SunSmart/Common/Data/Node+SyncData.swift`
  - 补齐 `.all` 恢复差异项；
  - 补齐 `getNeedSync()` 判断；
  - 确保 SIG 参数不依赖 Vendor Model。
- `scripts/check_device_restore_transition_time.sh`
  - 新增聚焦静态契约，锁定快照、差异计算、SET、成功判定和未同步状态。

预计只验证、不修改：

- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`
- `SunSmart/Common/Data/Node+MessageHandles.swift`
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- 本地 `NordicSigMeshSDK` 的 `NodeRestoreData`、Generic Default Transition Time 消息与 Node Status 持久化。

## 7. 验证计划

### 7.1 静态与逻辑契约

新增聚焦脚本验证：

1. `updateResoreData` 保存旧 Node 的 `defaultTransitionTime`；
2. `.all` 在目标为 3 秒且当前为空或 1 秒时生成 Transition Time 同步项；
3. 目标为空、Model 不存在或当前已是 3 秒时不生成该项；
4. Transition Time 的差异计算不依赖 Sunricher Vendor Model；
5. `getNeedSync()` 在 1 秒与 3 秒不一致时返回需要同步；
6. 同步消息仍为 acknowledged `GenericDefaultTransitionTimeSet`；
7. 成功条件仍严格比较返回值与目标 `rawValue`。

### 7.2 构建验证

按项目规则直接使用 generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO` 构建：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

同时执行：

- 聚焦契约脚本；
- `git diff --check`。

构建成功只能证明静态集成，不代表 BLE、Mesh、固件和真实设备恢复已验收。

### 7.3 真机与协议验收

使用同一 Light 设备复测 1.3.27 → 2.0.8：

1. OTA 前在 Device Parameter Settings 设置 Transition Time 为 3 秒；
2. 读取设备，确认 `0x8210` Status 参数为 `0x1E`；
3. 同时记录至少一种其他参数作为对照；
4. 执行 OTA，并允许 App 自动恢复；
5. 新设备重新配网后，确认 App 发送 `0x820E 1E`；
6. 确认设备回复 `0x8210 1E`；
7. 恢复结束后再次 Read，确认仍为 3 秒；
8. 关闭并重启 App，再次进入 Device Parameter Settings，确认显示 3 秒；
9. 模拟 SET 超时或无响应，确认 App 显示恢复未完成，并能通过 Sync 重试；
10. 分别覆盖 60 秒自动恢复和 Restore Now 手动恢复。

补充回归：

- Transition Time 为 0 秒、1 秒、3 秒和 10 秒；
- 设备没有 Generic Default Transition Time Model；
- 旧 Node 没有缓存 Transition Time；
- 新旧值已相同；
- 单设备与多设备 OTA；
- 设备在 Group 内和不在 Group 内；
- App 四个品牌 target 的基础恢复入口。

## 8. 非本次范围

- 不修改固件 1.3.27 或 2.0.8；
- 不改变 Composition Hash 判定和“需要重置”的产品流程；
- 不新增云端字段或服务器迁移；
- 不把 1 秒硬编码为恢复值；
- 不顺手重构全部 Device Parameter 框架；
- 不把构建成功或 SET ACK 单独当作完整业务恢复成功。

## 9. 待确认

2026-08-10 已确认采用方案 A，并按 Inline Execution 实施。

## 10. 实施结果（2026-08-10）

### 10.1 已完成

- 在旧 Node 生成 `NodeRestoreData` 时保存 `defaultTransitionTime`，恢复目标来自 OTA 前 App 已缓存的设备值，不使用新固件默认值。
- 新增纯值策略，统一判断恢复目标、设备当前值和有效能力；目标为空、设备不支持或当前值已经一致时不安排写回。
- `.all` 恢复规划在策略返回目标值时追加 Default Transition Time 参数，不受 Sunricher Vendor Model 条件限制。
- `getNeedSync()` 复用同一策略；超时、无响应或返回值不一致时，后续仍能识别为需要同步。
- 沿用现有 acknowledged `GenericDefaultTransitionTimeSet`、Status 更新与 `rawValue` 严格成功判断，未修改 SIG payload 或 SDK。
- 新策略文件已加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 App target。

### 10.2 验证结果

- 聚焦策略测试：7 个用例通过，覆盖 mismatch、current 为空、equal、target 为空、不支持和 raw value 为 0 等边界。
- 恢复链路接线契约：通过，覆盖旧值快照、两处共享策略、参数生成、acknowledged SET 与严格成功判断。
- `git diff --check`：通过。
- generic iPhoneOS Debug 构建：SunSmart、Archipelago、SLG Sync Plus、SylSmart 均 `BUILD SUCCEEDED`。
- NordicSigMeshSDK 工作区保持无改动；未修改 Pods、资源、本地化、UI 或依赖版本。

### 10.3 验证边界

上述结果证明 App 侧恢复链路和四 target 静态集成成立，不代表真实 BLE、Mesh 或固件行为已经验收。仍需使用同一 Light 设备完成 1.3.27 → 2.0.8 真机复测，重点确认恢复阶段发送 `0x820E 1E`、收到 `0x8210 1E`，并在 App 重启后仍显示 3 秒。
