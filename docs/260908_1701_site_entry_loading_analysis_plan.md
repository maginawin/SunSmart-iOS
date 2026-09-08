# iPad 进入 Site 长时间转圈：分析与优化方案

日期：2026-09-08。工作区：fix。分析基线：250e0ee0（已包含上一轮启动归属预检修复）。本轮仅分析源码、日志并规划，不修改业务代码。未取得此次 Site 卡住时的新线程栈、完整响应或原设备数据库。

后续日志已补全：Site 导入最终完成，耗时 174.701428 秒。请优先阅读 [后续耗时与 gzip 分析](260908_1704_site_import_elapsed_and_gzip_analysis.md)，其结论更新了下文“尚不确定正式导入是否开始”的证据边界及优化优先级。

## 1. 结论与证据边界

上一轮启动恢复中的无条件 Mesh 全量加载已经在本次普通数据路径上被跳过。新的等待集中在列表导入以及进入 Site 的本地读取、响应诊断、业务解析和导入链路。已确认多处规模相关的昂贵操作，但无法用这份日志给各环节分配实际耗时，也不能认定死循环或死锁。

| 日志事实 | 能得出的结论 |
| --- | --- |
| 5 个 Space、1,064 个身份，启动预检 0.053427 秒，进入 Site 预检 0.007401 秒，均 needsRepair=false | 本次预检快速结束，未走旧的完整归属修复分支；不应继续把该分支当成本次主因 |
| sites 返回 HTTP 200 / businessCode 200，170,170 字节 | 列表请求已取得业务成功响应 |
| 列表“导入数据”1788771312.069252，“导入数据完成”1788771327.4158049 | 导入区间墙钟耗时 15.346553 秒；已排除该区间仍在等待此列表 HTTP 响应，但不能全算作主线程 CPU 时间 |
| siteInfo 返回 HTTP 200 / businessCode 200，7,365,982 字节 | 约 7.37 MB（7.02 MiB）的 Site 数据已到达客户端；响应大小不等于线上压缩传输字节数 |
| NodeProbe 输出 1,064 条记录 | 节点分布为 59 + 499 + 500 + 6，诊断输出没有条数上限 |
| Gesture gate timed out，且发生在 siteInfo Response 日志之前 | 与界面响应迟滞一致；Response 打印前本身已有日志预处理，不能只按打印顺序确定网络实际收包时刻 |
| 本次没有第二组“导入数据”标记，也没有 SiteViewController 的 enter 日志 | 尚无证据证明正式 Site 导入已经开始或页面完成首次出现；需优先检查正式导入标记之前的工作 |

本日志里的 UIScene、全屏和方向提示不是已经触发的崩溃；App Group 空标识符是另一个配置问题。网络 metadata 警告之后请求成功，不能据此认定服务器连接一直失败。没有证据把这些提示直接关联到当前长等待。

## 2. 代码对应的四段负担

### 2.1 列表导入复用重量级数据入口

`SitesViewController.swift:291` 请求列表；`:320–338` 的计时包围 SiteData.import 的 task group。`ImportData.swift:448` 的 SiteData.update 同时用于列表和详情，并没有显式传入 summary/detail 模式。

该入口在 Site 时间戳判定之前调用 MeshNetwork.load(allData:false)（`:478`）。之后还可能合并 exclusions、更新 provisioner、处理 Space/Gateway、保存。不能因为列表响应只有 170 KB，就假定本地工作也很小。

核查工程实际锁定 SDK 86f5ec9e40148b9cd93e0512702337fcec41dd40 的 `Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift:186–267`：

- allData:false 仍加载 provisioner 的本地 Node、exclusions、deviceUsedAddresses。
- `:235` 调用未限定 subnetworkId 的 Node.loadAddresses(meshUUID:)，扫描整个 Site 的节点地址。
- `:241` 对现有节点地址和废弃地址逐项调用 deviceUsedAddresses.contains，规模为 O((A+E)×U)，A 为节点元素地址数、E 为废弃地址数、U 为已用地址数。
- 必要时追加地址并 network.save，因此该加载函数并非纯只读。
- Node.loadAddresses（`:876`）只使用主地址和 elementCount，却未显式限定 SQL SELECT 列；应测量并改为标量投影，避免取出无关大字段。

App 的 exclusions 合并（`ImportData.swift:692–740`）还存在 filter 内嵌数组 contains。日志确有大量 exclusions，但完整数量未知。此路径是 15.35 秒的重要候选，尚未测得占比。

