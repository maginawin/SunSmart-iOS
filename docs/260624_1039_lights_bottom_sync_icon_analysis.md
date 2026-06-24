# Site - Space - Main - Lights 底部同步图标功能分析

## 结论

当前 `Site - Space - Main - Lights` 底部同步图标是 Lights 页专属的入口。它在非编辑状态下检查当前 Space 内所有真实灯设备，只要存在任意 `Node.needSync == true` 的 light，就显示底部 `sync_failed` 图标；如果没有需要同步的灯设备，则隐藏。

`Switches`、`Sensors`、`Others` 三个 Main 子页都复用了 `SpaceFunctionFooterView`，但当前没有实现底部 `functionDidClickSync` 行为，也没有主动根据列表内容控制 `footerView.syncBtn` 显示。因此这三个 tab 没有与 Lights 底部同步图标完全相同的底部功能。

点击 Lights 底部同步图标后，会把当前 Lights 列表中 `needSync == true` 的灯设备传给 `SyncDevicesViewController(type: .devices(syncDevices))`。同步页会按每个节点的 `node.getSyncData(type: .all)` 展开需要同步或删除的任务。

## 展示条件

入口文件：

- `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`
- `SunSmart/Main/Space/View/SpaceFunctionFooterView.swift`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- `SunSmart/Common/Data/Node+SyncData.swift`

展示链路：

1. Lights 页加载设备时，只收集 `MeshNetworkManager.instance.realNodes` 中 `deviceType == .light` 的节点。
2. Lights 页 `updateUI` 在非编辑状态下异步判断 `devices.contains { $0.needSync }`。
3. 如果存在需要同步的灯，设置 `footerView.syncBtn.isHidden = false`；否则隐藏。
4. 进入编辑状态时，`SpaceFunctionFooterView.updateUI()` 会统一隐藏 `syncBtn`。
5. `footerView.syncBtn.isEnabled` 取决于 `space.deviceOperates.contains(.edit)`。也就是说没有 edit 权限时图标可能按 needSync 结果显示，但按钮不可点击。

`Node.needSync` 的判定不是单一字段。当前实现会先走缓存，没有缓存时调用 `getNeedSync()`，并把 `needSyncGroupData` 纳入最终结果。主要触发来源包括：

- 设备 key bind / 初始化未完成。
- 设备需要加入组或退出组。
- group/profile 配置与当前设备状态不一致。
- scene 需要同步或删除。
- schedule 需要同步或删除。
- 动能开关代理或绑定关系需要同步或删除。
- 邻近照明配置需要同步。
- 部分设备参数与 restore data 不一致，例如 PWM frequency、rated power、relative sensitivity。
- 对 dongle / gateway 类型还有额外数据判断，但 Lights 底部入口只传 light 节点，因此普通 Lights 入口不会主动覆盖 dongle/gateway。

## Switches / Sensors / Others 是否有同样功能

没有完全相同的底部功能。

### Switches

`DeviceSwitchesViewController` 实现了 footer 的 Add 和 Edit delegate，但没有实现 `functionDidClickSync`，也没有控制 `footerView.syncBtn` 展示。

Switches 相关同步提示存在于其他位置：

- `DeviceSwitchesViewCell` 会在 `switche.needSyncData` 时把 cell 图标替换为 `sync_failed_big`。
- `DeviceSwitchViewController` 的 header 会按 `switchData.needSyncData` 显示 `syncFailedBtn`。
- 点击 switch 详情页的同步提示会进入 `SyncDevicesViewController(type: .enOceanSwitch(...))`。

所以 Switches 有“单个开关/详情页同步”能力，但不是 Main - Switches 底部统一同步 icon。

### Sensors

`DeviceSensorsViewController` 只实现了 footer 的 Add 和 Edit delegate，没有看到 bottom sync icon 的显示或点击实现。

### Others

`DeviceOthersViewController` 只实现了 footer 的 Add 和 Edit delegate，没有实现 `functionDidClickSync`，也没有控制底部 `syncBtn` 展示。

Others 中存在独立的同步提示：

