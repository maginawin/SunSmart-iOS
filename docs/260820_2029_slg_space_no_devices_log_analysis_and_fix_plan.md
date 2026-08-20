# SLG Sync Plus Space No devices 日志分析与修复规划

## 1. 分析范围

测试通过以下路径复现：打开 Gateway 详情页，立即关闭，立即进入 `Space 1`，随后切换 Space 内页面，出现 `No devices`，Timed 页面显示 0 条定时。

本次根据用户提供的运行日志和当前源码进行分析与修复规划，不修改业务代码。

## 2. 结论

该日志已将此前的高概率判断提升为**基本确认的客户端根因**：

> Gateway 详情关闭后启动的 Site 静默刷新，在 `Space 1` 已经加载完子网后才完成；其完成回调无条件将全局 `MeshNetworkManager` 切换到 Site Primary 网络，导致当前 Space 页面继续从错误的全局网络读取产品、场景和定时。

服务器没有返回空数据，本地 Space 数据也没有在本次导入中被清空。`No devices` 是**运行时全局 Mesh 上下文被抢占**后的展示结果，而不是本地数据库或服务器数据被删除。

## 3. 日志证据链

### 3.1 Gateway 详情关闭触发 Site 静默刷新

日志先进入 `WiFiGatewayViewController`，随后立即点击 Space 卡片。此时同时发出：

- `spaceInfo`：`/sitespace/get/spaceprops`；
- `siteInfo`：`/sitespace/get/siteprops`。

这与当前源码一致：Gateway 详情关闭会调用 `finishGatewayDetailPresentation(...)`，再调用 `.silentGatewayReconcile` Site 刷新：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:880-888`。

### 3.2 Space 和 Site 响应都包含正确数据

脱敏后的关键计数如下：

| 数据来源 | Nodes | Scenes | Groups | Schedules |
| --- | ---: | ---: | ---: | ---: |
| `/spaceprops` | 3 | 0 | 0 | 1 |
| `/siteprops` 中的 `spaces[0]` | 3 | 0 | 0 | 1 |
| 本地导入前汇总 | 3 | 0 | 0 | 1 |

两个响应的 Space `updateTimestamp` 与本地 `lastUpdate` 相同。两次 `PJSpaceCountProbe` 最终都打印：

- `phase=skipped`；
- `note=serverUpdateTimestampNotNewer`。

因此本次 `SpaceData.update(...)` 没有执行删除节点、场景或定时的覆盖导入。服务器空数组和导入清空路径可以从本次根因中排除。

### 3.3 Site 导入和 Space 网络加载发生交错

关键时间顺序：

1. Site 导入开始：`1787228852.105767`；
2. Space 网络加载开始：`1787228852.108303`；
3. Space 网络基础数据加载完成：`1787228852.135755`；
4. Space 扩展数据加载完成：`1787228852.136116`；
5. Site 导入完成：`1787228852.184688`。

也就是说，`Space 1` 子网已完成加载约 49 ms 后，后台 Site 导入才结束。

### 3.4 Site 完成回调随后切回 Primary 网络

`performSiteLoad(...)` 在 `site.update(...)` 完成后执行：

- 如果当前 Mesh UUID 不属于 Site，或当前 Network Key 不是 Primary；
- 就调用 `setMeshNetworkConnected(...)`，目标为 `site.meshNetworkId`，`connected: false`。

位置：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:598-600`。

此时 `Space 1` 已经加载完成，当前 Key 必然是 Space 子网 Key，不是 Primary，因此该条件成立。SDK 随即替换全局 `meshNetworkManager`：

- SDK `MeshLibManager.swift:183-228`。

该 Site Primary 切换路径没有调用 `loadExtensionData(...)`，新 Manager 的关联 `schedules` 默认是空数组。

### 3.5 Timed 日志直接证明全局 Manager 已不是 Space 数据上下文

服务器、本地 Probe 都确认 Space 有 1 条定时，但进入 Timed 页面后日志显示：

- 当前页面参数仍是 `Space 1` 的 Space ID 和子网 ID；
- `schedule count: 0`。

Timed 的诊断方法直接读取 `MeshNetworkManager.instance.schedules`：

- `SunSmart/Main/Timed/Controller/TimedViewController.swift:313-317`。

因此页面持有正确的 `SpaceData`，但全局 Manager 已被替换为另一个上下文。这是本次根因的直接证据。

### 3.6 No devices 与切回 Primary 的表现一致

产品页面最终读取全局 Manager 的 `realNodes`。Site Primary 网络主要承载 Site/Gateway 数据，不是 `Space 1` 的 3 个产品子网；切回 Primary 后 Lights、Sensors 等分类自然得到空列表。

重新进入 Space 会再次执行 `SpaceViewController.setNetworkConnected()`，切回 `space.meshNetworkId` 并加载扩展数据，因此产品和定时恢复。这也进一步说明数据没有被删除。

## 4. 无关或次级日志

### 4.1 Auto Layout 警告不是根因

