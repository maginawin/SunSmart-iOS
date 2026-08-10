# Default Transition Time 恢复评审问题修复设计

## 1. 目标

修复 Default Transition Time 恢复链路中的两个 P2 问题：

1. 旧缓存或导入数据中的 Unknown Transition Time 不得生成 `GenericDefaultTransitionTimeSet`，也不得使设备持续处于 Needs Sync；
2. OTA 恢复成功后必须消费并持久化清除 `restoreData.defaultTransitionTime`，避免后续把设备的合法新值错误回写为旧恢复值。

本设计是既有 Light OTA Transition Time 恢复实现的聚焦增量修复，不重做原恢复方案。

## 2. 已确认的根因

### 2.1 Unknown 恢复目标未被过滤

`DeviceRestoreDefaultTransitionTimePolicy.pendingTargetRawValue(...)` 当前只检查：

- 设备是否支持 Default Transition Time；
- 恢复目标是否存在；
- 当前值是否与恢复目标不同。

它没有检查恢复目标是否为 Known。`TransitionTime` 的低 6 位为 steps，`0x3F` 表示 Unknown，因此 `0x3F`、`0x7F`、`0xBF`、`0xFF` 都不能作为 SET 目标。

当前策略被 `.all` 同步规划和 `getNeedSync()` 共用，所以同一个缺口会同时造成非法 SET 和持续 Needs Sync。

### 2.2 成功恢复后未消费恢复目标

`SyncDevicesViewController` 会把完成的消息、`handle.isSuccessful` 和 Model 交给 `Node.updateData(...)`。该方法入口会阻止失败消息更新缓存，并已在 PWM、Photosensor Exception 等成功分支中清除相应恢复字段和调用 `save()`。

但它没有处理 `GenericDefaultTransitionTimeSet`。因此设备返回匹配 Status、同步任务判定成功后，`restoreData.defaultTransitionTime` 仍会被编码到 Node 数据库。App 重启或设备值随后变化时，该旧目标会再次参与同步规划。

评审标注的 `Node+SyncData.swift:641` 是 SET 生成位置；成功后的恢复目标清理应放在 `MeshNetwork+SunSmart.swift` 的 `Node.updateData(...)` 中。

## 3. 选定方案

采用方案 A：集中校验恢复目标，并在成功 SET 后有条件地消费恢复目标。

### 3.1 Known 校验

在 `DeviceRestoreDefaultTransitionTimePolicy` 内集中判断 raw value 的低 6 位：

- 低 6 位等于 `0x3F`：返回 `nil`；
- 其他值继续执行既有的能力、nil 和相等判断；
- `0x00` Immediate 必须保持有效；
- 不修改 SDK 的 `TransitionTime`、SET 消息或 Import 数据结构。

把校验放在共享策略中，可保证 `.all` 消息生成和 `getNeedSync()` 使用同一真值。Unknown 恢复字段可以继续存在于旧数据中，但不会发送、不会被判定为待同步，也不会影响后续设备值。

### 3.2 成功清理条件

在共享策略中增加一个纯判断，用于决定成功 SET 是否可以消费恢复目标：

- 恢复目标必须存在；
- 成功 SET 的目标 raw value 必须与恢复目标完全一致；
- 不一致或没有恢复目标时不得清理。

`Node.updateData(...)` 已通过入口的 `isSuccess` 守卫过滤失败消息，因此新增 `GenericDefaultTransitionTimeSet` 分支只处理成功消息。满足上述匹配条件时：

1. 将 `restoreData.defaultTransitionTime` 置空；
2. 调用 `save()`，将更新后的 `restoreData` 重新编码到 Node 数据库；
3. 保持其他恢复字段不变。

目标匹配约束用于避免其他控制入口发送不同 Transition Time 时，误清除仍未完成的 OTA 恢复目标。

## 4. 数据流与状态规则

### 4.1 合法目标

恢复目标为 3 秒 `0x1E`、设备当前值为 1 秒 `0x0A` 时：

1. 策略返回 `0x1E`；
2. `.all` 生成 acknowledged `GenericDefaultTransitionTimeSet`；
3. 设备返回匹配的 `GenericDefaultTransitionTimeStatus` 后，SDK 更新并保存 `node.defaultTransitionTime`；
4. `handle.isSuccessful` 为真，App 的 `Node.updateData(...)` 消费并保存清除恢复目标；
5. 后续 `getNeedSync()` 不再因该字段返回 true。

### 4.2 Unknown 目标

恢复目标低 6 位为 `0x3F` 时：

1. 策略返回 `nil`；
2. `.all` 不生成 Transition Time SET；
3. `getNeedSync()` 不把该字段判定为待同步；
4. 不主动迁移或删除旧数据库字段，避免扩大本次修复范围。

### 4.3 失败或不匹配

- SET 超时、无响应或 Status 不匹配：`handle.isSuccessful` 为假，恢复目标保留，允许现有重试和后续 Sync；
- 成功处理的 SET 目标与恢复目标不同：恢复目标保留，避免错误消费；
- 恢复目标为空：不保存无变化数据。

## 5. 文件范围

### 修改

- `SunSmart/Common/Data/DeviceRestoreDefaultTransitionTimePolicy.swift`
  - 过滤所有 Unknown raw value；
  - 增加成功 SET 与恢复目标匹配的纯判断。
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 在 `Node.updateData(...)` 中处理成功的 `GenericDefaultTransitionTimeSet`；
  - 匹配后清空字段并调用 `save()`。
