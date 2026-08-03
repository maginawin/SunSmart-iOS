# Restore Device Data 扫描过滤与 EFC 恢复支持分析

**日期：** 2026-08-03
**状态：** 方案 B 已确认并完成实现；真机 EFC/Mesh 验收待执行
**范围：** 扫描过滤、EFC 恢复链分析与方案决策；实施结果见对应实施总结

## 1. 结论

1. Restore Device Data 不是按 CID/PID 白名单扫描。SDK 先用广播中的 MAC（兼容旧 MAC）反查当前 Mesh 或本地历史 Node；只有能匹配历史 Node 的未配网广播，才会回调给页面。
2. 页面随后叠加 RSSI、入口、Space、指定节点列表和已恢复状态等过滤。
3. 当前 Space 内 Restore Device Data 实际允许恢复非 Gateway、非 EFC 的历史设备，包括 Lighting、Sensor、Switch、Dongle，以及配置映射产生的 Unknown；Site 入口只允许 Gateway。
4. `CID 0x0A78 / PID 0x2131` 已在设备配置中登记为 `EmergencyController`，型号为 `SR-BL2421-DryCon924`，SDK 也已有该 PID 的模型绑定测试基础。
5. 但当前 Restore 页明确排除所有 `.emergencyController`，所以该 EFC 现在不会出现在扫描结果中，也不会进入恢复流程。结论是：**识别与普通添加支持已存在，Restore Device Data 当前不支持恢复它。**
6. Restore 控制器内仍保留一套不可达的 EFC 本地配置迁移和同步消息代码。历史提交显示该能力曾被加入，随后又被明确下线。它调用当前 `EmergencyFireControllerSyncPlanner`，因此消息规划会随现有 EFC 功能更新；但候选识别、任务执行收口、同步真值和失败 Retry 仍是旧链路，不能只删除过滤条件。
7. 修订后的支持范围不再限定 `0x0A78/0x2131`，而是支持设备配置注册表中所有 `deviceCategory == EmergencyController` 的产品；恢复仍要求扫描设备与历史 Node 的 CID/PID 一致，避免跨产品错误迁移。

## 2. 当前扫描与过滤链路

### 2.1 SDK 候选条件

`MeshAddDeviceManager.startScanRestoreDevices` 对每个广播执行以下判断：

1. 广播必须能构造 `ProvisioningDevice`。
2. 广播必须包含可解析的 MAC。
3. MAC 或兼容旧 MAC 必须匹配：
   - 当前 Mesh 的 `realNodes`；或
   - 当前 Mesh UUID、当前 NetworkKey networkId 下持久化的历史 Node。
4. 同一 MAC/旧 MAC 只回调一次。

这里没有按设备类别、CID 或 PID 过滤。它的业务含义是恢复“App 曾经认识的同一台被重置设备”，不是发现任意新设备，也不支持用不同 MAC 的替换硬件直接恢复旧数据。

### 2.2 页面通用条件

页面收到 SDK 回调后还要求：

- 原始 RSSI 不低于 `-100 dBm`；高于 `-25 dBm` 时显示值封顶为 `-25 dBm`。
- 当前 RSSI 滑块范围默认为 `-100...-25 dBm`，不在用户选择范围内的设备不展示。
- 设备必须通过入口过滤 `RestoreFilter`。
- `RestoreMode.specified` 下必须位于指定历史 Node 列表，并按旧 primary unicast address 匹配。
- 已成功恢复的 Node 不再进入待恢复集合；去重兼容 MAC 与旧 MAC。

### 2.3 不同入口的设备过滤

| 入口/模式 | 当前过滤 | 实际结果 |
| --- | --- | --- |
| Space - Restore Device Data | `currentSpaceNonGateways` | 只允许当前 Space 的非 Gateway、非 EFC Node |
| Site - Restore Device Data | `gatewaysOnly` | 只允许 Gateway |
| BLE OTA 后指定恢复 | 默认 `all` + `specified(nodes)` | 只允许指定列表中尚未恢复的 Node，但仍排除 EFC |
| 旧/通用容器默认过滤 | `all` | 除 EFC 外不限制类型和归属 |

`PJDevicesFireAlarmRestoreContainerController` 虽然存在，但当前只是把同一个 Restore 控制器包一层，仍使用默认 `all`，因此仍受 EFC 排除条件限制；本次检索也未发现它被当前业务入口实际创建。