### 2.2 页面首次出现前的同步 Mesh 读取

`SiteViewController.viewDidLoad` 发起 siteInfo；`viewWillAppear` 完成快速归属预检后同步调用 setupData（`:205`）。setupData → loadGatewaysData（`:1450`）→ sitePrimaryMeshNetwork（`:1356`），当前网络不能复用时调用默认 allData:true 的 MeshNetwork.load。

这里传入 Site 主网 subnetworkId，不应说它必然解码全部 1,064 个 Space 节点；但 SDK 的地址与 exclusions 补全仍覆盖整个 meshUUID。即使网关为空，当前实现也先加载网络再查询网关。

后续网络切换完成还会再次 setupData。应按一次进入操作记录加载次数，先确认重复开销再决定复用边界。`updateAddressData()` 当前函数体全部注释，不是本次真实扫描来源。

### 2.3 响应诊断在主线程抢先处理大数据

`NetworkRequest.swift:36` 的 MoyaProvider 没有指定 callbackQueue。已沿本地依赖核实：`Moya+Alamofire.swift:82` 使用 Alamofire 默认 response，`DataRequest.swift:219` 默认队列为 main；`MoyaProvider+Internal.swift:270` 先调用插件 didReceive，再调用业务 completion。

本次 DEBUG 成功路径，在业务导入之前至少有四次整份响应的 JSON 解析：

1. NetworkLoggerPlugin.didReceive（`:48`）读取业务码。
2. responseBodySummary（`:107`）再次 JSONSerialization，递归生成脱敏结构，排序重新序列化，转完整字符串，最后才截取 3,000 字符。
3. NodeProbe（`:137`）再次解析响应，遍历所有节点，生成并拼接全部 1,064 条字符串再 print。
4. NetworkRequest.request（`:124`）respond.mapJSON，再传给业务层。

所以“控制台正文被截断”仅限制显示长度，没有限制预处理成本。该开销在 DEBUG 编译条件下存在；Release 仍需单独评估下面的本地读取和导入问题。

### 2.4 业务回调在正式导入前还读取 Mesh；正式导入也有主线程重活

`SiteViewController.swift:504–549` 先解析时区状态、建立本地网关上下文，然后才创建 Task 并在 `:554` 打印导入开始。

`SiteGatewayCloudTimeZoneLocalContext.swift:42` 的 builder 为 @MainActor，`:73` 无条件加载 Mesh，之后才筛选网关候选。即使授权网关集合为空，仍付出网络加载成本。此处可以解释为何节点诊断打印完之后，仍没有正式导入开始标记，但目前只是与日志吻合的候选。

如果已经进入正式导入，仍有以下成本：

- SiteData.update 的 task group 调用 SpaceData.import；SpaceData.update（`ImportData.swift:1559`）明确 @MainActor。task group 并没有把其同步计算自动移到后台。
- 首次升级基线可能先 export；随后主线程读取本地整网（`:1622`）、解析拓扑、构建摘要；到 `:1740` 才判定是否跳过应用远端数据。所以最终 skipped 也可能已经很贵。
- 真正导入包含节点/模型反序列化、事务内写入、拓扑重建，以及 `:2504` 再加载整网验证。这些安全机制不可为了性能直接删除。

HUD 默认没有有限展示期限。Site 页成功分支要等待导入、可能的地址回收请求、setupData 等完成，到 `SiteViewController.swift:629` 附近才 hide。HTTP 200 不代表导入和界面加载完成；请求超时也不能约束 HTTP 返回后的本地工作。

## 3. 优化实施顺序

### 第一批：补齐测量并消除确定的多余工作

1. 每次进入分配 traceID，记录单调时钟、是否主线程、Site/Space 数量、响应字节数和阶段 start/end：页面本地准备、HTTP 回调入口、logger、mapJSON、时区上下文、Site 导入、每 Space 预检/解码/事务/读回、地址回收、setupData、HUD 结束。日志只写计数与必要标识，不复制原响应及密钥。
2. 大响应默认仅输出摘要；在全量解析/重编码之前按 Data 大小决定是否省略正文。节点探针默认关闭或显式开启后限制条数，并说明 omittedCount。仅使用有界诊断队列，不能把无上限数据堆到后台。
3. 将业务 JSON 解析放入专门处理队列，结果交回主线程；复用解析结果生成诊断摘要。不能仅改 Moya callbackQueue 就把所有既有 UIKit 回调一起放到后台。
4. 网关候选为空时不加载 Mesh。首次页面准备与时区上下文优先使用轻量 GatewayModel/所需 Node 属性；若需要复用完整网络，限定在单次操作且校验 Site/子网/版本、维持对象生命周期。