- `scripts/tests/DeviceRestoreDefaultTransitionTimePolicyTests.swift`
  - 增加 Unknown 和成功消费判断的行为用例。
- `scripts/check_device_restore_transition_time.sh`
  - 更新聚焦接线检查，覆盖成功清理与持久化接线。
- 既有 Transition Time 分析/实施文档
  - 实施完成后补充评审修复结果与验证边界。

### 仅验证

- `SunSmart/Common/Data/Node+SyncData.swift`
  - 两处策略调用继续共享 Known 过滤结果；不重复增加判断。
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 继续以 `handle.isSuccessful` 调用 `Node.updateData(...)`。
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 继续使用 Status 更新后的 raw value 严格判断业务成功。
- 本地 `NordicSigMeshSDK`
  - 继续负责 Transition Time 编码、Status 更新、Node 属性和数据库持久化；不修改 SDK。

不修改 UI、本地化、资源、依赖版本、协议 payload 或其他 Device Parameter 行为。

## 6. 测试设计

### 6.1 策略 RED/GREEN 用例

在修改生产代码前，先加入以下失败用例：

- `0x3F`、`0x7F`、`0xBF`、`0xFF` 目标均返回 `nil`；
- `0x00` Immediate 继续返回 `0x00`；
- `0x1E` 与当前 `0x0A` 不同时继续返回 `0x1E`；
- 成功 SET 目标与恢复目标相同，允许消费；
- 成功 SET 目标不同，不允许消费；
- 恢复目标为空，不允许消费。

保留现有 unsupported、nil current、equal 和 nil target 用例。

### 6.2 接线与静态验证

聚焦检查应确认：

- `.all` 和 `getNeedSync()` 仍各调用一次共享策略；
- 仍使用 acknowledged `GenericDefaultTransitionTimeSet`；
- `Node.updateData(...)` 存在 Default Transition Time SET 成功分支；
- 清理前使用目标匹配判断；
- 清理后调用 `save()`；
- `git diff --check` 通过。

### 6.3 构建验证

按项目规则直接使用 generic iPhoneOS、关闭签名构建：

- `SunSmart`；
- `Archipelago`；
- `SLG Sync Plus`；
- `SylSmart`。

构建成功只证明源码和四 target 静态集成，不代表真实 Mesh 或硬件验收完成。

### 6.4 真机验收

使用同一设备验证：

1. OTA 前设置 3 秒并确认 Status raw value 为 `0x1E`；
2. OTA 重置恢复发送 `0x820E + 0x1E`；
3. 收到 `0x8210 + 0x1E` 后完成恢复；
4. 重启 App 后不再出现 Needs Sync；
5. 由其他控制器把设备改成其他合法值后，App 不再自动回写旧的 `0x1E`；
6. 注入 Unknown 旧恢复数据时，不发送 `0x820E`，也不持续显示 Needs Sync。

## 7. 验收标准

- 所有 Unknown raw value 不生成 SET，且不触发 Needs Sync；
- 合法 3 秒恢复路径行为保持不变；
- 只有成功且目标匹配的 SET 才清除恢复字段；
- 清理结果经 `save()` 持久化，App 重启后不会恢复旧目标；
- 失败路径保留恢复目标和现有重试能力；
- 四个 App target 完成 generic iPhoneOS 构建；
- 未引入 SDK、UI、国际化、资源或无关模块改动。

## 8. 非目标

- 不批量清洗历史 Import、Export 或数据库中的 Unknown 值；
- 不修改 `GenericDefaultTransitionTimeSet` 构造器；
- 不重构所有 Device Parameter 的恢复描述表；
- 不改变超时、重试次数或同步页面状态机；
- 不执行 Git commit、push 或 merge。

## 9. 实施状态（2026-08-10）

### 9.1 两个 P2 的对应结果

- P2 Unknown：已在共享 pending-target 策略中过滤全部四种分辨率的 Unknown raw value；`.all` 和 `getNeedSync()` 无需增加重复判断；
- P2 残留目标：已在 `Node.updateData(...)` 增加成功 SET 分支，仅当 SET raw value 与恢复目标一致时清空字段并调用 `save()`。

### 9.2 修改文件

- `SunSmart/Common/Data/DeviceRestoreDefaultTransitionTimePolicy.swift`；
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`；
- `scripts/tests/DeviceRestoreDefaultTransitionTimePolicyTests.swift`；
- `scripts/check_device_restore_transition_time.sh`。

`Node+SyncData.swift` 的两处共享策略调用、`SyncDevicesViewController.swift` 的成功传递和 `SyncDevicesCellModel.swift` 的 raw value 成功判断保持原接线。

### 9.3 自动验证

- 11 个 pending-target 行为用例通过；
- 3 个 cleanup 行为用例通过；
- 恢复链路 wiring contract 通过；
- `git diff --check` 通过；
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 generic iPhoneOS 构建均 exit 0。

### 9.4 验收边界

上述结果证明纯策略、App 接线、Swift 编译和四 target 静态集成。尚未完成真机、真实 BLE/Mesh、固件响应、App 重启持久化和其他控制器修改后的业务验收；第 6.4 节真机清单仍全部待执行。
