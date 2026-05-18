# Device1.5 交接文档

更新时间：2026-05-18

## 总览

`Device1.5` 是新一批设备业务的独立目录，当前主要包含：

- `Common`：1.5 设备添加、恢复入口的公共分发层。
- `FireAlarm`：应急火警控制器，业务链路相对完整，包含本地配置、绑定节点、虚拟组、同步、监控、删除、导入导出等。
- `NEightKeySwitches`：8 键开关，目前主要是 UI/页面骨架、基础模型和本地元数据保存，业务层还没有完整闭环。
- `NGateWay`：Wifi + SIG Mesh 网桥，目前主要是 UI/页面骨架和部分云端/网关配置尝试，业务层还没有完整闭环。

接手优先级建议：

1. 先熟悉 `Common` 入口分发和老添加页面复用方式。
2. 重点接 `FireAlarm`，这是当前最需要维护和继续补边界的完整业务。
3. `NEightKeySwitches`、`NGateWay` 不要按已完成业务接手，需要重新按需求核对协议、数据存储、同步、删除、导入导出和异常态。

## 公共入口

目录：`Common`

关键文件：

- `Flow/PJDevicesAddFlowFactory.swift`
- `Flow/PJDevicesRestoreFlowFactory.swift`
- `Flow/PJDevicesLegacyContainerController.swift`
- `Flow/PJDevicesAddEntryContext.swift`
- `Flow/PJDevicesRestoreEntryContext.swift`
- `GroupSelection/Controller/PJDeviceGroupSelectionViewController.swift`

当前做法：

- 通过 `PJDevicesEntrySource` 区分 fireAlarm、eightKeySwitch、gateway。
- 添加入口走 `PJDevicesAddFlowFactory.make(context:)`。
- 恢复入口走 `PJDevicesRestoreFlowFactory.make(context:)`。
- 三类设备的 Add/Restore 容器目前都复用老的 `DeviceAddViewController`，通过 `PJDevicesLegacyContainerController` 嵌入。
- `FireAlarm`、`EightKeySwitch` 添加入口会传 `context.addBehavior`，`Gateway` 添加入口目前没有传 addBehavior。

接手注意：

- 这个公共层只是路由/容器，不等于业务已经完成。
- 后续如果新设备有独立添加流程，建议保留 factory 分发，把老 `DeviceAddViewController` 替换成各自独立 Controller。
- 不要在公共层写设备特有业务，设备特有逻辑放回各自模块。

## FireAlarm 应急火警

目录：`FireAlarm`

这是当前完成度最高的 1.5 业务。核心概念是：一个本地的 `DeviceEmerFireData` 绑定一个真实 Mesh 节点，并用一个内部 virtual group 做 EFC Scene Client / Light LC Client publication，灯组侧订阅这个内部组，以便火警/断电触发时联动灯。

### 主要入口

- 列表：`Controller/EmerFireAlarmDevicesController.swift`
- 添加专业模式：`Controller/EmerFireAlarmAddProfessionalVC.swift`
- 编辑配置：`Controller/LinkedEmerFireEditVC.swift`
- 编辑表格：`Controller/LinkedEmerFireEditVC+Table.swift`
- 组选择：`Controller/LinkedEmerFireGroupSelectionVC.swift`
- 监控页：`Controller/EmerFireAlarmMonitorVC.swift`
- 监控渲染：`Controller/EmerFireAlarmMonitorRendering.swift`
- 监控路由/删除/刷新：`Controller/EmerFireAlarmMonitorRouting.swift`
- Mesh 消息回调：`Controller/EmerFireAlarmMonitorDelegates.swift`
- 同步页：`Controller/EmerFireAlarmControllerSyncVC.swift`

### 数据与存储

核心文件：

- `Model/DeviceEmerFireData.swift`
- `Repositories/DeviceEmerFireRepository.swift`
- `Model/LinkedEmerFireConfig.swift`
- `Model/DeviceEmerFireData+Sync.swift`

本地表：

- 表名：`emergencyFireControllers`
- 关键字段：
  - `controllerId`
  - `spaceId`
  - `meshUUID`
  - `subNetworkKey`
  - `name`
  - `bindNodeAddress`
  - `publishGroupAddress`
  - `isSynced`
  - `reportToGateway`
  - `configurationData`
  - `createTime`
  - `lastUpdate`