- Dongle cell 会在 `dongle.needSyncData` 时显示 `sync_failed_big`。
- Dongle 详情页 header 会按 `dongleData.needSyncData` 显示同步失败按钮，并进入 `SyncDevicesViewController(type: .dongle(...))`。
- Emergency & Fire Controller 的 `displayStatus == .syncIssueDevice` 时 cell 显示同步问题；点击该 cell 会进入 EFC 编辑页，而不是通过底部统一 sync icon 直接同步。

因此 Others 有设备级或业务级同步入口，但没有与 Lights 底部相同的统一同步按钮。

## 点击 Lights 底部同步图标后的同步内容

点击入口：

- `DeviceLightsViewController.functionDidClickSync`

执行流程：

1. 过滤当前 Lights 页 `devices` 中 `needSync == true` 的节点。
2. 创建 `SyncDevicesViewController(type: .devices(syncDevices))`。
3. 同步页对 `.devices` 分支逐个调用 `getSyncDeviceModel(group: nil, node:)`。
4. 因为没有传入 group，`getSyncDeviceModel` 使用 `node.getSyncData(type: .all)` 生成同步数据。
5. 同步数据被分成 configuration section 和 remove section。同步成功或返回后，Lights 页会 `updateUI()` 重新计算底部 icon 状态。

当前 `.all` 路径可能生成的同步内容如下：

- Initialize：设备未完成 key bind / 初始化时，生成 device initialize 任务。
- Group subscription：如果节点已有 group 或 restoreData.addGroup，则同步加入组、退出组、组订阅。
- Profile：同步 group profile 或无组 profile，包括传感器发布、Light LC、daylight / occupancy / vacancy 等 profile 差异。
- Scene：同步需要写入的 scene，删除设备侧多余 scene。
- Schedule：同步需要写入的 schedule，删除设备侧多余 schedule。
- Switch relation：同步或删除动能开关 proxy、linked switches；Battery Power Switch 的 group subscription 也走这里生成 `Group Subscription` / `Group Unsubscription` 任务。
- Proximity Lighting：同步邻近照明启用状态、relay number、neighbor/path sequence。
- Device parameters：当 restoreData 与节点当前值不一致时，同步 PWM frequency、rated power、relative sensitivity 等参数。
- Dongle data：`.all` 支持 dongle collection schedules，但 Lights 底部入口不会传入 dongle 节点。
- Gateway data：`.all` 支持 gateway project / associated spaces / subnet appkey / APN / MQTT 信息，但 Lights 底部入口不会传入 gateway 节点。

## 需要注意的边界

- Lights 底部 icon 的显示依据是当前内存中的 `Node.needSync`，它会使用缓存；具体缓存失效依赖设备状态、同步回调和相关数据刷新路径。
- `getNeedSyncGroup(group:)` 在判断 sensor server publication 时使用 `legacyCompatible`，而实际 `.all` 生成同步任务时仍会走严格的 `getSyncData` 路径。这是为了避免部分旧配置在 UI 上误报 need-sync，同时保留真实同步任务的严格生成逻辑。
- 旧任务中曾出现 “Main - Lights sync 一下就恢复” 的现象，原因方向优先考虑 deferred group/profile/publication sync，而不是 provisioning 本身失败。当前 worktree 仍保留 `DeviceGroupDeferredSyncPlanner` 和 `GroupProfileSyncContext(reason: .memberAdded)` 相关实现。

## 代码证据索引

- Lights 设备来源：`DeviceLightsViewController.loadDevices`
- Lights icon 显示控制：`DeviceLightsViewController.updateUI`
- Lights icon 点击入口：`DeviceLightsViewController.functionDidClickSync`
- Footer 默认隐藏和点击分发：`SpaceFunctionFooterView`
- `Node.needSync` 判定入口：`MeshNetwork+SunSmart.Node.needSync`
- `Node.getNeedSync()` / `getSyncData(type: .all)`：`Node+SyncData.swift`
- `.devices` 同步页分支：`SyncDevicesViewController.setupDataSource`
- `.all` 展开为 section / step：`SyncDevicesViewController.getSyncDeviceModel`
