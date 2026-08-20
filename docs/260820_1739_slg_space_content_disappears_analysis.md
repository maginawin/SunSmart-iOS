# SLG Sync Plus Space 内容进入后消失问题分析

## 1. 问题描述

测试反馈：进入 `Space1` 后，产品、场景和定时最初能够正常显示，约一秒后同时消失；退出并重新进入 `Space1` 后恢复正常。

本次仅进行当前源码静态分析，未修改业务代码，也未取得复现设备日志、服务器响应或真实运行时网络上下文快照。

## 2. 结论

最可能的主因是 **Site 页面异步刷新与 Space 页面进入流程发生竞态，已退到导航栈后台的 `SiteViewController` 在请求完成后，把全局 Mesh 上下文从 `Space1` 子网切回了 Site 主网**。

产品、场景和定时页面并没有持有各自 Space 的独立数据源，而是共同读取 `MeshNetworkManager.instance`。全局上下文一旦切回主网，这三个页面后续刷新时看到的就是主网数据，通常为空或不属于 `Space1`，因此表现为同时消失。

重新进入 `Space1` 时，`SpaceViewController` 会再次把全局上下文切换到 `Space1.meshNetworkId` 并加载扩展数据，因此列表恢复。这与测试描述的“一次进入异常、重新进入正常”高度吻合。

该结论属于**源码证据支持的高概率根因**，但在取得复现时的请求时序和 `currentNetworkKey` 日志前，不应称为已完成运行时实证。

## 3. 主因证据链

### 3.1 Site 页面进入后立即发起异步刷新

`SiteViewController.viewDidLoad()` 在网络可用且 Site 已上传云端时调用 `loadSiteRequest()`：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:175-176`

该请求从 `/sitespace/get/siteprops` 获取 Site 详情，随后通过异步 `Task` 调用 `site.update(...)`：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:482-545`

### 3.2 用户点击 Space 时又启动一条独立异步链路

联网状态下点击 Space 会调用 `loadSpaceReqeust(space:)`：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:2684-2685`

Space 请求成功后先调用 `space.update(...)`，然后将 `SpaceViewController` 压入导航栈：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:1218-1238`
- `SunSmart/Main/Site/Controller/SiteViewController.swift:2693-2719`

因此同时存在两条可能交错完成的异步链路：

1. Site 页面进入时启动的 Site 详情刷新；
2. 用户点击 `Space1` 后启动的 Space 详情刷新和页面进入。

### 3.3 Site 请求完成回调没有校验页面是否仍然可见

Site 导入任务只检查 `self` 是否存在和任务是否被取消，没有检查：

- `SiteViewController.view.window != nil`；
- 当前顶层页面是否仍为 Site；
- 当前全局 Mesh 上下文是否已被后续的 Space 页面接管；
- 本次响应是否已经过期。

`SiteViewController` 被压在导航栈下方时仍然存活，因此其请求和导入任务会继续执行。

### 3.4 后台 Site 回调会把当前 Space 子网切回 Site 主网

Site 导入结束后执行以下逻辑：

- 如果当前 Mesh UUID 不是该 Site，或当前 Network Key 不是 Primary；
- 则调用 `setMeshNetworkConnected(...)`，目标为 `site.meshNetworkId`，且 `connected: false`。

位置：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:598-600`

进入 `Space1` 后，当前 Network Key 正常应为 `space.meshNetworkId`，通常不是 Primary。因此后台 Site 回调完成时，`!currentNetworkKey.isPrimary` 必然成立，并主动把全局上下文切回 Site 主网。

SDK 的 `setMeshNetworkConnected(...)` 会加载目标网络、设置 `currentNetworkKey`，并替换 `MeshLibManager` 当前持有的 `meshNetworkManager` 和 `connection`：

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:183-228`

这不是单纯刷新 Site UI，而是实际改写全局 Mesh 数据上下文。

### 3.5 产品、场景和定时共同读取全局上下文