`EmptyDataView.width == 0` 与左右内边距约束冲突，是列表变空并进入 Empty UI 后、分页页面布局尚未取得有效宽度时产生的次级布局警告。它不会清空 Mesh 数据，也不能解释服务器 1 条定时变成全局 Manager 0 条。

可以单独建立 UI 修复任务，但不应与本次 Mesh 上下文修复混在同一改动中。

### 4.2 `XPC connection invalid` 不是当前证据链的一部分

该日志没有与节点计数、Network Key 或 HTTP 失败形成关联，不应据此判断 BLE、Mesh Proxy 或服务器异常。

### 4.3 Heartbeat 成功不代表 Mesh 数据上下文正确

Heartbeat 请求成功只证明 Space 在线占用/权限心跳完成，不验证当前全局 `MeshNetworkManager` 是否仍指向 Space 子网。

## 5. 源码层根因拆分

### 5.1 直接根因：Site 完成回调越权接管全局网络

Site 刷新的职责应是更新 Site/Space/Gateway 云端数据。当前完成回调额外执行全局 Primary 网络切换，但此时 Site 页面可能已不再是顶层控制器。

该网络切换缺少以下条件：

- 当前可见控制器仍为 `SiteViewController`；
- 当前网络上下文仍由 Site 页面拥有；
- 请求仍是最新 Site Load 会话；
- 用户尚未进入 Space。

### 5.2 触发窗口：新静默刷新允许用户继续导航

关闭 Gateway 详情后的 `.silentGatewayReconcile` 不显示 HUD，因此用户可以在请求未完成时进入 Space。该入口使原有的无条件 Primary 切换更容易稳定暴露。

### 5.3 当前 Primary 切换已经没有 Gateway 展示上的必要性

`setupData()` 的 Gateway 加载已通过 `sitePrimaryMeshNetwork()` 获取明确的 Site Primary Mesh：

- 当前 Manager 正好是 Site Primary 时复用；
- 否则直接从数据库加载 `site.meshNetworkId` 对应的 Primary Mesh。