重要说明：

- `spaceId` 必须保留。应急火警是空间级业务，后续可能跨空间，导入导出也要保留空间维度。
- `configurationData` 是 JSON 编码的 `EmergencyFireControllerConfiguration`。
- `isSynced` 是本地同步态，不能盲信导入文件里的值。导入时应根据配置意图、绑定节点、发布组等重新推导。
- `DeviceEmerFireStore.devices(in:)` 会把数据库记录和真实 emergencyController 节点合并，发现真实节点但没有本地记录时会补一条未同步本地记录。

### 配置模型

`EmergencyFireControllerConfiguration` 包含：

- `workMode`
  - `powerLossEmergency`
  - `fireAlarmEmergency`
  - `allDisabled`
- `powerLossSettings`
- `fireAlarmSettings`

每个 mode 的 settings 包含：

- 关联灯组地址：`associateGroupAddresses`
- 触发亮度：`triggerBrightness`
- 触发重发间隔/次数：`triggerIntervalSeconds`、`triggerCount`
- 停止重发间隔/次数：`stopIntervalSeconds`、`stopCount`
- 恢复延迟：`restoreDelaySeconds`
- 待清理灯组：`pendingUnassociateGroupAddresses`

接手重点：

- 从 A 模式切到 B 模式，旧模式关联组不能直接丢掉，要进入 pending cleanup。
- `allDisabled` 也可能有 pending cleanup，不能因为 active mode 为 nil 就跳过清理。
- `hasSyncIntent` 用于判断配置是否仍有同步意图，导入导出、同步态判断时要用它，而不是只看 `isSynced`。

### 同步链路

核心文件：

- `Model/EmergencyFireControllerSyncPlanner.swift`
- `Model/EmergencyFireControllerSyncPlan.swift`
- `Model/EmerFireAlarmSyncCellModel.swift`
- `Controller/EmerFireAlarmControllerSyncVC.swift`
- 通用同步页面：`Main/Space/Controller/SyncDevicesViewController.swift`

主要同步任务：

- Controller 侧：
  - Scene Client publication 设置到内部 virtual group。
  - Light LC Client publication 设置到内部 virtual group。
  - Vendor work mode 设置。
  - Vendor resend 参数设置。
  - Vendor restore delay 设置。
- 灯组侧：
  - Scene Server 订阅内部 virtual group。
  - 存储触发 scene。
  - Light LC Server 订阅内部 virtual group。
- 清理侧：
  - 从灯节点移除内部 virtual group 的订阅。
  - 清理 pending unassociate groups。

内部 virtual group：

- 每个 EFC 应复用自己的 `publishGroupAddress`。
- 不要为同一个 EFC 重复创建虚拟组。
- 删除 EFC 时，如果本地有 publish group，最终要清本地配置并移除缓存 group。
- 删除时如果 cleanup task 没有真实 Mesh 消息，只是 local-only 配置清理，不应要求 Mesh 在线。

### 监控页链路

核心文件：

- `ViewModels/EmerFireAlarmMonitorViewModel.swift`
- `ViewModels/EmerFireAlarmMonitorState.swift`
- `Controller/EmerFireAlarmMonitorVC.swift`
- `Controller/EmerFireAlarmMonitorRendering.swift`
- `Controller/EmerFireAlarmMonitorDelegates.swift`
- `Controller/EmerFireAlarmMonitorRouting.swift`

监控页根据 `currentWorkMode` 和设备上报的 `EmergencyControllerMode/active` 映射显示状态。

需要注意：

- 火警模式和断电模式按钮、文案、状态图标是两套。
- 火警模式下，识别按钮后面的触发/停止按钮边框要走火警色系。
- 信息页打开的是绑定的真实节点 `currentDevice?.bindNode`，不是本地 EFC 配置本身。
- 通用设备信息页需要主动刷新 RSSI，否则首次进入可能只显示 `--`。

### 删除链路

入口：

- 监控页删除：`EmerFireAlarmMonitorRouting.deleteDevice()`
- Others 列表删除：`DeviceOthersViewController.deleteEmergencyFireController`

删除时做的事：

