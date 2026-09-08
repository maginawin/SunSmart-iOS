# Site 导入 174.70 秒与 gzip 使用情况补充分析

日期：2026-09-08。工作区：fix，代码基线 250e0ee0。本轮仅分析并更新方案，没有修改业务代码，也没有请求用户的线上 Site 数据。

## 1. 时间戳代表什么

`导入数据完成: 1788771532.627898` 是 Date().timeIntervalSince1970 输出的 Unix 时间戳，单位秒，不是数据大小或处理次数。数值大不会导致此次卡顿。

- 开始：1788771357.926470。
- 完成：1788771532.627898。
- 差值：174.701428 秒，约 2 分 54.70 秒。

对应 `SiteViewController.swift:554–558`，计时包围 `await self.site.update(siteJsonData:)`。响应日志、节点探针和 NetworkRequest 的 mapJSON 在开始标记之前；HUD 的实际收尾和可能的回收请求在完成标记之后。

因此，174.70 秒已经是收到此 HTTP 响应并进入 Site 更新后的墙钟耗时，不是此 siteInfo 的下载时间，也不能归到此前 1,064 条 NodeProbe 输出。它包含更新路径内部 CPU、数据库/文件 I/O、任务调度和等待；不代表主线程连续运行了整整 174 秒。

手势日志的 26.815 秒说明存在较长交互迟滞，但不能据此把全部导入区间视为单次主线程阻塞，也不能把它与导入区间简单相加。页面最终出现、导入最终返回、HUD 最终消失，支持“严重慢处理”的判断，不能再称作这一次永不返回或死锁。

## 2. 大多数 Space 没有应用完整远端数据，仍然很慢

| Space | 本次结果 | 说明 |
| --- | --- | --- |
| 59 个远端节点的 Space | invalidRemoteTopology，preserved local snapshot | 保护本地拓扑，没有直接应用疑似破坏性修复 |
| 兴东，500 个节点 | skipped | 时间戳相同，最终无需应用完整数据 |
| 兴东2，499 个节点 | skipped | 时间戳相同，最终无需应用完整数据 |
| 新领dongle，6 个节点 | skipped | 时间戳相同；serverDeviceCount=485 与 nodes.count=6 另有摘要一致性问题 |
| 空间 1，0 个节点 | skipped | 时间戳相同，最终无需应用完整数据 |

这些结果不表示整个更新没有任何写入：元数据保存、恢复状态、升级基线、Site 级更新仍可能发生。但本次不能用“重新写入全部 1,064 个节点”解释 174 秒，因为这些 Space 都没有走到常规完整应用分支。

## 3. 进一步核查的主要热点

### 3.1 跳过判断太晚，前面已经完整解码和读取

`ImportData.swift:1559–1747` 的 SpaceData.update 是 @MainActor：

1. 元数据保存、删除恢复和本地保护检查。
2. 如需升级基线，先执行 `export(purpose:.localBackup)`。
3. ProximityLightingImportPreflight.parse：遍历远端 Group/Node；扫描 elements/models/subscriptions；对符合条件的节点重新序列化并 JSONDecoder.decode(Node.self)。不仅仅是读取几个摘要字段（同文件 `:123–217`）。
4. 读取本地 Mesh 全量模型与拓扑，检查本地可用性。
5. 检查配置、构造摘要、再读取一次 allData:false 网络检查 key。
6. 最后根据版本、恢复状态和摘要判断是否 skipped。

所以即使 499/500 个节点的 Space 最终 skipped，完整节点解码、模型分配及本地加载仍可能已经发生。withTaskGroup 调用这些函数不能让 MainActor 的同步片段并行执行。

### 3.2 升级基线可能多次重复完整导出

本日志出现多个 ProximityLightingExport，说明导入期间确有导出活动；日志缺少 Space ID/traceID，无法把每条导出逐一归属到具体调用者。当前更新入口的升级基线是明确候选。

`SpaceConfigurationSafety.swift:678–689`：只有本地配置与远端配置对比一致，并成功完成 checkpoint 和 snapshot 后，才设置 spaceConfigurationMigrated 标记。若不一致、被 blocked 或持久化失败，标记不会设置；未来进入仍可能再次尝试完整导出。

`ExportData.swift:123–158,336–356,494` 显示一次本地备份导出至少包含：

- snapshotExportAuthorization 加载一次完整 Mesh 校验。
- 随后 MainActor.run 内再次完整加载同 Space Mesh、加载 GroupInfo/SceneInfo 等。
- 拓扑准备、逐节点编码和扩展字段拼装。

加上导入自己的 localMeshNetwork 以及 allData:false key 检查，一个进入升级基线并完成导出的 Space 可触发至少四次 MeshNetwork.load；不是本机实际采样计数，且不包括其他内部加载。

checkpoint（`SpaceConfigurationSafety.swift:708`）在缺少完成标记时备份 App 与 Mesh 两个数据库。是否在这次 174 秒内执行、耗时多少尚无日志证据，不可直接认定是主要耗时。

### 3.3 每次 Mesh 加载还包含 Site 级地址扫描

延续上一份方案已核实的 SDK 行为：allData:false 也会查询整个 meshUUID 的节点元素地址和 exclusions，并在 filter 中反复做数组 contains，必要时写回。多个 Space 重复加载相同 Site 的地址集合，会放大该成本。

优先测量升级基线 export、preflight.parse、MeshNetwork.load 的分阶段耗时及调用次数，不能只在正式 Node.import 或事务写入内加计时。

## 4. 拓扑和计数日志的正确解读