## 3. 当前可恢复的设备类别

### 3.1 代码级类别

`Node.DeviceType` 包含：

- Light
- Sensor
- Switches
- Dongle
- Gateway
- Emergency Controller
- Unknown

当前规则下：

- Space 入口：Light、Sensor、Switches、Dongle、Unknown；不含 Gateway 和 Emergency Controller。
- Site 入口：仅 Gateway。
- 指定恢复：除 Emergency Controller 外均可进入，但还受指定列表约束。

### 3.2 当前内置设备目录

`devices_config.json` 当前包含：

| deviceCategory | 数量 | 当前恢复入口 |
| --- | ---: | --- |
| Lighting | 121 | Space / 指定恢复 |
| BatteryPowerSwitch | 2 | Space / 指定恢复，走专用 BPS 恢复配置 |
| ACPowerSwitch | 2 | Space / 指定恢复 |
| Dongle | 2 | Space / 指定恢复，迁移绑定地址与集合日程 |
| Gateway | 6 | Site / 指定恢复 |
| EmergencyController | 1 | 当前全部被过滤 |

配置表当前没有独立 `Sensor` 条目，但代码允许服务器设备配置映射出 Sensor。没有配置项的 Node 默认可能按 Light 处理，因此“列表可见”不等于该产品所有专有数据都能完整恢复。

### 3.3 恢复内容边界

普通恢复链路会根据设备能力恢复或迁移：

- 重新 Provision、Composition/Key Bind 和基础初始化；
- 旧名称、MAC/RSSI、本地 Node 映射；
- 有效旧 Group 归属与模型订阅；
- Profile、Scene、Schedule、Switch Proxy 等 `NodeSyncData`；
- PWM frequency、photosensor exception、phase energy consumption、motion sensitivity range；
- 日光校准值/校准数据、邻近照明路径中的旧地址、设备日程目标地址；
- Dongle 绑定地址和 collection schedule；
- GatewayModel 地址映射；
- Battery Power Switch 的虚拟开关配置、目标订阅和初始电量读取。

这些都是按模型和能力条件生成，不能理解为每一种设备都会恢复全部项目。真实 Mesh ACK、最终同步状态和设备行为才是完成依据。

## 4. EFC Controller 调查

### 4.1 已有支持

- `devices_config.json` 已将它定义为：
  - Category：Emergency Controller
  - Device category：EmergencyController
  - Element count：3
  - Model：SR-BL2421-DryCon924
- `Node.DeviceType` 可映射为 `.emergencyController`。
- 普通 Add Device 的 Classic/Professional 流程已有 EFC 专用处理。
- 本地 SDK 已被 workspace 以 local Swift Package 引用，SDK 测试中使用 PID `0x2131` 验证附加 client model 的 AppKey bind 收集。
- EFC 本地业务对象已保存名称、绑定 Node 地址、内部 virtual publish group、Gateway 选项、Working Mode、Power Loss/Fire Alarm 关联组和动作、Restore 动作/延迟/发送次数及同步状态。

当前内置目录只有 `0x0A78/0x2131` 一个 EmergencyController，但服务器设备配置会覆盖并持久化到本地数据库。因此“所有 EFC Controller 类型设备”应解释为：当前设备配置注册表中，使用 CID/PID 精确命中且 `deviceCategory` 映射为 `.emergencyController` 的所有产品，而不是维护硬编码 PID 列表。

### 4.2 当前阻断

`DeviceRestoreViewController.shouldIncludeRestoreNode` 在以下两条路径显式排除 `.emergencyController`：

- `.all`
- `.currentSpaceNonGateways`

现有 `scripts/check_efc_controller_flows.sh` 还把“不列出 EFC”固化成合约，所以这是明确的当前产品行为，不是偶发扫描问题。

### 4.3 休眠恢复代码已有的能力

不可达代码目前能够：

- 根据旧/新 EFC Node 地址查找已有 `DeviceEmerFireData`；
- 保留原本的 EFC 本地配置，更新绑定到新 Node 地址；
- 保留或补建内部 publish group；
- 删除新地址上的重复本地 EFC 记录；
- 用 `EmergencyFireControllerSyncPlanner` 生成控制器 publication、working mode、resend、action config、restore delay，以及关联灯订阅/清理任务；
- 把发送失败映射为 Restore 页的 `syncFailed`。

### 4.4 不能只解除过滤的原因