1. 生成 delete cleanup items。
2. 判断是否有真实 Mesh message 需要同步。
3. 如果只是 local-only 配置清理，直接清本地配置，不要求 Mesh 在线。
4. 如果需要 Mesh 同步且 Mesh 在线，进入 `SyncDevicesViewController`。
5. 同步成功后清理本地配置，刷新列表/空间状态。

已知边界：

- 不要用 cleanupItems 是否为空判断是否要 Mesh 在线，要看 task 里是否存在 `messageHandles`。
- local-only cleanup item 是为了让 pending 配置能被清掉，不代表需要 Mesh。

### 导入导出

涉及文件：

- `Common/Data/ImportData.swift`
- `Common/Data/Node+SyncData.swift`
- `Common/Data/Node+MessageHandles.swift`
- `LinkedEmerFireConfig.swift`

接手注意：

- 导出字段需要覆盖：`spaceId`、`meshUUID`、`meshNetworkId`、绑定节点地址、publish group address、configuration。
- 导入时不要直接信 JSON 的 `isSynced`。
- 如果导入后还有绑定节点、publish group 或非空同步意图，应标记为未同步，让同步页重新对齐真实设备。
- `spaceId` 后续跨空间时会变得更重要，不要删。

### FireAlarm 后续建议

- 补自动化测试或至少补一份手测清单：模式切换、pending cleanup、删除、导入导出、Mesh 离线删除、设备离线显示。
- 梳理 `SyncDevicesViewController` 里 EFC 和老设备同步展示的兼容边界。
- 继续验证 vendor 协议：work mode、resend、restore delay 的 ack/失败重试策略。
- 检查虚拟组生命周期：创建、复用、删除、导入恢复后的地址冲突。

## NEightKeySwitches 8 键开关

目录：`NEightKeySwitches`

当前状态：页面和本地元数据雏形已有，业务层未完成。

已有内容：

- 添加/恢复容器：
  - `Add/Controller/PJDevicesEightKeyAddContainerController.swift`
  - `Restore/Controller/PJDevicesEightKeyRestoreContainerController.swift`
- 监控和设置页面：
  - `Controller/PJEightKeySwitchMonitorVC.swift`
  - `Controller/PJEightKeySwitchMoreSettingsController.swift`
  - `Controller/PJEightKeySwitchSelectPanelController.swift`
  - `Controller/PJSwitchesTypesVC.swift`
  - `Controller/PJPreAddEightKeySwitchesVC.swift`
- 模型：
  - `Model/PJEightKeySwitchData.swift`
  - `Model/PJEightKeySwitchPanelDefinition.swift`
  - `Model/PJEightKeySwitchStatus.swift`
- 本地元数据：
  - `Repositories/PJEightKeySwitchRepository.swift`
- ViewModel：
  - `ViewModel/PJEightKeySwitchMonitorViewModel.swift`
  - `ViewModel/PJEightKeySwitchMoreSettingsViewModel.swift`
  - `ViewModel/PJEightKeySwitchSelectPanelViewModel.swift`
  - `ViewModel/PJPreAddEightKeySwitchesViewModel.swift`
  - `ViewModel/PJSwitchesTypesViewModel.swift`

当前能说明的业务意图：

- 区分 8 键面板类型，例如 scene 8 key、brightness 8 key。
- 本地保存面板类型、periodic reporting、LED indicator enabled。
- 根据绑定/启用/同步异常等状态展示不同 icon。

未完成/待接手确认：

- 8 键开关真实协议命令没有完整闭环。
- 添加后如何识别为 8 键、如何绑定到老 `DeviceSwitchData`，需要继续核对。
- 按键配置、scene/dimming/forced auto 等弹窗目前偏 UI，真实下发和回读需要补。
- 删除、恢复、导入导出、同步态没有完整统一策略。
- 和老 `Switches` 业务的边界需要小心，不要破坏旧开关流程。

建议接手方式：

1. 先拿协议确认每个按键配置需要下发哪些 vendor/model message。
2. 再确定本地表是否够用，目前只保存了面板类型和更多设置，可能不足以恢复完整业务。
3. 最后补同步页/异常修复页，不要只靠 UI 状态展示。

## NGateWay 网桥

目录：`NGateWay`

当前状态：UI、页面交互和部分网络/云端注册逻辑已有，完整设备业务层未完成。

已有内容：

