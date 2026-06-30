# Space 删除后被云端旧数据恢复问题设计

## 背景

在 `Site - Space - Main - Lights` 中，用户通过底部 Delete 删除所有设备后，返回 Site 页面时 Space Item 显示 `Luminaires: 0`。随后点击该 Space Item 重新进入 Space，之前删除的设备又出现在 `Main - Lights` 中；再次返回 Site 后，Space Item 上的数量也变回非 0。

该问题的预期是：删除成功的设备不能被重新导入回当前 Space。

## 代码事实

- Lights 删除成功后会先移除本地节点，更新 `space.deviceCount` / `space.luminairesCount` 并保存，然后发送 `spaceDataChangedNotificaitonName`。
- `SpaceViewController` 监听 `spaceDataChangedNotificaitonName` 后，才更新 `space.lastUpdate`，并将 `syncSpace` 或 `syncSite(site, syncSpaces: [space])` 加入云同步队列。
- Site 页面点击 Space Item 时，会先请求 `/sitespace/get/spaceprops`，调用 `space.update(spaceJsonData:)`，之后才进入 `SpaceViewController`。
- `SpaceData.update(spaceJsonData:)` 一旦决定接受服务器数据，会先移除本地非 provisioner 节点，再按服务器 `nodes` 重建本地 Mesh 节点。
- `space.needUploadCloud` 的判断依赖 `lastUpdate > lastUploadCloudTimestamp`。如果删除流程只改了本地 count，但还没有同步更新 `lastUpdate`，本地可能暂时不被视为待上传数据。
- Space Item 上的 `Luminaires` 当前实际展示的是 `space.deviceCount`，因此现象中的数量变化代表本地 Space 设备总数被恢复，不只是 label 刷新问题。

## 根因

删除流程与云端导入保护之间存在时间窗口。

删除成功后，页面层已经移除了本地节点并保存了 Space 计数，但 Space 的 `lastUpdate` 和云同步任务依赖通知观察者异步处理。如果用户立即返回 Site 并再次点击 Space Item，Site 入口会先拉取云端 Space 数据。

当云端仍是删除前的旧 payload 时，`SpaceData.update(spaceJsonData:)` 可能认为服务器数据可以应用，继而清空本地节点并按旧云端 `nodes` 重建，导致已删除设备重新出现。

所以根因不是 Lights 列表未刷新，而是设备删除完成时没有同步、原子地把当前 Space 标记为“本地已有待上传变更”，导致旧云端数据可以覆盖本地删除结果。

## 影响面

### Lights

存在该问题。Lights 删除真实 Mesh 节点，成功后依赖 `spaceDataChangedNotificaitonName` 驱动 `lastUpdate` 和云同步。用户复现路径正是该入口。

### Switches

存在同类风险。Switches 删除开关数据后调用本地删除和刷新通知，并发送 `SpaceChangeDataType.device`。如果删除后立刻从 Site 入口拉取旧云数据，旧 `switches` payload 可能恢复被删除的 switch 数据。

### Sensors

当前没有同类问题。`DeviceSensorsViewController` 目前是固定空态，没有实际 sensor 列表、选择、删除入口，因此没有用户可触发的同类删除恢复路径。

### Others

存在同类风险。Others 删除 Dongle / Emergency Fire Controller 后也会更新本地数据、保存 Space count，并通过通知触发同步。如果旧云端 payload 先被拉取并应用，相关 Others 数据也可能恢复。

## 目标

1. Lights 删除成功后，重新进入 Space 不再恢复已删除设备。
2. Switches 和 Others 删除成功后，也不会被旧云端 Space payload 恢复。
3. 删除成功时立即让 Space 进入本地待上传状态，缩短或消除依赖通知观察者造成的时间窗口。
4. 继续复用现有云同步机制，不重写 `CloudSynchronizationManager`。
5. 保持 Sensors 当前行为不变。

## 非目标

- 不调整设备 reset / force delete 的 Mesh 协议语义。
- 不重构 `SpaceData.update(spaceJsonData:)` 的整体导入算法。
- 不改变 Site / Space 的导航结构。
- 不修改 UI 文案或本地化资源。
- 不改变 Sensors 页面能力。
- 不处理 Space Item 当前 `Luminaires` 展示 `deviceCount` 的文案/计数字段问题；该问题可作为独立显示问题后续评估。

## 推荐方案

采用共享 Space 本地变更提交入口。

新增一个小范围 helper，用于在删除成功 completion 内同步完成以下动作：

1. 根据当前 `MeshNetworkManager` 和本地业务数据刷新 Space summary count。
2. 如果 Space 当前用户是 owner / editor，则立即更新 `space.lastUpdate` 并保存。
3. 按现有规则加入云同步队列：
   - Site 已上传云端时，优先同步当前 Space。
   - Site 尚未上传云端时，按现有逻辑同步 Site 和相关 Spaces。
   - 对设备地址变化类删除，继续保留现有 `syncSite(site, syncSpaces: [space])` 语义。
4. 继续发送现有刷新通知，让当前页面和 sibling 页面更新 UI。

