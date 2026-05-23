# Scene CCT Sync State 设计

## 背景

前一轮修复已经让场景同步下发和 Sync device(s) 页面成功判定按设备有效能力处理 CCT：

- 支持 CCT 的设备按自身 `effectiveCctRange` 夹紧目标色温。
- 配置为 `Single White (DIM)` 或不支持有效 CCT 的设备跳过色温项，只同步亮度、开关并保存场景。
- Sync device(s) 页面不再因为设备保存的 CCT 与组场景 CCT 不同而显示 Failure。

当前又发现一个独立问题：设备 A 和 B 原始都支持 CCT，但 A 在 Device Parameter Settings 中配置为 `Single White (DIM)`，B 配置为 `Tunable White (CCT)`。当 B 已在 Group 1 且已配置场景 S1，再把 A 加入 Group 1 后：

- 添加组成员流程会要求同步 S1。
- S1 同步后，Sync device(s) 页面可能显示成功。
- 但 Group 1 和 S1 仍提示需要同步。
- 删除 S1 后，这两个同步异常消失。
- 新建场景并把 Group 1 加入目标设备后，SAVE 可以成功，但组和场景仍提示需要同步，且除非删除场景，否则状态无法消失。

## 根因

工程内存在两套场景同步判断：

1. Sync device(s) 页面任务成功判定和 `Group.getNeedSyncDataNodes(scene:)` 已改为使用设备级比较。
2. `Node.getNodeSyncSceneDatas(group:scene:)` 仍然直接比较设备缓存的 `SceneExecuteData` 和组上的 `SceneExecuteData`。

`Scene.needSyncGroups`、`Scene.needSync`、`Group.needSync`、`Node.needSyncGroupData` 等红点或同步状态会通过 `Node.getSyncData(...)` 间接调用 `Node.getNodeSyncSceneDatas(...)`。因此即使实际同步已经按设备有效能力成功，列表状态仍可能使用旧逻辑误判。

典型误判：

- `Single White (DIM)` 设备 A：A 的场景只需要亮度和开关一致，不应比较 CCT；旧逻辑仍比较完整对象。
- CCT range 不同的设备：组场景可能是 `6500K`，设备 B 的有效上限可能是 `5000K`；B 实际保存 `5000K` 是正确结果，旧逻辑仍拿它和组场景 `6500K` 直接比较。

## 目标

所有“场景是否需要同步”的判断必须与“同步下发”和“同步成功判定”使用同一套设备级目标语义。

对每个设备：

- 如果 `node.effectiveSupportCct == true`，设备目标 CCT 为组场景 CCT 按该设备有效范围夹紧后的值。
- 如果 `node.effectiveSupportCct == false`，设备不参与 CCT 比较，也不因为 CCT 不同被判定为需要同步。
- 亮度、开关、场景号和状态仍需正常比较。

## 设计

采用方案 A：统一复用 `SceneExecuteData.isSynced(with:for:)`。

### 同步状态判断

`Node.getNodeSyncSceneDatas(group:scene:)` 在判断设备已有场景是否与组场景一致时，不再直接比较完整 `SceneExecuteData`。它应调用统一的设备级比较入口。

效果：

- `Scene.needSyncGroups` 与 Sync device(s) 页面保持一致。
- `Group.needSync` 与实际设备级同步目标保持一致。
- `Node.needSyncGroupData` 不再因为无效 CCT 字段误报。
- 添加组成员、重新同步场景、创建或修改场景后的红点状态都使用同一判断标准。

### 添加组成员时的场景同步

把 A 添加到 Group 1 时，A 仍需要同步 S1，但同步内容按 A 的有效能力执行：

- A 为 `Single White (DIM)`：同步亮度、开关并保存 S1；跳过 CCT 下发和 CCT 比较。
- B 为 `Tunable White (CCT)`：同步亮度、开关和按 B 有效范围夹紧后的 CCT。

同步完成后，A 不应因为缺少或不同的 CCT 被再次判定为需要同步。

### 设备 CCT range 差异

同组设备允许保存不同的实际 CCT 值：

- 组场景保存用户选择的目标值。
- 每个设备保存自身实际可达到的目标值。
- 后续同步状态判断按设备目标比较，而不是要求所有设备的缓存值等于组场景原始 CCT。

因此，设备 CCT range 不同不会导致组或场景长期显示需要同步。

### 一致性检查

如果工程内还有其他场景同步成功判定直接使用完整对象比较，也应改为同一设备级比较入口，避免其他同步入口出现同类误报。

## 非目标

- 不改变场景 Settings UI 的 CCT 可选范围策略。
- 不把组场景 CCT 改写为所有设备范围的交集。
- 不把 `Single White (DIM)` 设备从组场景同步中排除；它仍需要保存亮度和开关对应的场景。
- 不修改 Mesh Composition Data 或底层 SDK 能力识别。
- 不迁移历史场景数据；旧数据在同步、比较和下发时按当前有效能力解释。

## 验证计划

### 场景 1：Single White 与 Tunable White 混组

前置条件：

- A 原始支持 CCT，但 Change Control Page 配置为 `Single White (DIM)`。
- B 原始支持 CCT，Change Control Page 配置为 `Tunable White (CCT)`。
- B 已加入 Group 1，Group 1 已配置场景 S1。

验证步骤：

1. 将 A 加入 Group 1。
2. 在 Sync device(s) 页面同步 Group 1 和 S1。
3. 检查 A 同步成功。
4. 检查 Group 1 不再提示需要同步。
5. 检查 S1 不再提示需要同步。

预期：

- A 保存 S1 的亮度和开关目标。
- A 不因为 CCT 字段不同而持续需要同步。
- 删除 S1 不再是消除同步状态的唯一办法。

### 场景 2：同组设备 CCT range 不同

前置条件：

- A 有效 CCT range 为 `2700K...6500K`。
- B 有效 CCT range 为 `2700K...5000K`。
- Group 1 场景 S1 目标 CCT 为 `6500K`。

预期：

- A 的设备场景目标为 `6500K`。
- B 的设备场景目标为 `5000K`。
- A、B 都同步成功。
- Group 1 和 S1 不因为 A、B 实际保存 CCT 不同而继续提示需要同步。

### 回归

- 删除场景流程不变，仍按设备是否存在该场景判断是否需要删除。
- 不支持 Scene Setup Model 的设备不参与场景同步。
- Sync device(s) 页面里的场景任务成功判定与列表同步状态一致。