1. **类型识别来源不够严格。** 当前 Restore 使用历史 `node.deviceType`；该属性的配置查找只按 PID，且扫描回调把历史 Node 类型直接赋给 `ProvisioningDevice`。支持所有 EFC 时应改为使用当前设备配置注册表按 CID+PID 精确解析，而不是只信历史类型或硬编码 PID。
2. **候选身份不够严格。** SDK 恢复扫描按 MAC 找旧 Node，不校验扫描广播的 CID/PID 与旧 Node 一致。所有 EFC 产品都可恢复，不等于允许不同 EFC 产品之间迁移；必须保证当前广播 CID/PID 与历史 Node 一致。
3. **同步状态会失真。** EFC 本地迁移会设置 `controllerSelfSyncPending = true`，但休眠 Restore 收口只写 `isSynced = !failed`，没有按任务结果清理 controller self pending，也没有执行当前 EFC 同步页的完整状态刷新逻辑。
4. **清理任务结果未完整落库。** 休眠路径把 planner 任务展平成消息句柄；非空 cleanup 任务成功后没有按任务调用 `clearPending`，会遗留 pending group 状态。
5. **失败重试路由不正确。** Restore 页统一把同步失败 Node 送入普通 `.devices` 同步；EFC 应走 `.emergencyFire` 同步类型，才能重建专用 planner 并正确更新 EFC 聚合状态。
6. **任务可观测性不足。** EFC planner 同时涉及控制器自身和多个关联灯。展平成 Fast Add 附加消息后，用户只看到一个设备级成功/失败，无法利用现有 EFC Sync device(s) 页的逐任务结果与 Retry。
7. **历史行为是主动下线。** Git 历史显示 EFC Restore 曾加入，随后以 “remove restore for EFC” 目标在候选边界下线。现有文档没有记录下线的业务原因，不能假设当时只是临时屏蔽。

### 4.5 与当前 EFC 功能的符合性

结论：**当前休眠 Restore 链只在“本地配置迁移”和“消息规划”两个环节基本符合现有 EFC 功能；端到端执行与结果真值不符合。**

| 当前 EFC 能力 | 休眠 Restore 链 | 评估 |
| --- | --- | --- |
| 保留名称、绑定地址、publish group、Gateway 选项、完整 configuration | 调用当前 `DeviceEmerFireStore.restoreDevice`，原对象不重建 | 符合 |
| Working Mode：Disabled / Power Loss / Fire Alarm / Both | Restore 设置 `controllerSelfSyncPending = true`，当前 planner 会生成 `0x4D/0x05` | 消息规划符合 |
| Trigger/Restore resend | 当前 planner 生成 `0x4D/0x03` | 消息规划符合 |
| 三种状态 Action Config | 当前 planner 生成 `0x4D/0x07`，使用现有 action/brightness/restore 规则 | 消息规划符合 |
| Restore delay | 当前 planner 生成 `0x4D/0x06` | 消息规划符合 |
| Scene Client publication 到内部 virtual group | 当前 planner 重新检查并生成 publication | 消息规划符合 |
| 关联灯组仅处理 Light，并覆盖新增订阅与 pending cleanup | 当前 planner 已按 Light 过滤并生成现行任务 | 消息规划符合 |
| 逐任务成功、local-only cleanup、unsupported | Restore 将任务展平成 handles，仅提前处理空任务 | 不符合 |
| `controllerSelfSyncPending` 与 `isSynced` 联合真值 | Restore 最终仅按 handle failure 写 `isSynced` | 不符合 |
| cleanup 成功后持久化 pending 变化 | 非空 cleanup 成功未按 task 调用 `clearPending` | 不符合 |
| EFC 专用失败 Retry | Restore 统一进入普通 `.devices` 同步 | 不符合 |
| 综合状态按设备返回 Working Mode 解释 | 属于恢复后的监控链；只要绑定、publication 和 proxy filter 正确即可复用 | 恢复成功后符合 |

EFC Restore 下线后，现有功能至少发生了这些直接影响恢复的变化：

- 单一 enabled 语义升级为四态 Working Mode；
- 引入 `controllerSelfSyncPending`，`isSynced` 不再能单独代表控制器与设备已对齐；
- 关联组同步范围收敛为 Light，新增 Node/Group mutation 补订阅与 pending cleanup；
- EFC 任务接入当前 `SyncDevicesViewController(.emergencyFire)`，支持 task 粒度状态、local-only task、unsupported 和正确持久化；
- 综合状态改为按设备返回的 enable mode 和 active bit 映射；
- SceneRecall 状态事件改为全局分发并依赖内部 publish group/proxy filter。