位置：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:1322-1333`；
- `SunSmart/Main/Site/Controller/SiteViewController.swift:1415-1432`。

因此 Site 请求完成后不必为了刷新 Gateway UI 强制替换全局 Manager。

### 5.4 相邻风险：Site 导入选择当前网络时只比较 Mesh UUID

`SiteData.update(...)` 当前只要全局网络 `meshUUID` 等于 Site 的 `meshUUID`，就把它作为 Site 导入网络，没有确认当前 Key 是 Site Primary：

- `SunSmart/Common/Data/ImportData.swift:166-168`。

同一 Site 的所有 Space 共享 Mesh UUID、使用不同子网 Key。若 Site 导入在 Space 已接管全局 Manager 后才开始，可能错误使用 Space 网络执行 Site/Gateway 导入。这次日志中的 Space 数据因时间戳相同而跳过，没有暴露该破坏路径，但它属于同一网络作用域问题。

### 5.5 相邻风险：Space 定时全局写入只比较 Mesh UUID

`SpaceData.update(...)` 更新 `MeshNetworkManager.instance.schedules` 时只比较 Mesh UUID，没有比较当前子网 ID：

- `SunSmart/Common/Data/ImportData.swift:1620-1622`。

并发导入同一 Site 的多个 Space 时，其他 Space 的定时可能覆盖当前全局 Manager。该风险不是本次日志中的直接原因，但应进入后续隔离任务。

## 6. 推荐修复方案

### 6.1 第一阶段：聚焦修复本次确认问题

推荐将 Site 和 Space 的全局网络所有权收敛到页面生命周期边界：

1. 删除 `performSiteLoad(...)` 完成回调中的无条件 Site Primary 网络切换。
2. Site 数据刷新继续完成云端解析、必要的本地落盘和 `setupData()`；Gateway 解析继续使用现有 `sitePrimaryMeshNetwork()` 的显式 Primary 数据源。
3. Site Primary 的运行时切换只保留在 `SiteViewController.viewDidAppear`，因为此时 Site 确实重新取得顶层页面所有权。
4. Space 子网切换只保留在 `SpaceViewController.setNetworkConnected()`，因为此时 Space 取得运行时所有权。
5. 增加 DEBUG 诊断断言：Site Load 完成时如果顶层是 Space，不允许发生 Primary 切换，并记录 Site/Space/当前 Network ID。

这是改动最小、与日志根因直接对应的方案。现有 `sitePrimaryMeshNetwork()` 已提供隐藏 Site 刷新 Gateway 数据所需的非全局加载能力。

### 6.2 第二阶段：防止过期 Site 请求执行 UI 副作用

为 `performSiteLoad(...)` 增加 Load Session/Generation：

1. 每次 Site Load 生成唯一会话标识；
2. 新请求开始时使旧请求的 UI 会话失效；
3. 请求可继续完成安全的数据解析/落盘；
4. `title`、HUD、Entry Sync 展示、导航、`setupData()` 等 UI 副作用只由最新且仍属于可见 Site 的会话执行；
5. 进入 Space 时显式失效当前 Site UI 会话，不把“对象仍存活”当作“页面仍拥有 UI”。

该阶段可以防止多个 Site 请求乱序返回，但不应以简单取消网络请求替代数据作用域修复，因为已开始的导入任务未必响应取消。

### 6.3 第三阶段：修正导入网络作用域

建议作为独立、紧邻的加固任务：

1. `SiteData.update(...)` 只有在当前网络同时匹配 Site Mesh UUID 和 Primary Key 时才复用全局网络，否则显式加载 `site.meshNetworkId`。
2. `SpaceData.update(...)` 只有在 Mesh UUID 和 `meshNetworkId` 都匹配时，才写入全局 `schedules` 等运行时扩展数据。
3. 为同一 Mesh UUID 下的 Site/Space 导入建立串行或事务边界，避免多个 Task 同时删除和重建网络集合。
4. 长期逐步让产品、场景、定时页面使用明确的 Space 上下文，而不是无条件读取全局单例。

第三阶段影响范围大于本次直接修复，不建议未经专项测试直接与第一阶段混合提交。

## 7. 不推荐方案

### 7.1 在 Space 页面发现数据为空后自动重连

这会掩盖 Site 越权切换，造成 Site/Space 两边反复抢占全局 Manager，并可能打断 BLE/Mesh Proxy 会话。

### 7.2 只给 Site 静默请求增加固定延时

延时只能改变出现概率，不能建立网络所有权规则；不同网络速度下仍会复现。

### 7.3 只刷新 Products、Scenes、Timed UI

页面刷新仍会读取错误的全局 Manager，只会稳定显示空状态。

### 7.4 将服务器数据重新写入本地

日志已经证明服务器和本地汇总均为 3 个节点、1 条定时；回写不能修复运行时上下文，还可能覆盖用户数据。

## 8. 测试与验收规划

### 8.1 自动化契约

1. Site Load 完成且 Site 为顶层：允许 Site 生命周期切换到 Primary。
2. Site Load 完成但 Space 为顶层：不得调用 Primary 网络切换。
3. Gateway Detail 关闭触发静默刷新，随后进入 Space：旧 Site 响应完成后当前 Network ID 仍等于 `space.meshNetworkId`。
4. 多个 Site Load 乱序完成：只有最新可见会话执行 UI 副作用。
5. 返回 Site：`viewDidAppear` 正常切回 Primary，Gateway 仍能解析和显示。

### 8.2 导入作用域测试

1. 当前 Manager 为 Space 子网时执行 Site 更新，不得把 Gateway/Primary 数据写入 Space 网络。
2. 当前为 Space A 时导入 Space B，不得覆盖全局 `schedules`。
3. 服务器时间戳相同、数据一致时保持跳过；不触发运行时网络切换。
4. 服务器数据确实更新时，导入结束后节点、场景、定时数量正确，不向 UI 暴露永久空状态。

### 8.3 四品牌构建

相关文件由多个品牌 target 共用，需要按项目规则验证：

- `SunSmart`；
- `Archipelago`；
- `SLG Sync Plus`；
- `SylSmart`。

使用 generic iPhoneOS Debug、关闭代码签名进行构建，不使用 Simulator。

### 8.4 真机回归矩阵

1. Gateway Detail → 关闭 → 立即进入 Space，循环 20 次。
2. Site 首次加载 → 快速进入 Space。
3. 弱网下 `/siteprops` 晚于 `/spaceprops` 返回。
4. Space 内切换 Products、Groups、Scenes、Timed、More。
5. 返回 Site 后 Gateway、Space 列表正常。
6. 有 3 个节点和 1 条定时的本次数据集仍显示 3/1。
7. BLE/Mesh Proxy 不因后台 Site 刷新断开或切换网络。

自动化和构建只能验证代码契约与编译，不替代上述真机时序、BLE/Mesh Proxy 和 UI 验收。

## 9. 安全说明

本次日志原文包含可用于鉴权或设备接入的敏感字段，包括请求头凭据、Mesh/App/Device Key 和 Gateway MQTT 凭据。分析文档未复制这些值。

建议：

1. 不要将原始日志直接粘贴到公开 Issue、聊天群或代码仓库；
2. 对外共享前统一脱敏；
3. 如果这些是有效环境凭据且日志已经进入非受控渠道，应按后台和 Gateway 运维流程评估轮换或吊销；
4. 后续诊断日志只保留 endpoint、请求编号、时间戳、ID 后四位、Network 类型和数组计数。

## 10. 建议实施范围

本次建议先批准以下聚焦范围：

1. 移除 Site Load 完成回调对全局 Primary 网络的越权切换；
2. 增加 Site Load 会话有效性和当前页面所有权保护；
3. 添加本次 Gateway Detail → Space 的确定性回归契约；
4. 完成四品牌 generic iPhoneOS 构建；
5. 保留导入作用域全面加固为紧随其后的独立任务。

在用户确认前，不实施业务代码修改。

