# EFC SAVE 命令顺序分析

## 背景

- 问题设备：EFC，PID `0x2131`。
- 操作路径：EFC Edit 页面，在 `Associate With Group(s)` 中新增占用感应组后点击 `SAVE`。
- 预期：同步成功后，关联灯组自动回到占用感应 Profile 状态。
- 实际：同步成功后未回到占用感应 Profile 状态。
- 已知恢复方式：模拟 group 页面的 `AUTO` 按钮，发送 Auto 控制后可恢复。

## SAVE 入口

`LinkedEmerFireEditVC.saveAction()` 的流程是：

1. 校验页面输入。
2. `viewModel.save()` 保存本地 EFC 配置。
3. 如果绑定了真实设备，并且 `lastSavedRequiresSync == true`，进入 `SyncDevicesViewController(type: .emergencyFire(...))`。
4. 同步页通过 `EmergencyFireControllerSyncPlanner.makeItems()` 生成任务。
5. 同步页逐个执行任务的 `messageHandles`。

## 任务生成顺序

`EmergencyFireControllerSyncPlanner.makeItems()` 的顺序固定为：

1. 确保 EFC 内部 publish group 存在。
   - 这是本地 Mesh group 创建/复用，不是 Mesh 发送命令。
2. 生成 EFC 控制器自身任务。
3. 生成当前激活模式关联灯组任务。
4. 生成 pending cleanup 任务。

同步页对 `.emergencyFire` 设置了 `prefersDevicesBeforeGroups = true`，因此控制器自身任务会先执行，然后才执行灯组关联任务。

## 实际 Mesh 命令顺序

### 1. EFC 控制器自身任务

这些任务作用在 EFC 绑定节点上，按以下顺序生成和执行：

1. `Scene Publication`
   - 命令：`ConfigModelPublicationSet`
   - 目标模型：EFC 节点的 `sceneClientModel`
   - publication 地址：EFC 内部 publish group
   - 条件：当前 publication 不是内部 publish group 时才发送。

2. `LC Publication`
   - 命令：`ConfigModelPublicationSet`
   - 目标模型：EFC 节点的 `lightLCClientModel`
   - publication 地址：EFC 内部 publish group
   - 条件：当前 publication 不是内部 publish group 时才发送。

3. `Mode`
   - 命令：`SunricherVendorSet(function: .emergencyMode(...))`
   - 目标模型：EFC 节点的 `sunricherVendorModel`
   - 条件：首次完整同步，或 `workMode` 变化时发送。

4. `Resend`
   - 命令：`SunricherVendorSet(function: .emergencyResendParameters(...))`
   - 目标模型：EFC 节点的 `sunricherVendorModel`
   - 条件：首次完整同步，或 resend 参数变化时发送。

5. `Restore Delay`
   - 命令：`SunricherVendorSet(function: .emergencyRestoreDelay(seconds: ...))`
   - 目标模型：EFC 节点的 `sunricherVendorModel`
   - 条件：首次完整同步，或 restore delay 变化时发送。

### 2. 当前激活模式的关联灯组任务

对当前激活模式的每个 `associateGroupAddresses`，按 group 地址数组顺序处理。每个 group 内按 `group.nodes` 顺序处理节点。每个节点的任务顺序是：

1. `Scene Group`
   - 命令：`ConfigModelSubscriptionAdd`
   - 目标模型：灯节点的 `sceneModel`
   - 订阅地址：EFC 内部 publish group
   - 条件：`sceneModel` 尚未订阅内部 publish group 时才发送。

2. `Trigger Scene`
   - 命令 1：`LightLightnessSet(lightness: triggerBrightness, transitionTime: .immediate, delay: 0)`
   - 命令 2：`SceneStore(triggerScene)`
   - 目标模型：灯节点的 `lightnessModel` 和 `sceneSetupModel`
   - 场景号：
     - Power Loss：`0xFF20`
     - Fire Alarm：`0xFF22`
   - 注意：`LightLightnessSet` 会改变灯当前亮度，随后把这个亮度存入 EFC 保留触发场景。

3. `LC Group`
   - 命令：`ConfigModelSubscriptionAdd`
   - 目标模型：灯节点的 `lightLCModel`
   - 订阅地址：EFC 内部 publish group
   - 条件：`lightLCModel` 尚未订阅内部 publish group 时才发送。

### 3. Pending cleanup 任务

对 pending 取消关联的组执行清理：

1. `LC Cleanup`
   - 命令 1：`ConfigModelSubscriptionDelete`，删除灯节点 `sceneModel` 对 EFC 内部 publish group 的订阅。
   - 命令 2：`ConfigModelSubscriptionDelete`，删除灯节点 `lightLCModel` 对 EFC 内部 publish group 的订阅。
   - 只有对应模型确实已订阅时才发送。
   - 如果没有可发送 Mesh 命令，可能生成本地 cleanup task，用于清理 pending 标记。

## 与 group 页 Auto 的差异

group 页 Auto 按钮发送：

`LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)` 到用户可见 group 地址。

EFC 监控页 Stop/恢复链路发送：

`LightLCLightOnOffSetUnacknowledged(true)` 到 EFC 内部 publish group 地址。

当前 Edit 页 SAVE 同步链路没有发送上述 Auto/LC On 命令。SAVE 只完成 EFC 控制器 publication、vendor 参数、灯节点订阅和保留触发场景写入。

## 初步结论

新增占用感应组后，SAVE 同步成功不等于恢复占用感应 Profile 运行状态。现有同步流程中 `Trigger Scene` 会先用 `LightLightnessSet` 改变灯当前亮度，再 `SceneStore` 保存 EFC 触发场景；流程结束后没有发送 group Auto 等价的 `LightLCLightOnOffSetUnacknowledged(true)`，因此设备可能停留在当前/手动状态，没有回到占用感应 Profile 状态。

后续修复应围绕“EFC SAVE 同步完成后，对新增或受影响的占用感应组补发等价 Auto/LC On 恢复命令”继续验证，而不是调整已有 publication/subscription 顺序。

## 修复后命令顺序

修复后，`EmergencyFireControllerSyncPlanner.makeItems()` 在当前激活模式关联任务之后追加 `Auto Restore` 任务。SAVE 同步顺序变为：

1. EFC 控制器自身任务：
   - `Scene Publication`
   - `LC Publication`
   - `Mode`
   - `Resend`
   - `Restore Delay`
2. 当前激活模式关联灯组任务：
   - 每个灯节点 `Scene Group`
   - 每个灯节点 `Trigger Scene`
   - 每个灯节点 `LC Group`
3. 当前激活模式 Auto restore：
   - 对每个当前激活关联 group 发送 `LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)` 到用户可见 group 地址。
   - 范围与 group 页面 Auto 入口一致，覆盖所有 group profile，不按 `occupancyType` 过滤。
4. Pending cleanup：
   - `LC Cleanup`

这样 `Trigger Scene` 写入保留场景时产生的当前亮度改变，会在流程末尾通过 group Auto 恢复到对应 Profile 的 Auto 状态。