因此方案 B 必须复用当前 EFC 专用同步流程，不能恢复旧的“Fast Add 中展平全部 EFC handles”执行方式。

## 5. 方案比较

### 方案 A：仅解除 EFC 过滤

改动最少：放开 `.emergencyController` 并反转现有 shell 合约。

优点：工作量最小，现存休眠代码可以立即被调用。
缺点：会放开所有 EFC 产品；沿用失真的同步收口和错误的失败重试路由；无法可靠证明恢复完成。
结论：不推荐。

### 方案 B：启用所有已注册 EmergencyController，并复用权威 EFC 同步流程

保持 Restore Device Data 统一入口，但把恢复分成两阶段：

1. Restore 页通过设备配置注册表按 CID/PID 精确解析所有 `.emergencyController`，完成候选身份校验、Provision/Key Bind 和本地 `DeviceEmerFireData` 地址迁移；EFC 状态保持 Adding/Needs Sync，不提前宣告成功。
2. Provision 成功后，由 Restore 页按队列进入现有 `SyncDevicesViewController(.emergencyFire)`，让当前权威 planner/执行器同步 publication、vendor 参数、关联灯订阅与 pending cleanup，并复用逐任务状态、失败选择和 Retry。
3. EFC 专用同步全部成功后才把该设备标记为 Restore success；失败或用户中止则保留 `syncFailed` 和未同步真值。
4. 普通设备继续走现有恢复链，不受影响；Gateway 入口继续只显示 Gateway。

优点：复用当前已经维护的 EFC 同步真值与 UI；避免复制任务执行器；风险和改动面可控。
缺点：恢复 EFC 时会增加一个 Sync device(s) 阶段；多个 EFC 需要顺序排队。
结论：**推荐。**

### 方案 C：抽取无 UI 的共享 EFC Task Executor

把 EFC planner 的任务执行、pending 清理、controller self 状态收口和 retry 从 SyncDevices 页面抽成共享协调器，Restore 页在原页面内静默执行。

优点：Restore UX 最连贯，长期架构最统一。
缺点：会重构当前稳定的 EFC 同步页和 Restore 页，测试与回归范围明显扩大，不符合本次“所有已注册 EFC Controller 可恢复”的聚焦范围。
结论：本次不推荐，可作为后续平台化演进。

## 6. 推荐方案 B 的开发规划

### 阶段 1：候选能力策略与测试

- 新增可独立测试的 Restore candidate policy，不再把所有判断埋在 ViewController。
- 新增按 `companyId + productId` 查询当前 `supportDeviceInfos` 的 EFC identity resolver；只有 `deviceCategory` 映射为 `.emergencyController` 才是可恢复 EFC。
- 不维护 EFC PID 白名单；服务器后续新增的 EmergencyController 配置自动进入支持范围。
- `.currentSpaceNonGateways` 允许所有已注册 EFC，仍拒绝 Gateway；`.all` 同样允许；`.gatewaysOnly` 行为不变。
- 扫描回调同时校验历史 Node 和当前 ProvisioningDevice：两者均解析为 EFC，且 CID/PID 完全一致。
- 如果广播缺少 CID/PID、设备配置不存在、类别不是 EmergencyController 或历史/当前身份不一致，则不进入恢复；不降级为普通恢复。
- 覆盖多个不同 CID/PID EFC 注册项、RSSI、Space、specified、already restored、未知产品和身份不匹配用例。

### 阶段 2：EFC 本地数据迁移收口

- 复用 `DeviceEmerFireStore.restoreDevice`，保留名称、publish group、Gateway 选项和完整 configuration。
- 明确旧地址记录只迁移一次，新地址不得生成第二条默认 EFC。
- 迁移后保持 `isSynced = false`、`controllerSelfSyncPending = true`，直到专用同步完成。
- 若找不到 Space、无法创建/恢复 publish group 或缺少必要模型，标记为 `syncFailed`，不回退成普通设备成功。
- 所有 EFC 类型在 Composition 完成后统一验证当前功能所需的 Scene Client 与 Sunricher Vendor Model；缺失时展示 Repair/Needs Attention 真值，不伪造支持成功。