产品页面最终读取全局 Manager 的 `realNodes`；场景页面的 `visibleScenes` 直接读取 `MeshNetworkManager.instance.scenes`；定时页面的 `updateUI()` 直接读取 `MeshNetworkManager.instance.schedules`：

- SDK `MeshLibManager.swift:1163-1175`：`realNodes` 来自当前 `meshNetwork`；
- `SunSmart/Main/Scene/Controller/ScenesViewController.swift:47-48`；
- `SunSmart/Main/Timed/Controller/TimedViewController.swift:182-191`。

因此全局上下文被切回主网后，三个功能页会同时失去 `Space1` 数据。该共同依赖也解释了为什么不像单一页面刷新错误。

### 3.6 重新进入会恢复上下文

`SpaceViewController.setNetworkConnected()` 每次进入 Space 都会再次使用 `space.meshUUID + space.meshNetworkId` 设置当前网络，加载扩展数据后重建分页控制器：

- `SunSmart/Main/Space/Controller/SpaceViewController.swift:667-706`

第一次进入时尚未完成的 Site 请求通常已经在异常出现前完成；第二次进入后没有同一条旧 Site 回调再次把上下文切走，所以数据恢复。

## 4. 高概率触发时序

1. 用户进入 Site 页面，Site 自动刷新请求 A 发出。
2. 本地缓存已能显示 `Space1`，用户很快点击进入。
3. Space 请求 B 完成，`Space1` 数据导入并进入 Space 页面。
4. `SpaceViewController` 把全局 Mesh 上下文设置为 `Space1` 子网，产品、场景和定时正常显示。
5. 较慢的 Site 请求 A 完成，后台 `SiteViewController` 执行 Site 导入。
6. Site 导入后的逻辑发现当前 Key 不是 Primary，于是把全局上下文切回 Site 主网。
7. Space 子页面在页面切换、状态刷新或 `viewWillAppear` 时重新读取全局 Manager，显示为空。
8. 用户退出再进入 `Space1`，上下文重新切回 Space 子网，数据恢复。

网络速度、Site 数据量、Space 数量以及用户点击速度会改变 A/B 完成顺序，因此问题可能是偶现，并集中发生在“刚进入 Site 就快速点击 Space”的场景。

## 5. 会放大问题的次级风险

### 5.1 Site 导入会并发导入所有 Space

`SiteData.update(...)` 使用 `withTaskGroup` 并发执行每一个 `SpaceData.import(...)`：

- `SunSmart/Common/Data/ImportData.swift:449-464`

如果其中一个任务命中当前正在显示的 Space，`SpaceData.update(...)` 会直接使用全局当前 `meshNetwork`。导入不是基于不可见快照完成后一次替换，而是先删除、再逐项重建：

- 删除全部非本地节点：`ImportData.swift:1321-1326`；
- 删除并重建全部场景：`ImportData.swift:1588-1612`；
- 删除并重建全部定时：`ImportData.swift:1614-1625`；
- 删除并重建全部组：`ImportData.swift:1627-1645` 起。

这意味着即使最终服务器数据正确，正在显示的页面也可能观察到导入中间态；同时这些操作没有显式的串行导入边界或 UI 快照隔离。

### 5.2 定时数据存在跨 Space 覆盖风险

Space 导入设置全局 `MeshNetworkManager.instance.schedules` 时只校验 `meshUUID`，没有同时校验 `meshNetworkId`：

- `SunSmart/Common/Data/ImportData.swift:1620-1622`

同一 Site 下的 Space 通常共享 `meshUUID`、使用不同子网 Key。Site 并发导入多个 Space 时，任意一个 Space 的定时数组都可能写入当前全局 Manager，最终结果取决于任务完成顺序。该问题可以单独造成定时列表错误或为空，但不能独立解释产品和场景也同时消失。

### 5.3 服务器空数组被视为权威新数据的风险

当服务器 `updateTimestamp` 更新，或时间戳相同但汇总数量不同且本地无待上传修改时，`SpaceData.update(...)` 会应用服务器数据：