- 添加/恢复容器：
  - `Add/Controller/PJDevicesGatewayAddContainerController.swift`
  - `Restore/Controller/PJDevicesGatewayRestoreContainerController.swift`
- 主页面：
  - `Controller/PJNGatewayViewController.swift`
  - `View/PJNGatewayDetailView.swift`
  - `ViewModel/PJNGatewayPageViewModel.swift`
  - `Model/PJNGatewayModel.swift`
- WiFi DFU：
  - `Controller/PJNGatewayWiFiDFUViewController.swift`
  - `Controller/PJNGatewayWiFiDFUHistoryViewController.swift`
  - `ViewModel/PJNGatewayWiFiDFUViewModel.swift`
  - `ViewModel/PJNGatewayWiFiDFUHistoryViewModel.swift`
  - `Model/PJNGatewayWiFiDFUModel.swift`
  - `Model/PJNGatewayWiFiDFUHistoryModel.swift`

已有逻辑：

- 页面可编辑名称、激活状态、网络信息展示。
- 通过 `NEHotspotNetwork.fetchCurrent` 获取当前 SSID。
- 有 2.4GHz 提示逻辑。
- 有云端 gateway register/delete、关联空间查询/解绑的部分调用。
- 注册成功后尝试通过 vendor message 下发 MQTT connect info。

未完成/待接手确认：

- 真实配网流程未完整闭环。
- IP/DNS 等网络信息目前存在默认值/模拟填充，不能视为真实设备回读。
- WiFi DFU 删除仍有 placeholder 文案。
- 网关和空间关联的权限、云端状态、Mesh 设备状态三者需要完整设计状态机。
- 删除网关时云端删除、本地 Gateway、Mesh Node、关联空间关系的顺序需要继续确认。
- 添加入口目前没有传 `addBehavior`，要确认是否符合产品预期。

建议接手方式：

1. 先确认网关协议：配网、MQTT 下发、网络状态回读、DFU。
2. 再确认云端 API：register、delete、association space list、unbind space 的错误码和权限策略。
3. 最后统一 UI 状态，不要让模拟网络状态和真实设备状态混在一起。

## 国际化与 UI 规范

历史要求：

- 国际化写到 `SunSmart/en.lproj/Localizable.strings`。
- 每个 1.5 模块建议用自己的注释区块，例如 `v1.5-- FireAlarm`、`v1.5-- NEightKeySwitches`、`v1.5-- NGateWay`。
- UI 按 Figma，白色圆角、背景、约束和交互细节要严格检查。
- 文件超过 500 行时尽量拆 Controller/ViewModel/View/Model，不要继续堆大文件。

接手注意：

- 现有代码里有不少纯代码 UI，改动时要特别看小屏和横向文案。
- 新增文案不要直接写英文硬编码，除非已有历史代码就是硬编码且短期不改。

## 当前工作区提醒

写本文档时，工作区已有这些状态，不是本文档造成的业务改动：

- `SunSmart.xcodeproj/project.pbxproj` 已修改。
- `FireAlarm/firealarm.md` 当前处于删除状态。
- `NGateWay/ngateWay.md` 当前处于删除状态。

如果接手人需要恢复模块原始需求说明，可以从 git 历史里查看上述 md。

## 建议交接顺序

1. 先跑一遍添加入口：从设备添加页进入三类 1.5 设备，确认 factory 分发。
2. 再跑 FireAlarm：
   - 新建 EFC。
   - 绑定真实 emergency controller。
   - 配置 power loss/fire alarm 两种模式。
   - 同步。
   - 进入监控页。
   - 切换模式产生 pending cleanup。
   - 删除时分别测 Mesh 在线和离线。
3. 最后只验 8 键和 NGateway 的页面，不要承诺业务闭环。

## 风险清单

- FireAlarm 的同步态是本地态，和真实 Mesh 设备可能漂移，导入、删除、跨空间时尤其要谨慎。
- FireAlarm 的内部 virtual group 是关键资源，不能重复创建，也不能错误复用到其它 EFC。
- pending cleanup 不能丢，丢了会导致灯节点保留旧订阅。
- local-only cleanup 不应要求 Mesh 在线。
- 8 键开关和 NGateway 当前不是完整业务，后续排期要按“继续开发”估，不要按“修 bug”估。

