# SLG Sync Plus Space Mesh 上下文竞态修复开发计划

## 1. 计划目标

修复以下已通过真机日志确认的问题：Gateway 详情关闭触发的 Site 静默刷新，在 Space 已进入后完成并抢占全局 Mesh 上下文，导致 Products 显示 `No devices`、Timed 从服务器和本地均为 1 条变成运行时 0 条。

本计划供用户确认。确认前不修改业务代码。

## 2. 推荐实施范围

推荐采用“聚焦修复 + 同类作用域保护”，共修改两个现有业务文件，不新增本地化、资源、依赖、Auth 信息或 target 配置。

### 2.1 修改文件

1. `SunSmart/Main/Site/Controller/SiteViewController.swift`
2. `SunSmart/Common/Data/ImportData.swift`

### 2.2 新增测试文件

1. `Tests/Site/SiteSpaceMeshContextOwnershipContractTests.swift`
2. `scripts/check_site_space_mesh_context_ownership.sh`

测试文件不加入 App target，不修改 `SunSmart.xcodeproj`。

## 3. 业务代码改动规划

### 3.1 移除 Site Load 完成回调的全局网络切换

当前 `performSiteLoad(...)` 在 `site.update(...)` 完成后检查当前网络是否为 Primary；如果不是，就调用 `setMeshNetworkConnected(...)` 切到 Site Primary。

计划：

1. 删除该完成回调内的 Primary 网络切换。
2. 保留 Site 数据解析、落盘、Gateway 时间信息恢复、`setupData()` 和后续云同步判断。
3. 不增加“延迟后再切换”或“发现 Space 为空再恢复”等补偿逻辑。

理由：

- 异步 Site 请求不拥有当前页面的运行时 Mesh 上下文；
- `setupData()` 已通过 `sitePrimaryMeshNetwork()` 显式读取 Site Primary 数据，无需替换全局 Manager；
- Site 真正重新可见时，现有 `viewDidAppear` 已负责切到 Primary；
- Space 进入时，现有 `SpaceViewController.setNetworkConnected()` 负责切到 Space 子网。

修复后的所有权规则：

| 事件 | 是否允许切换全局 Mesh | 目标 |
| --- | --- | --- |
| Site HTTP 响应完成 | 否 | 无 |
| Site `viewDidAppear` | 是 | Site Primary |
| Space `setNetworkConnected()` | 是 | 当前 Space 子网 |
| 后台/隐藏 Site 的静默刷新 | 否 | 无 |

### 3.2 限制 Site 导入复用全局网络的条件

当前 `SiteData.update(...)` 只比较 Mesh UUID。由于同一 Site 下的 Primary 和各 Space 子网共享 Mesh UUID，Site 导入可能把当前 Space Manager 误当成 Site Primary 网络。

计划：

1. 只有当前 Manager 同时满足以下条件时，Site 导入才允许复用：
   - Mesh UUID 等于当前 Site；
   - 当前 Network ID 等于 `site.meshNetworkId`；
   - 当前 Key 为 Primary。
2. 条件不满足时，显式从数据库加载 `site.meshUUID + site.meshNetworkId` 对应的 Primary Mesh。
3. 保留现有 Site、Space、Gateway 导入和时间戳决策，不修改服务器数据权威规则。

该修改防止另一种完成顺序：Space 已先接管全局 Manager，随后 Site 导入才开始，并错误地在 Space 网络上执行 Gateway/Primary 数据处理。

### 3.3 限制 Space 定时写入全局 Manager 的条件

当前 Space 导入写入 `MeshNetworkManager.instance.schedules` 时只比较 Mesh UUID。同一 Site 的多个 Space 共享 UUID，因此导入 Space B 可能覆盖当前 Space A 的运行时定时数组。

计划：

1. 只有当前 Manager 的 Mesh UUID 和 Network ID 都匹配正在导入的 Space，才更新全局 `schedules`。
2. 无论是否为当前 Space，定时仍按现有逻辑写入对应 Space 的数据库。
3. 不修改 Schedule 模型、协议、启停、同步或设备侧配置流程。

## 4. 本次明确不做

为了保持改动聚焦，以下内容不进入本次修复：

1. 不重构整个 `performSiteLoad(...)` 为新的 Coordinator。
2. 不增加 Site 请求取消、Generation 或完整会话状态机；如后续发现旧请求导致 HUD/导航乱序，再单独处理。
3. 不将 Site/Space 全量导入改造成事务或 Actor 串行队列。
4. 不重构 Products、Scenes、Timed 的全局 Manager 数据源架构。
5. 不修复 `EmptyDataView.width == 0` 的 Auto Layout 警告。
6. 不修改 Gateway、BLE、Mesh Proxy、TimeSet、场景或定时业务行为。
7. 不修改本地化、资源、target 配置或依赖。
8. 不在本次功能修复中处理调试日志的凭据脱敏；该项应作为独立安全任务处理。

## 5. 自动化测试规划

### 5.1 新增 Mesh 上下文所有权契约

新增 `SiteSpaceMeshContextOwnershipContractTests`，静态验证以下不可回退约束：