- `SunSmart/Common/Data/ImportData.swift:1238-1251`

如果复现响应中的 `nodes`、`scenes`、`schedules` 合法存在但错误地返回空数组，导入逻辑会真实清空本地数据。该可能性必须通过响应日志排除。

不过，如果服务器持续返回空数据，第二次进入通常也应继续为空。因此它与“重新进入正常”的吻合度低于全局上下文竞态。

## 6. 当前不支持的原因方向

### 6.1 权限或心跳导致列表隐藏

Space 的心跳和编辑权限冲突主要修改 `disableEditorPermission`、操作权限和弹窗状态；场景、定时的 `updateUI()` 仍从 Mesh 数据源取列表，权限变化主要影响增删改按钮。现有源码没有发现权限切换会同时主动清空产品、场景和定时列表。

### 6.2 三个页面各自的 UI 刷新错误

三个页面控制器、列表实现和通知名称不同，但共同依赖全局 `MeshNetworkManager.instance`。同时消失更支持上游共享上下文问题，而不是三个独立 UI 同时失效。

## 7. 建议的运行时确认项

复现时建议记录以下信息，便于把高概率根因提升为确认根因：

1. Site 自动请求开始、Space 请求开始、两者响应完成和导入完成的时间顺序。
2. 每次调用 `setMeshNetworkConnected(...)` 时记录调用方、目标 `meshUUID`、目标 `subNetworkId`、当前顶层控制器。
3. 数据消失瞬间记录：
   - `Space1.meshNetworkId`；
   - `MeshNetworkManager.instance.currentNetworkKey.networkId`；
   - `currentNetworkKey.isPrimary`；
   - `realNodes/scenes/schedules` 数量。
4. 记录 `/sitespace/get/siteprops` 和 `/sitespace/get/spaceprops` 的脱敏响应：各 Space 的 `updateTimestamp`、`nodes/groups/scenes/schedules` 数量，不记录 Mesh Key、App Key、密码或授权信息。
5. 优先按“进入 Site 后立即点击 Space”与“等待 Site 加载完成后再点击 Space”做对照。如果只有前者稳定复现，将直接支持该竞态链路。

预期的确认日志特征：数据消失前出现一次来自 Site 刷新完成路径的 `setMeshNetworkConnected(site.meshNetworkId, connected: false)`，随后 `currentNetworkKey.isPrimary == true`，且当前顶层控制器仍为 `SpaceViewController`。

## 8. 后续修复边界建议

如果运行时日志确认主因，建议按以下边界设计修复，再单独评审实现方案：

1. Site 刷新完成后的网络切换必须受页面所有权约束；当顶层仍为 Space 时，不得把全局上下文切回 Primary。
2. 进入 Space 后取消、失效化或仅保留 Site 请求的数据落盘部分，禁止旧请求继续执行影响当前页面上下文的副作用。
3. 将“导入数据”和“切换当前运行网络”拆开；后台 Site 数据刷新不应隐式接管 Mesh 运行上下文。
4. Space 导入改为显式 `meshUUID + meshNetworkId` 作用域，并避免删除后逐步重建的中间态暴露给 UI。
5. 修正定时导入的当前子网判断，不能只比较 `meshUUID`。
6. 该代码为多个品牌 target 共用，修复后至少验证 `SunSmart`、`Archipelago`、`SLG Sync Plus` 和 `SylSmart`；真实设备还需验证 Mesh Proxy、跨 Space 切换、场景和定时数据一致性。

## 9. 分析结论分级

- **高概率主因**：后台 Site 刷新完成后，将全局 Mesh 从当前 Space 子网切回 Site 主网。
- **高风险放大因素**：Site 并发导入 Space，且当前 Space 导入采用删除后重建方式，UI 可观察到中间态。
- **独立确定性缺陷**：全局定时数组写入只比较 `meshUUID`，未比较 `meshNetworkId`，存在跨 Space 覆盖风险。
- **待日志排除**：服务器返回合法空数组并携带较新时间戳，导致真实本地数据被覆盖为空。
