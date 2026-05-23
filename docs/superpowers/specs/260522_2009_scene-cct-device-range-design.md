# 场景同步按设备色温范围夹紧设计

## 背景

场景中同一个组可能包含不同色温能力的设备。例如：

- A 设备支持 `2700K...6500K`
- B 设备支持 `2700K...5000K`

用户在场景 Settings 中将组场景色温设置为 `6500K` 并 SAVE 后，进入 Sync device(s) 页面，B 设备持续显示 Failure。

期望行为是：组/场景层面保留用户选择的 `6500K`，但同步到每个设备时按该设备实际支持范围保存。上述例子中，A 保存 `6500K`，B 保存 `5000K`。

## 已确认原因

当前代码已有部分按设备夹紧逻辑：

- `Scene.getSyncMessageHandles(node:data:)` 发送 `LightCTLSet` 前使用 `node.clampEffectiveCct(...)`。
- `Node.updateData(message:isSuccess:)` 处理 `SceneStore` 后，也会把设备场景缓存写成 `clampEffectiveCct(cct)`。

因此 B 设备收到和保存的实际目标值会是 `5000K`。持续 Failure 的根因更可能在比较逻辑：

- `Group.getNeedSyncDataNodes(scene:)` 直接比较设备缓存的 `nodeSceneData` 与组上的 `sceneData`。
- `DeviceOperationType.isSuccessful` 中 `.configuration(... .scene(...))` 也直接比较 `nodeScene == sceneData`。

当组场景值为 `6500K`、B 设备保存值为 `5000K` 时，直接比较永远不相等，导致同步成功后仍被判定为失败或仍需同步。

## 设计目标

- 保留组场景数据表达的用户意图，不因为组内某个设备能力较低而把组值降到 `5000K`。
- 对每个设备生成设备级目标场景数据，色温按设备实际 `effectiveCctRange` 夹紧。
- 同步发送、同步成功判定、再次进入同步页时的待同步判断使用同一套设备级目标数据。
- 不改变不支持色温设备的现有 lightness/onoff 行为。

## 已确认方案

增加一个统一的设备级场景目标计算入口，例如在 `SceneExecuteData` 或相邻扩展中提供：

- 输入：组场景 `SceneExecuteData`、目标 `Node`。
- 输出：用于该设备的 `SceneExecuteData`。
- 行为：
  - `sceneNumber`、`isOn`、`lightness`、`state` 沿用组场景数据。
  - 如果 `node.effectiveSupportCct == true`，`cct = node.clampEffectiveCct(groupSceneData.cct)`。
  - 如果设备不支持 CCT，同步消息直接跳过色温项，只设置亮度或开关并保存场景；同步成功判定也不应让 CCT 字段参与比较。

实际落点：

- `Scene.getSyncMessageHandles(node:data:)`
  - 继续按设备夹紧发送，最好复用同一个设备级目标数据，避免发送值与判定值分叉。
- `Group.getNeedSyncDataNodes(scene:)`
  - 比较设备缓存与 `sceneData.deviceTarget(for: node)`，而不是直接比较组 `sceneData`。
- `DeviceOperationType.isSuccessful`
  - `.configuration(node, .scene(sceneId, sceneData))` 中比较设备缓存与 `sceneData.deviceTarget(for: node)`。

## 数据流

1. 用户在场景 Settings 中为组选择 `6500K`。
2. 组场景数据保存为 `6500K`。
3. Sync device(s) 为组内每个设备计算设备级目标：
   - A：`6500K`
   - B：`5000K`
   - 不支持 CCT 的设备：跳过色温项，只同步亮度或开关并保存场景。
4. 同步发送时使用设备级目标。
5. 设备 SceneStore 成功后，本地设备缓存写入设备级目标。
6. 成功判定与后续待同步判定都使用设备级目标比较，因此 B 不会因为 `5000K != 6500K` 被反复判定失败。

## 影响范围

- 场景同步：
  - `SunSmart/Common/Data/Node+MessageHandles.swift`
  - `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- 可能受益的相关流程：
  - 新建场景后同步
  - 场景 Settings 修改后同步
  - Sync device(s) 页面重试/重新同步
  - 场景被日程绑定时的场景同步步骤

## 非目标

- 不改变场景 Settings UI 的可选范围策略；混合设备组仍可选择组内 CCT 设备范围并集。
- 不把组场景值保存为所有设备色温范围交集。
- 不修改 SDK 的设备能力读取逻辑。
- 不调整设备参数页的 absolute CCT range 配置行为。
- 不新增用户提示或 Warning 状态。

## 验证计划

- 静态检查：
  - 确认场景同步发送值、成功判定值、待同步比较值来自同一设备级目标。
- 构造数据验证：
  - 组场景 `6500K`，A `2700K...6500K`，B `2700K...5000K`。
  - A 同步后设备场景缓存为 `6500K`。
  - B 同步后设备场景缓存为 `5000K`。
  - A、B 都被判定同步成功。
  - 再次进入 Sync device(s) 时不再要求 B 继续同步。
- 回归检查：
  - 单一范围组行为不变。
  - 不支持 CCT 的调光灯跳过色温项，仍只同步亮度或开关，并可正常完成场景保存与成功判定。
  - 删除场景流程不受影响。