这一批可优先在 App 落地并测量，不能预先承诺消除所有 15 秒等待。

### 第二批：修公共加载与地址算法

1. SDK 地址 membership 使用预先构建的 Set，将重复线性查找降为近似线性遍历；原数组继续保存，保持地址顺序、重复处理及 IV Index 语义一致。App exclusions 合并同样建立按 IV Index 的查找索引。
2. Node.loadAddresses 改为显式标量列读取；按实际 query plan 决定是否需要索引，避免直接新增冗余索引。
3. 引入专用只读网络头/网关属性读取入口；地址补全写入保留在受控维护入口。初期不改变旧 MeshNetwork.load 的恢复语义，逐个迁移只读调用者，避免漏补地址。
4. SDK 改动在已指定的 one-dev 开发目录进行，并验证工程实际引用的 SDK 版本；不能直接修改 DerivedData checkout 后宣称 App 已获得修复。

### 第三批：列表摘要与完整导入分开，缩短主线程占用

1. 列表仅更新名称、权限、计数、在线概览等摘要；完整拓扑从详情入口应用。必须显式定义权限撤销、网关归属、地址资源等字段的权威边界，不能把“缺字段”当“空集合”，也不能擅自丢弃列表中唯一提供的必要数据。
2. 完整导入分为后台不可变快照解析/校验与受控提交。按账户、地区、Site、Space 和恢复版本校验过期结果；共享 SDK 模型和数据库写入需隔离，禁止直接把现有 update 整段搬进 detached task。
3. 提前用持久化版本/摘要判断无需导入，保留同时间戳但内容不同、强制恢复、待导入日志、未上传删除、权限变化等例外；不能只比较节点数量或时间戳。
4. 测量后优化批量写入、复用单次导入快照及读回验证的重复加载，同时保留 checkpoint、事务回滚、拓扑验证和跨 Space 隔离。

### 第四批：加载生命周期与传输契约

- 同 Site 加载合并，跟踪请求和导入任务；页面退出、账户/地区切换后拒绝旧结果刷新当前页。成功、失败、取消都由同一加载状态出口清理 HUD。
- 有已验证本地缓存时先显示 Space 列表，后台刷新；首次无缓存时保留明确加载状态。超时应结束等待并提供重试，不能将部分导入当成功，也不能用延时 hide 掩盖阻塞。
- 暂不把 7.37 MB 全量响应改成分页/按 Space 拉取：需要服务端提供稳定版本、完整性和删除语义，再作为后续优化。
- 独立修正请求 Content-Encoding:gzip 与 JSON 明文 body 的错配；Accept-Encoding 负责响应协商，二者不能混用。本次已成功返回，不能把错配认定为本次长等待主因。覆盖 siteInfo、spaceInfo、siteUpload、spaceUpload 的真实 task 编码。

## 4. 验证与验收

- 优先在原 iPad、相同 1,064 节点与 exclusions 数据上连续多次采样；卡住时至少取得数次主线程栈或 Time Profiler，区分日志处理、地址扫描、网关读取、正式导入和网络等待。
- 对比冷启动、重复进入、已有缓存、无网关、499/500 节点 Space、有大量 exclusions、数据未变/有变化。分别记录调试日志开关、Debug/Release，不能拿 Mac 合成测试代替设备结论。
- 性能验收：每阶段有完成/失败/取消记录，界面可响应且 HUD 有终态；统计首屏时间、导入总耗时、主线程最长连续占用、Mesh 加载次数和内存峰值。初步以主线程单段尽量低于 100 ms 为工程目标，原设备测量后确定首屏/导入总耗时预算，不承诺千节点瞬时完成。
- 正确性回归：地址保留与回收、相同时间戳差异、待删除/恢复/导入、网关时区本地脏数据、角色权限变化、账户/地区/Site 切换、重复刷新、导入中断恢复；导入前后核验全部节点及 Group/Scene/Schedule/Trigger Zone、side stores，无数据丢失。
- 修改公共 App/SDK 后执行相关契约测试及五品牌 generic iPhoneOS 构建；加载交互若变化，在真实 iPad 验证完整进退页面、失败重试及旋转布局。不使用 Simulator 代替验收。

本轮没有运行构建或宣称新优化已生效。建议先实施第一批，并基于阶段数据安排第二、三批，优先修重复加载和地址算法，最后再评估服务端拆分。
