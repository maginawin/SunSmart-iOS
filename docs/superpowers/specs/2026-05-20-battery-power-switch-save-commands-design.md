# Battery Power Switch SAVE Commands Design

## 背景

本设计只覆盖 PID `0x2A01`、`0x2A02` 两种 Battery Power Switch。目标是让新增设备在 Add 阶段直接写入默认 switch configuration，并让后续 SAVE 只按真实变化发送命令，避免未变化 target group 被重复同步，也避免 group 命令早于 switch configuration 执行。

## 已确认需求

- 新增 PID `0x2A01` 时，默认使用 Scene Profile。
- 新增 PID `0x2A02` 时，默认使用 Brightness Profile。
- Add 阶段需要把默认 switch configuration 直接发送给遥控器。
- Add 阶段默认 switch configuration 全部成功后，switch 展示正常状态。
- Add 阶段默认 switch configuration 中间任一命令失败时，停止剩余 BPS configuration；设备添加仍算成功，但 switch 展示未同步。
- 后续 SAVE 时，如果 Profile 未变化，只管理 target groups。
- Scene Profile 的 scene 关联变化等同于 Profile 切换，需要重新下发 switch configuration。

## 当前代码差异

- `MeshNetworkManager.createDefaultSwitch(forBatteryPowerSwitch:)` 已按 PID 分配默认 profile，但创建后直接把 `syncState` 设为 `.pending`，`appliedConfigHash` 为空，因此新增后必然展示未同步。
- Classic 与 Professional Add 流程已有 `appendMessagesBack`，但当前未为 PID `0x2A01`、`0x2A02` 追加默认 BPS switch configuration。
- `PJEightKeySwitchData` 已用 desired/applied config hash 判断 Profile、enabled、link group、scene A-D 是否变化，基本覆盖 Profile 与 scene 关联变化。
- BPS target group 差异同步已有改动方向：不再使用 `includeExisting: true` 强制把未变化 group 放进任务。
- `SyncDevicesViewController` 当前执行顺序仍可能不符合需求：section 默认 groups before devices，remove section 又早于 configuration section；同时 `relevanceStepModels` 只处理依赖失败，不等待依赖成功。

## 方案选择

采用方案 A：把默认 switch configuration 接入 Add 的 append messages 阶段。

原因：

- Add 入网完成后设备仍处于当前连接上下文，最适合立即写入默认 BPS configuration。
- 设备添加成功与 switch configuration 成功可以拆开记账，符合“配置失败但设备添加成功”的业务要求。
- 改动范围集中在 Add 追加配置、BPS 状态持久化、BPS 同步顺序，不需要引入新的用户流程。

不采用方案 B：Add 成功后再跳转或后台复用 Sync 页面。它会打断 Add 流程，而且低功耗设备可能已经离开可配置窗口。

不采用方案 C：Add 只创建默认 profile，后续用户手动同步。这等同当前问题，不能满足需求。

## Add 阶段设计

Add 流程识别到节点是 PID `0x2A01` 或 `0x2A02` 后：

1. 创建默认 `PJEightKeySwitchData`。
2. 按 PID 写入默认 profile。
3. 确保 BPS link group 存在。
4. 计算 desired config hash。
5. 生成默认 own configuration 消息链：Reset Defaults、Key Config、Model Publication。
6. 将这批消息作为 BPS 专属 append messages 发送。

发送结果：

- 全部成功：保存 `syncState = .synced`，`appliedConfigHash = desiredConfigHash`，展示正常状态。
- 任一失败：停止剩余 BPS own configuration，保存为未同步状态，不更新 `appliedConfigHash`，设备仍进入 Add success list。

这里需要让 append message 阶段支持 BPS fail-fast。失败只停止本次 BPS own configuration，不触发设备 provisioning 失败。

## SAVE 阶段设计

SAVE 同步按明确业务顺序执行：

1. 如果 BPS own configuration 有变化，先执行 switch configuration。
2. 再执行新增 target group configuration。
3. 最后执行 remove target group。

具体场景：

- Brightness Profile 未变化，新增 group A：仅下发 group A configuration。
- Brightness Profile 未变化，删除 group A：仅下发 remove A group。
- Brightness Profile 未变化，新增 group A 且删除 group B：先新增 A，再删除 B。
- Brightness Profile 与 Scene Profile 互相切换：先下发 switch configuration，再按新增 group、删除 group 顺序处理。
- Scene Profile 更新 scene 关联：等同 Profile 切换。
- Profile 或 scene 有变化但 group 无变化：仅下发 switch configuration。

实现上，`.batteryPowerSwitch` 同步类型需要专用顺序：

- configuration section 中 BPS own configuration devices 优先。
- configuration groups 其次。
- remove groups 最后。
- BPS group task 依赖 own configuration 时，必须等待 own configuration 成功后才可执行；own configuration 失败时不继续执行后续 group add/remove。

## 状态与失败语义

- Add 阶段 BPS own configuration 失败，不把设备添加结果改为失败。
- SAVE 阶段 BPS own configuration 失败，不继续执行 group add/remove。
- group add/remove 失败只影响 target group 同步，不回滚已成功的 own configuration。
- own configuration 成功但 group 失败时，允许保存 applied config，并保留 group 差异供后续同步。

## 验证范围

- 新增 `0x2A01`，默认 Scene Profile switch configuration 成功后不显示未同步。
- 新增 `0x2A02`，默认 Brightness Profile switch configuration 成功后不显示未同步。
- Add 默认 switch configuration 失败时，设备添加成功，switch 显示未同步。
- Profile 未变化时，新增、删除、新增加删除 target groups 的命令集合与顺序符合需求。
- Profile 切换或 Scene Profile scene 关联变化时，switch configuration 先于 group add/remove。
- 非 PID `0x2A01`、`0x2A02` 的设备不进入该逻辑。
- 使用项目指定的直接 `xcodebuild` 命令验证 SunSmart 编译。

## 设计自检

- 文档内容完整。
- Add 成功与 switch configuration 成功的状态边界明确。
- SAVE 的命令顺序覆盖新增、删除、新增加删除、Profile 切换、scene 关联变化和 group 无变化。
- 范围限定在 PID `0x2A01`、`0x2A02`，不扩展到其它设备。