### 阶段 3：Provision 与专用同步分阶段执行

- EFC 在 Fast Add 附加消息阶段不再使用休眠的扁平 planner 发送方式。
- Provision/Key Bind 成功后收集待同步的 EFC controller，设备状态继续显示处理中。
- 批次 Provision 完成后按 EFC 逐个启动现有 `.emergencyFire` 同步流程。
- 同步成功回调后更新 Restore 设备状态并处理下一个 EFC；失败/中止保留未同步状态，允许在专用页 Retry。
- 普通设备的 deferred restore、BPS、Gateway、Dongle 流程保持现状。

### 阶段 4：恢复结果与重试路由

- Restore 的 Success 必须同时满足 Provision 成功和 EFC 专用同步成功。
- EFC 失败不得进入普通 `.devices` Retry。
- 若同一批次还有普通设备同步失败，先完成 EFC 专用队列，再进入现有普通同步页；两类结果分别保留。
- 自动 OTA 恢复的 `specified` 模式同样支持所有已注册 EFC Controller；自动流程失败时保留手动专用 Retry 入口。

### 阶段 5：合约与验证

- 更新 `check_efc_controller_flows.sh`：从“全部排除 EFC”改为“允许所有注册为 EmergencyController 的匹配身份，且必须走专用同步”。
- 新增 Restore candidate policy 单元测试。
- 新增 EFC identity resolver 单元测试，至少使用两个不同 CID/PID 的 EmergencyController fixture，证明没有硬编码 `0x2131`。
- 新增 EFC 本地记录迁移测试：旧地址迁移、配置完整保留、重复记录去除、缺失旧配置的明确行为。
- 新增恢复状态 reducer/coordinator 测试：Provision 成功但同步失败不得显示成功；Retry 成功后才完成。
- 运行 EFC 现有 contract、相关 focused tests、`git diff --check`。
- 直接使用 iPhoneOS 构建验证四个共享 target：SunSmart、Archipelago、SLG Sync Plus、SylSmart。

## 7. 真机验收矩阵

静态测试和 build 不能替代真实 EFC/Mesh 验收。至少需要覆盖：

1. 同一台 EFC 重置后，可按 MAC/旧 MAC 扫到；当前内置 `0x0A78/0x2131` 必测，并为另一种 EmergencyController 产品执行同样验收。
2. 不同 EFC CID/PID 即使发生异常 MAC 命中，也不可把旧配置迁移到新产品。
3. 无关联组、单关联组、多关联组三种配置。
4. Disabled、Power Loss only、Fire Alarm only、两者同时启用。
5. Restore Auto、Set Brightness（含 0%）、None；恢复延迟与发送次数保持。
6. 原内部 publish group 存在与缺失两种情况；恢复后不产生重复 EFC 卡片或重复 virtual group。
7. 关联灯全部在线、部分离线；失败任务显示原因并可单项/选中 Retry。
8. 成功后验证 EFC Scene Client publication、`0x4D/03/05/06/07` 参数、灯模型订阅及 App/网关状态事件链路。
9. BLE OTA 自动恢复的 specified 模式。
10. App 重启和云同步后，EFC 名称、绑定地址、完整 configuration、`controllerSelfSyncPending` 与 `isSynced` 真值保持一致。

## 8. 本次未做事项

- 未修改任何业务代码、测试或现有合约。
- 未执行完整 iPhoneOS build，因为本轮只有调查与方案规划，没有代码差异。
- 已执行当前 EFC controller flow contract，结果通过，证明当前“Restore 排除 EFC”行为仍被代码与合约共同锁定。
- 未进行真实 EFC、真实 Mesh、网关或服务器验收。

## 9. 修订后待确认

方案 B 保持不变，但支持范围和身份策略更新为：

- 支持当前设备配置注册表中所有 `deviceCategory == EmergencyController` 的产品，不硬编码 CID/PID 白名单；
- 只允许同一历史设备身份恢复：当前广播 CID/PID 必须与历史 Node 一致；跨 EFC 产品绑定继续使用现有 Link/Add 流程，不属于 Restore；
- 同时覆盖 Space 手动 Restore 与 BLE OTA specified 自动恢复；
- Site Gateway Restore 入口保持不变；
- EFC Provision 后必须走当前 `.emergencyFire` 专用同步链；
- EFC 专用同步完成前不显示 Restore success。
