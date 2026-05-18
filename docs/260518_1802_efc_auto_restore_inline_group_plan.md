# EFC Auto Restore 组内展示调整计划

## 背景

当前 EFC Edit SAVE 修复方案已经把 `AUTO` 恢复建模为 `EmergencyFireControllerSyncTaskKind.autoRestore`，并在同步计划末尾额外生成一批独立的 `EmergencyFireControllerSyncItem`。这样能保证发送 Auto 控制，但同步设备页会在最后再次展示前面已经展示过的 group，用户会看到同一批组重复出现。

用户提出的调整是：不要在同步页最后重复展示 group，而是把 `AUTO` 任务添加到每个 group 的最末尾任务。UI 上图标使用灯，设备名称显示 `AUTO`，任务也显示 `AUTO`。

## 合理性判断

该需求合理，且比当前“独立 Auto Restore item”更符合用户对同步进度的理解：

- 同一个 group 的配置和恢复动作属于同一次 group 同步流程，放在一个 group 下更直观。
- `AUTO` 必须在该 group 内所有关联灯的 Scene Subscription、Trigger Scene、Light LC Subscription 之后执行，否则 `Trigger Scene` 中的亮度写入仍可能覆盖 Profile Auto 状态。
- 同步页现有执行顺序来自 `SyncDevicesSectionModel.allModels`，同一个 group 下的 `deviceModels` 按创建顺序执行；只要 `AUTO` 作为最后一个 group-level device model 追加，就能保证它在该 group 里的灯节点任务之后执行。

需要注意：不能把 `AUTO` 任务伪装成某个灯节点地址。同步页会按 `task.address` 分组，若 `AUTO` 使用第一个灯节点地址，它会合并到该灯节点的任务列表中，可能在同组其他灯节点之前执行，不满足“每个组最末尾”的要求。

## 推荐方案

采用“group-level AUTO task，组内最后展示”的方案。

1. Planner 不再生成独立的 `makeActiveModeAutoRestoreItems()` 列表。
2. 在 `makeActiveModeAssociateItems()` 中，为每个当前激活关联 group 的 `tasks` 末尾追加一个 `autoRestore` task。
3. `autoRestore` task 保持 `address = group.address.address`，`messageHandles` 也发送到 group 地址，与 group 页面 Auto 按钮一致。
4. 同步页在构建 EFC leaf device model 时，对 `task.kind == .autoRestore` 做专门展示：
   - device name: `AUTO`
   - step/task name: `AUTO`
   - icon: 灯图标，沿用 `device_light`
   - operation context: 仍使用 `data.bindNode` 作为 `DeviceOperationType.configuration` 的 node 上下文
5. 这样每个 group 下会显示：灯节点 A、灯节点 B、...、`AUTO`。不会再把 group 在最后重复展示一次。

## 可选方案对比

### 方案 A：保持当前独立 AUTO item

优点：代码改动最少，发送链路已经验证能工作。

缺点：同步页重复展示同一批 group，用户容易理解成二次配置或重复设备。

结论：不推荐。

### 方案 B：把 AUTO 合并到某个灯节点任务末尾

优点：UI 不增加额外 device row。

缺点：同步页按节点分组执行，AUTO 会跟着某个灯节点执行，不能保证在同 group 所有灯节点之后执行。

结论：不推荐，存在行为风险。

### 方案 C：group-level AUTO task，展示为组内最后一个 AUTO 设备行

优点：不重复展示 group；执行顺序清晰；发送地址仍与 group 页面 Auto 完全一致；UI 能表达这是 group 级恢复动作。

缺点：同步页需要为 EFC 的 group-level task 增加一个小的展示分支。

结论：推荐。

## 开发计划

### 任务 1：调整 planner 的任务结构

- 修改 `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
- 删除或停用 `makeActiveModeAutoRestoreItems()` 在 `makeItems()` 中的独立追加。
- 在 `makeActiveModeAssociateItems()` 生成每个 group 的 `tasks` 时，把 `makeAutoRestoreTask(group:)` 追加到该 group 的 `tasks` 末尾。
- 保留 `makeAutoRestoreTask(group:)`，确保发送消息仍是 `LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)` 到 group 地址。

### 任务 2：同步页支持 group-level AUTO leaf row

- 修改 `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- 在 `makeEmergencyFireControllerLeafDeviceModel(item:tasks:data:)` 或其附近 helper 中识别 `autoRestore`。
- 当 task 为 `autoRestore` 时，创建一个名称为 `AUTO`、地址为 group 地址、图标为 `device_light` 的 `SyncDevicesModel`。
- `AUTO` row 下只保留一个 step，step 和 task 文案都显示 `AUTO`。
- `makeEmergencyFireControllerTaskModel(task:data:)` 可继续通过 `nodeForEmergencyFireControllerTask` fallback 到 `data.bindNode`，真正发送地址来自 task 的 `messageHandles`。

### 任务 3：验证顺序

- 检查 `groupedEmergencyFireControllerTasksByNode(_:)` 对 appended group-address task 的处理：由于它按首次出现地址追加分组，`AUTO` group-address task 会成为该 group 的最后一个 device model。
- 检查 `SyncDevicesSectionModel.allModels`：group 下的 `deviceModels` 按数组顺序展开，`getNextHandleModel()` 会按该顺序取下一项。
- 预期顺序：
  1. EFC controller 自身配置任务。
  2. Group 1 的每个灯节点关联任务。
  3. Group 1 的 `AUTO`。
  4. Group 2 的每个灯节点关联任务。
  5. Group 2 的 `AUTO`。
  6. Pending cleanup。

### 任务 4：验证构建

- 使用项目要求的命令直接运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：`BUILD SUCCEEDED`。

## 决策

推荐采用方案 C。它保留了 group 页面 Auto 按钮的真实 Mesh 行为，同时让同步页不再重复展示 group，并能保证每个 group 的 `AUTO` 在该 group 所有灯配置任务之后发送。