1. `performSiteLoad(...)` 内不再调用 `setMeshNetworkConnected(...)`。
2. `SiteViewController.viewDidAppear` 仍保留 Site Primary 切换和切换后的 `setupData()`。
3. `SpaceViewController.setNetworkConnected()` 仍使用 `space.meshUUID + space.meshNetworkId`。
4. `SiteData.update(...)` 复用当前网络时必须同时校验 Mesh UUID、Primary Network ID 和 `isPrimary`。
5. `SpaceData.update(...)` 写入全局 `schedules` 时必须校验 Mesh UUID 和 Space Network ID。
6. `loadGatewaysData()` 继续通过 `sitePrimaryMeshNetwork()` 和 `model.resolveNode(in:)` 显式解析 Gateway。

新增 `scripts/check_site_space_mesh_context_ownership.sh` 编译并运行该契约。

### 5.2 现有回归契约

同时运行：

1. `zsh scripts/check_site_space_mesh_context_ownership.sh`
2. `zsh scripts/check_site_gateway_online_state.sh`
3. `zsh scripts/check_site_sync_gateways.sh`
4. `zsh scripts/check_timed_scheduler_persistence.sh`
5. `zsh scripts/check_timed_scheduler_single_owner.sh`
6. `git diff --check`

目的：避免移除 Primary 切换后回归 Gateway 展示、Sync Gateways 权限/数据、Timed 持久化和 Scheduler 单一所有权。

## 6. 构建验证规划

相关业务文件由四个品牌 target 共用，使用项目要求的 generic iPhoneOS Debug、关闭代码签名方式分别构建：

1. `SunSmart`
2. `Archipelago`
3. `SLG Sync Plus`
4. `SylSmart`

不使用 Simulator，不使用 shell 包装或日志重定向。

构建只能证明编译集成，不证明竞态、BLE、Mesh Proxy、服务器回读或 UI 真机表现。

## 7. 真机验收规划

### 7.1 原问题复现路径

使用本次已复现的数据集，至少循环 20 次：

1. 打开 Gateway 详情；
2. 立即关闭；
3. 立即进入 `Space 1`；
4. 快速切换 Products、Groups、Scenes、Timed、More；
5. 确认 Products 始终显示 3 个节点；
6. 确认 Timed 始终显示 1 条定时；
7. 确认旧 Site 响应完成后当前 Network ID 仍等于 `Space 1.meshNetworkId`。

### 7.2 返回 Site 验收

1. 从 Space 返回 Site；
2. 确认 `viewDidAppear` 正常切回 Primary；
3. 确认 Gateway1 仍存在、名称和在线状态正确；
4. 再次进入 Space，节点和定时仍正常。

### 7.3 响应顺序矩阵

至少覆盖：

1. `/siteprops` 先于 `/spaceprops` 完成；
2. `/spaceprops` 先于 `/siteprops` 完成；
3. Site 导入先开始、Space 网络后加载；
4. Space 网络先加载、Site 导入后开始；
5. 时间戳相同并跳过 Space 导入；
6. 服务器 Space 时间戳更新、需要实际导入。

### 7.4 运行链路验收

1. Space 的 BLE/Mesh Proxy 不被后台 Site 刷新关闭或替换；
2. Heartbeat 和编辑权限校验保持正常；
3. Gateway 详情打开/关闭正常；
4. Site Gateway 静默刷新仍能更新云端数据，但不接管 Space 网络；
5. 不出现新的场景、定时或节点串 Space。

## 8. 风险与控制

### 8.1 Gateway 展示回归风险

被移除的网络切换最初与 Gateway 节点读取修复有关。当前代码后来已经引入 `sitePrimaryMeshNetwork()` 显式加载 Primary Mesh，因此理论上不再依赖全局切换。

控制措施：

- 保留并强化现有 Gateway Online State 契约；
- 真机验证 Site 返回、Gateway 新增/刷新和在线状态；
- 四品牌构建。

### 8.2 导入数据并发风险

本次只修正网络选择条件，不改变 TaskGroup 和删除后重建流程。更完整的导入串行化仍需单独设计。

控制措施：

- 覆盖两种请求完成顺序；
- 覆盖需要实际应用服务器新数据的场景；
- 不把自动化契约当作真机导入验收。

### 8.3 多品牌风险

`SiteViewController.swift` 和 `ImportData.swift` 为共享文件，功能语义会同时影响四品牌。

控制措施：

- 不加入 `#if SLGSync` 特例；
- 四品牌构建；
- 至少在 SLG Sync Plus 完成本次真实时序验收。

## 9. 交付内容

若用户确认本计划，实施后交付：

1. 两个现有业务文件的聚焦修改；
2. 一个新的 Mesh 上下文所有权契约测试；
3. 一个聚焦检查脚本；
4. 现有相关契约结果；
5. 四品牌 generic iPhoneOS 构建结果；
6. 实现总结 Markdown；
7. 明确列出仍需真机验证的项目。

不自动 commit、push 或 merge。

## 10. 待用户确认

建议批准本计划的推荐范围：

- 移除后台 Site Load 的全局 Primary 切换；
- 修正 Site 导入和 Space 定时的 Network ID 作用域；
- 新增聚焦契约并验证现有 Gateway/Timed 契约；
- 完成四品牌 generic iPhoneOS 构建；
- 暂不实施请求会话重构、导入事务化和 Empty UI 布局修复。