### invalidRemoteTopology 不等于 hardErrors 必须非空

ProximityLightingImportPreflight.hasValidationIssues 同时检查 warnings、hardErrors 和 hasDestructiveRepairs。

`ProximityLightingTopologyReconciler.swift:183–192,240–248,288–302`：sequence[group:node] 表示路径引用的设备地址不在该组计算出的成员集合中，归一化结果需要清空该引用；这种修复被分类为破坏性修复。因此 warnings=[]、hardErrors=[:] 时，仍可能触发保留本地快照。

这次列表有 24 项 sequence 修复，均指向十进制组地址 49158（0xC006）。应核查该组 Path 引用、设备订阅、groupState、以及归一化采用的 vendor element 地址。不能只凭此日志认定云端设备被删除，也不能自动删除这 24 个引用来提速。

remoteNodes=59/localNodes=60 的比较口径不同：local 使用整个 network.nodes.count，可能包含本地 provisioner，不能直接推断少了一个业务设备。

### Group 数量不同不必然触发重导入

SpaceImportSummary（`ImportData.swift:76–108`）的远端 groupCount 排除 isVirtual=true 的组，而 PJSpaceCountProbe 输出原始 groups 数组长度。18 对 16、7 对 1 可能是虚拟组口径差异。完整响应缺失，不能确认虚拟组确切数量；但不能仅凭原始计数差异认定 skipped 错误。

deviceCount 比较使用 nodeDicts.count，不是服务器 deviceCount 标量。因此新领dongle 的 485 对 6 应单独追踪服务端摘要/字段语义，不能为了达到 485 而生成设备，也不能据此判断本地丢失 479 个设备。

## 5. App 到底有没有使用 gzip

### 上传请求正文：当前没有真正压缩

`NetowrkReqeustApi.swift:590–615`：gzipped + requestCompositeData 分支全部被注释，实际统一使用 JSONEncoding.default 的 requestParameters。

`NetworkRequest.swift` 中另一个压缩尝试也被注释。此次请求日志 actualBodyGzip=false 且正文为可读 JSON，与源码一致。

但 siteInfo、spaceInfo、siteUpload、spaceUpload 仍设置 Content-Encoding:gzip。这是请求编码声明与实际字节不一致，不是已经使用 gzip 的证据。siteInfo 的请求仅 97 字节，压缩收益很小；应取消不真实的声明。大体量 siteUpload/spaceUpload 如要压缩，应真正生成 gzip 字节，再设置对应头，编码失败必须保证声明与 body 同步。

### 下载服务器响应：已经声明接受 gzip，本次是否生效尚不能确认

上述四类请求设置 Accept-Encoding:gzip。这表示接受压缩响应；服务端支持 gzip 并不证明某次响应实际使用了 gzip。App 使用 URLSession/Alamofire 的响应处理，不需要把服务器压缩响应手动重复解压；应按正确 Content-Encoding 交由传输层解码。

当前 NetworkLoggerPlugin 只记录 response.data.count，没有响应 Content-Encoding 或任务传输指标。7,365,982 字节是业务拿到的 Data，不能据此认定线上传输就是 7.37 MB。

应记录响应头 Content-Encoding、Content-Length（若存在），并采集 URLSessionTaskTransactionMetrics：countOfResponseBodyBytesReceived 与 countOfResponseBodyBytesAfterDecoding，分别核查传输量和交给业务的数据量。Apple 对两者的定义分别见[传输字节数](https://developer.apple.com/documentation/foundation/urlsessiontasktransactionmetrics/countofresponsebodybytesreceived)和[解码后字节数](https://developer.apple.com/documentation/foundation/urlsessiontasktransactionmetrics/countofresponsebodybytesafterdecoding)。压缩比统计需注明传输计数可能含协议 framing/编码开销。

即便服务器将 7.37 MB 压缩成更少的线上字节，App 仍需处理解码后的 1,064 个节点及其模型。gzip 主要解决传输体积，不能消除已经发生在导入开始之后的 174.70 秒本地处理。

## 6. 调整后的实施优先级

1. **以导入内部为首要性能对象。** 为每个 Space 增加 traceID/阶段计时，分别测量 baseline export、配置对比、checkpoint、远端 preflight 解码、各次 Mesh load、skip/apply 及 Site 收尾。同步限制日志并采集传输指标。
2. **先修“无变化仍全量工作”。** 设计可复用的已验证版本/配置摘要及基线尝试记录。快路径必须保留权限、pending import/deletion、本地脏数据、同时间戳内容不同和 invalid topology 的保护语义；不能简单把时间戳 guard 移到最前面。基线失败的重复尝试可按不变的本地版本+远端内容指纹避免重复导出，但绝不能把失败标为迁移成功。
3. **减少重复全网加载，优化 SDK 地址索引。** 复用一次操作中的一致快照，使用标量属性读取和 Set membership，保留恢复及地址生命周期语义。
4. **后台准备不可变数据、串行受控提交。** 将 preflight 和导出编码等纯计算移出主线程；共享模型/SQLite 事务不能任意跨线程，仍保留恢复、回滚、读回验证。
5. **单独修 gzip 请求契约与拓扑异常。** 前者改善协议正确性和大上传体积，后者验证 0xC006 的悬挂引用来源，两者都不应替代性能热点治理。

本轮确认了完整导入区间及具体前置工作，尚未取得各热点的真实耗时和设备采样。仍应在原 iPad、原数据、Debug/Release、多次重复进入场景下验收；性能改善不得以跳过数据完整性保护为代价。