该 helper 不直接处理 UI，也不处理具体删除动作。页面只在删除已经成功、并完成本地数据移除后调用它。

## 组件设计

### Space 本地变更提交 helper

职责：

- 收敛“删除后更新 count、更新时间戳、保存、排队云同步”的重复逻辑。
- 根据变更类型选择现有 sync level 和 sync operation。
- 保持权限判断与 `SpaceViewController` 现有观察者一致：visitor 不上传本地改动，owner / editor 才推进 `lastUpdate` 和云同步。

建议放置位置：

- 优先放在 `SpaceData` 或 Space 相关扩展中，作为业务层工具函数。
- 如果需要 `site` 参与选择同步 operation，则提供 `site` 参数，避免 helper 反查导航层状态。

### Lights 删除入口

在成功删除节点并更新本地 `devices` 后，调用共享 helper。

覆盖分支：

- 全部 reset 成功。
- 部分成功后用户取消 force delete，但已有成功删除节点。
- force delete 失败节点。

### Switches 删除入口

在 `deleteCache(switchData:)` 中删除 switch 数据后调用共享 helper。

该入口覆盖：

- 普通 Kinetic switch。
- Battery / AC power switch。
- 无需 SyncDevices 任务的本地删除分支。
- SyncDevices 成功后的删除 completion。

### Others 删除入口

在 `finishDeleteOthersItem()` 完成本地删除后调用共享 helper。

该入口覆盖：

- Dongle 删除。
- Emergency Fire Controller 删除。
- linked / virtual EFC 删除后返回 Others 的刷新路径。

### Sensors

不改。当前没有实际删除入口，不纳入实现范围。

## 数据流

删除成功后的目标数据流：

1. 页面完成 Mesh reset、force delete 或业务对象删除。
2. 页面移除本地节点、switch、dongle 或 EFC 数据。
3. 页面调用共享 Space 本地变更提交 helper。
4. helper 刷新 Space count，更新 `lastUpdate`，保存本地数据，并加入云同步队列。
5. 页面发送原有刷新通知，刷新当前 UI。
6. 用户返回 Site 后，Space Item 读取到的本地 Space 已是待上传状态。
7. 用户再次点击 Space Item 时，如果云端仍返回旧 payload，`SpaceData.update(spaceJsonData:)` 应因为本地 `needUploadCloud == true` 而跳过旧数据覆盖。
8. 云同步完成后，服务器 payload 与本地删除结果一致。

## 错误处理

- 如果云同步失败，保留现有 `syncCloudError` / Space Item 同步失败提示机制。
- 删除本身失败时，继续沿用现有 force delete 提示和成功/失败分支。
- 如果本地已经没有任何 real node 且当前 Mesh 仍连接，保留现有关闭 Mesh 连接逻辑。
- visitor 权限下不新增上传行为，避免越权写云端。

## 测试计划

### 静态检查

- 确认 Lights 删除成功的三个分支都调用共享 helper。
- 确认 Switches `deleteCache(switchData:)` 调用共享 helper。
- 确认 Others `finishDeleteOthersItem()` 调用共享 helper。
- 确认 Sensors 无删除入口且无改动。
- 确认没有新增本地化、资源、target 配置或依赖变更。

### 行为验证

- Lights：删除所有设备，返回 Site，Space Item 显示 0；立即重新进入 Space，Main - Lights 不应恢复旧设备。
- Switches：删除 switch，返回 Site 后立即重新进入 Space，Main - Switches 不应恢复旧 switch。
- Others：删除 Dongle 或 EFC，返回 Site 后立即重新进入 Space，Main - Others 不应恢复旧 item。
- 云同步失败时，Space Item 应继续能显示现有同步失败提示，且本地删除结果不应被旧云端覆盖。

### 构建验证

使用 iPhoneOS 构建验证：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与缓解

- 风险：helper 与 `SpaceViewController` 通知观察者重复排队同步。
  - 缓解：CloudSynchronizationManager 已有同 operation 去重逻辑；实现时仍应尽量让删除入口改为 helper 负责同步，通知保留刷新用途。

- 风险：对 `.device` 和 `.network(type: .address)` 的同步语义混用。
  - 缓解：helper 参数明确变更类型，Lights / Others 真实节点地址变化继续使用 address 语义，Switches 使用 device/common 既有语义。

- 风险：过度修改 `SpaceData.update` 影响 share/import。
  - 缓解：本方案不重写导入算法，只保证删除 completion 及时设置本地 dirty 状态。

- 风险：Site 未上传云端时 operation 选择错误。
  - 缓解：沿用 `SpaceViewController.syncSpace(level:)` 的现有规则：Site 已上传则同步 Space，未上传则同步 Site 与 Spaces。

## 自检结论

- 无占位符或未决项。
- 范围聚焦在删除成功后的 Space 本地变更提交，不触碰 Mesh reset 和云端导入主流程。
- Lights、Switches、Others 的同类风险均纳入；Sensors 明确不纳入。
- 推荐方案与用户确认的方案 A 一致。
