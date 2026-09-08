# Site 长时间加载修复与验证记录

日期：2026-09-08。App 工作区：fix，基线：250e0ee0。用户已授权按调整后的优先级实施。本次未提交或推送。

## 问题与修复范围

原日志中的 1788771532.627898 是 Unix 时间戳。Site 更新区间为 174.701428 秒，位于 HTTP 响应及节点探针之后。此次主要治理导入前置计算、重复数据库读取和 SDK 地址匹配；gzip 单独处理传输契约。

已实施：

1. Site、Space、远端预检和导出增加单调时钟阶段计时，输出 scope、trace、阶段、主线程标记和耗时。升级基线进一步分开配置比较、checkpoint、快照保存；事务读回前的计时不冒充事务提交完成。
2. 远端拓扑预检在专用串行后台队列准备，缓存最多 8 份纯值结果。缓存键包括整个远端 JSON 的 SHA-256 和 initialize 参数，不只比较更新时间；远端内容改变会重新解析。缓存不保存 SDK Node/Group 活对象，不替代本地权限、脏数据、恢复、删除和拓扑保护判断。
3. 新增 await 后再次校验取消、恢复上下文与本地更新时间，过期准备结果被拒绝。写入事务和读回验证保持原有受控流程。
4. 导出授权读取的 Mesh 在数据库版本未变化时供后续导出复用；升级基线导出读取的网络可继续供本次导入使用。App/Mesh SQLite 的连接身份、totalChanges、data_version，以及账户和地区共同限制复用。版本查询失败或数据库发生写入时重新读取。
5. SDK 的地址补全使用 Set membership，保留原数组顺序及重复项语义；地址查询仅取 primaryUnicastAddress、elementCount，避免读取模型 JSON。Site exclusions 的匹配也改为 Set。没有网关时避免为网关列表和时区上下文加载完整网络。
6. HTTP JSON 解析移至后台响应队列，两个回调接口均明确回到主队列。大响应不再为日志额外完整解析、脱敏、序列化；节点探针默认关闭，开启后仅处理小正文且最多输出 10 项。
7. 删除查询接口不真实的 Content-Encoding:gzip。最终请求编码阶段为 `/sitespace/sync/siteprops`、`/sitespace/sync/spaceprops` 的正文在达到 1,024 字节时生成真实 gzip，再设置 Content-Encoding；覆盖同一路径的 Site 创建。小请求保持普通 JSON，Accept-Encoding 保持。压缩失败作为请求失败返回，不静默重试上传。增加响应编码、传输字节数与解码后字节数指标。

## SDK 依赖与复现

**更正：开发入口是 SunSmartLocal.xcworkspace，SDK 开发工作区是 one-dev。** 此前擅自创建隔离 SDK 并切换正式工程依赖的处理不适合用户现有工作流，已经废弃。

SDK 修复现已直接应用到：

`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`

保留其原 HEAD `8bdbd5a` 及已有开发内容，只修改 MeshDatabase.swift 中的数据库版本读取、地址 Set membership 和标量查询。

原有 `.local-sdk/nordic-sig-mesh-sdk` 软链接继续指向 one-dev，SunSmartLocal.xcworkspace 的内容不变。正式 project、SunSmart.xcworkspace、正式 Package.resolved 均保持原有配置，不需要切换运行入口。

已移除本次误加的隔离 SDK 准备脚本及补丁文件；改用仓库已有的本地 SDK 工作流。最新验证见 `260908_1734_local_sdk_workflow_correction.md`。SDK 尚未提交或发布，正式远端版本尚不包含新增方法。

## 自动验证

- SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux：generic iOS Debug 构建通过，关闭代码签名；未使用 Simulator。构建仍有原有资源重名、弃用 API、Sendable 等警告。
- `check_site_entry_performance.py`：生产 SDK 标量查询、1,064 行真实 SQLite 数据、地址顺序/重复语义、同连接及外部连接写入后的快照失效、账户/地区隔离、真实 gzip 压缩解压字节一致性通过。
- 地址 membership 合成样本：64,000 候选、30,000 已用地址，最新本机测试约 0.0213 秒。此数字是 macOS 独立算法测试，不是原 iPad 的 Site 加载耗时。
- `check_network_response_queue.py`：两个生产回调适配器的成功、业务失败、非法 JSON、非对象 JSON、HTTP/传输错误分支通过；解析离开主线程，回调回到主线程，每个请求只完成一次。传输边界使用测试替身，没有调用真实服务器。
- `check_proximity_scoped_import.py`：生产预检的相同正文复用、正文变化/initialize 变化失效，以及拓扑、跨 Site/Space 隔离、破坏性导入保护、删除恢复和所有权回归通过。
- `check_startup_ownership_loading.py`：真实 SQLite 标量身份查询、无模型解码、任务合并、主队列交接及过期恢复验证通过。
- `check_configuration_database_safety.sh`：真实 SQLite WAL 快照、隔离、失败 checkpoint、事务回滚与旧 profile schema 通过。
- `check_space_recovery_receipts.py`：持久化回执、权限基线、重连、持久化失败及生命周期隔离通过。
- `check_device_permanent_deletion_cleanup.sh`：设备日程地址清理通过。
- App 和隔离 SDK 的 `git diff --check` 通过。

## 保留的边界与后续验证

本次没有把“时间戳相等”改成跳过全部安全校验。远端无变化时可以复用纯预检结果；本地安全判断仍执行。失败升级基线的跨次持久化缓存、全量导出编码后台化没有在此次实现：前者需要完整的本地配置版本和恢复文件失效依据，后者需要先分离共享模型的可变状态。现有阶段日志用于判断是否还需要继续推进这两项。

0xC006 的悬挂 Path 引用继续触发本地快照保护，没有自动删除引用；服务端 deviceCount 与 nodes.count 的差异未修改。UIScene、方向支持和空 App Group identifier 未混入此次性能修复。

尚未取得原 iPad 的修复后采样，也未实测本次大上传在生产服务器的接收结果。应使用原账户/原数据验证：冷启动、首次进入、重复进入、远端数据变化、离线失败、权限/账户切换与本地待上传。重点检查 HUD 最终收尾、界面响应、设备/组/路径保留，以及 `[SiteImportTiming]`、`[SiteImportBaseline]`、`[HTTP][Metrics]`。通过 receivedBytes/decodedBytes 判断下载 gzip 是否实际生效；不能仅凭业务 Data 大小判断线上传输量。
