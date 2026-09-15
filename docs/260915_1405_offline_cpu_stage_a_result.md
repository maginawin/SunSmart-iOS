# 断网加载与 CPU 风险：阶段 A 实现及验证结果

## 结论

已实现批量 Site Zone 清理合并、中断恢复标记和安全回归，五个品牌 target 的 iPhoneOS 构建通过。真机完成了真实本地数据副本上的三组旧／新路径对照，分类器读取次数均由 12 次降至 3 次。

阶段 A 的代码与可执行回归已完成；**真实 App 的断网／弱网端到端及最终体验验收仍未完成**。本次真机结果覆盖本地清理性能，不代表请求、HUD、触控或网关链路验收。阶段 B、C 未实施。

依据：[原 review](260915_1149_offline_cpu_risk_review.md)、[已确认计划](260915_1340_offline_cpu_risk_fix_plan.md)。基线 HEAD 为 `cf5e5c13`。改动保留在工作区，未提交或推送 Git。

## 实现内容

### 批量准备与调用顺序

- `SpaceSyncCleanupCoordinator.prepareBatch` 按 Site 准备 Space，同一稳定批次只在末尾进行一次 Site Zone 清理；去重 Space ID，拒绝混入其他 Site。
- 前台恢复、`SyncOperation.syncSite`、`addSpaces` 已接入批量入口；恢复保留 Space 筛选、真实主队列交接，以及交接后复查上传队列的行为。
- 单项 `prepare`／`prepareCurrentSpace` 保留 Site 收尾职责。只共享内部 Space 清理任务，单项不会因等待到批量内部任务完成而跳过自己的 Site 收尾。
- 批量返回重新读取的 Site／Space 状态，供 Zone pending 判断及上传导出使用；远端 Zone 同步后重新读取 Space 再筛选上传候选。
- 接收远端后的独立 Zone 清理仍然执行。恢复批次和正式上传批次允许分别清理一次。
- 一个 Site 因存储失败无法准备时，恢复入口继续处理其他 Site；单个 Space 失败仍沿用已有上传安全门，不把整批准备结束当作所有 Space 均可上传。

### 中断、持久化及作用域

- 在既有 `SiteTriggerZoneState` 增加可选的本地 `referenceCleanupRequests`。原表按 Site／区域隔离，标记按账号保存 UUID 代次；旧 JSON 缺少字段仍可解码。
- 标记先于批量 Space 修改持久化。标记写入失败时不启动缺少恢复保障的 Space 准备；Zone 提交或清除标记失败时保留恢复记录。
- 清理结果区分完成、暂缓和抛错；冲突、歧义远端、被拒绝远端、提交中、无权限等暂缓情况不清除标记，也不在本轮循环等待。
- 运行中的单项／批量调用分别持有 Site 工作标识。只在同作用域没有其他未结束准备、且代次仍匹配时清除标记，防止提前丢失中断恢复入口。
- 空 Space 候选也会补做已有 Site 待清理工作。远端接收不清除本地标记，该字段不进入服务端 extensionData。
- 账号、区域、取消和恢复任务身份在异步边界检查。取消不强行终止其他调用也在等待的共享 Space 任务；当前共享本地准备结束后退出本批次，不启动后续 Space、不提交本批次 Zone 收尾，保留恢复标记。
- 未知、不可读、受阻及不安全拓扑成员继续由原分类器保守保留；清理不提前确认设备已同步。

没有修改 SDK、依赖、国际化、产品 UI 或 target 配置。真机探针和计数插桩仅存在临时工程中，没有写入产品代码。

## 自动化验证

以下均通过：

| 验证 | 覆盖 |
| --- | --- |
| `scripts/check_site_zone_cleanup_batch.py <SDK路径>`（新增） | 生产批量协调、三条调用入口、真实 SQLite Store、生产 Zone 分类器和清理逻辑 |
| `scripts/check_site_zone_cleanup_loading.py` | 空／无效 Zone 零读取、引用按需加载、失败读取缓存、保守清理 |
| `scripts/check_startup_ownership_loading.py <SDK路径>` | SQLite 投影、候选筛选、恢复合并、主队列交接、旧恢复任务隔离 |
| `scripts/check_space_sync_cleanup.py` | Space 完整快照清理、Profile、幂等性、非法数据及观察状态保留 |
| `scripts/check_site_trigger_zones.sh` | Zone 数据／持久化、候选、展示策略及拓扑策略四组测试 |
| `SiteEntryTimeZoneSyncCoordinatorTests` | 时区等待、超时、取消、迟到结果、失败保留待上传状态 |
| `SiteGatewayCloudTimeZoneSyncCoordinatorTests` | 轮询失败、总超时、取消、旧任务隔离 |
| `scripts/check_missing_group_hardware_cleanup.py` | 无组收尾、设备观察、失败回执和持久化重试 |
| `scripts/check_space_recovery_receipts.py` | 上传快照／版本、Site 交接、账号／权限／取消、导入和清理回执 |
| `git diff --check` | 差异空白检查 |

新增批量测试的稳定计数为 K=1、R=1 → 1 次；K=100、R=80 → 80 次。K 是候选 Space 数，R 是 Zone 引用且需要尝试加载的不同 Space 数。旧路径约 K×R 的推导不包含 Space 自身导出和清理成本。

新增安全用例还覆盖：SQLite 文件重开恢复、仅 Site 有标记、账号标记隔离、部分失败、权限／冲突／提交中暂缓、标记写入失败、Zone 写入失败及后续恢复、取消、网络在 Space 之间失效、账号／区域切换、同 Space 共享任务、不同 Space 的单项／批量重叠、上传载荷使用新状态、交接后 Space 已进入上传队列，以及单个 Site 存储失败不阻断其他 Site。

测试边界：新脚本直接编译生产批量协调、Zone 清理、SQLite 持久化和三个调用分支；内部 Space 修复及网络传输使用替身。完整 Space 策略和回执由独立已有测试覆盖，不能把这些测试写成真实网络或设备通信验收。

SDK 测试路径为仓库规定的本地 `one-dev` 路径；App 构建使用原 workspace 已解析的远端 `release (a6246b1)`，未切换依赖。

## 品牌构建

SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 均完成最终代码的 Debug、generic iPhoneOS、关闭签名构建。直接运行 `xcodebuild`，没有使用 Simulator、shell 包装或日志重定向。

构建仍有既有 UIKit 弃用、未使用变量、部分品牌资源重名／重复构建文件等警告；未扩大本次改动去处理它们。最初查询真机和一次构建遇到沙箱服务访问问题，按工具权限规则在沙箱外重试后成功。

## 真机本地清理性能对照

### 方法与范围

- 设备：`MtestiPhone15`（iPhone 15）。
- 独立临时应用：`com.sunricher.stage-a-cleanup-probe`，Debug／iPhoneOS；使用原 SDK 的真实 Mesh 加载、Space 清理与 Zone 分类器。
- 从现有测试机数据读取副本；探针每次进程启动都将相同副本恢复到自身容器。没有改写原 SunSmart 的数据。
- 样本 Site：4 个 Space，Zone 引用其中 3 个 Space，共 17 个成员。探针把副本标记为已有升级基线，以单独测量本地工作；不运行 HTTP 基线查询、正式上传、页面加载或蓝牙控制。
- 同一探针内编译基线提交的旧 `SpaceSyncCleanupCoordinator`，旧模式逐 Space prepare；新模式调用生产 `prepareBatch`。旧模式同样在 Space 之间交还主队列。
- 分类器仅在临时源码中增加读取计数；CPU 用 `getrusage` 的进程累计用户态＋系统态时间，墙钟用 systemUptime。主队列指标为 5 ms Timer 的最大回调间隔，**不是精确的最长连续阻塞时间**。内存记录进程常驻字节数。
- 按旧、新交替各运行三次，每次均重建同样的探针数据。17 个成员在六次运行后均保留，新模式三次均没有遗留本地待清理标记。

### 测量结果

| 轮次 | 路径 | 分类器读取 | 本地准备耗时（秒） | CPU 累计用时（秒） | 主队列最大回调间隔（毫秒） |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | 旧 | 12 | 1.1117 | 1.0877 | 159.46 |
| 1 | 新 | 3 | 0.7197 | 0.6922 | 120.51 |
| 2 | 旧 | 12 | 1.0357 | 1.0138 | 153.22 |
| 2 | 新 | 3 | 0.7160 | 0.6904 | 119.85 |
| 3 | 旧 | 12 | 1.0377 | 1.0147 | 150.25 |
| 3 | 新 | 3 | 0.7209 | 0.6938 | 120.35 |
| 中位数 | 旧 | 12 | 1.0377 | 1.0147 | 153.22 |
| 中位数 | 新 | 3 | 0.7197 | 0.6922 | 120.35 |

该小样本的本地准备耗时中位数约减少 31%，CPU 累计用时约减少 32%。这不是全 App CPU 占用率下降承诺，也不能外推到大规模真实站点或弱网。

新模式常驻内存从约 35.49–35.54 MB 增至 43.73–43.78 MB；旧模式第二、三轮约从 35.54–35.55 MB 增至 43.86–43.89 MB，首轮初始内存更高。本次未观察到明显额外常驻内存增长，不据此宣称长期内存稳定。

主队列仍出现约 120 ms 的回调间隔。批量合并减少了总工作量，单次同步计算热点仍存在；若进入阶段 B，应先定位该间隔内的具体加载／导出成本。

### 本地证据

- 临时探针准备脚本：`/tmp/prepare_stage_a_cleanup_probe.py`。
- 临时工程及测量入口：`/tmp/StageACleanupProbe/SunSmart.xcodeproj`、`/tmp/StageACleanupProbe/AppDelegate.swift`。
- 六份原始计数：`/tmp/stage_a_probe_legacy_1.json` 至 `legacy_3.json`，`/tmp/stage_a_probe_batch_1.json` 至 `batch_3.json`。
- 大规模可重复自动化入口：`scripts/check_site_zone_cleanup_batch.py`，参数传入本地 SDK 路径。

## 未验证项与人工检查步骤

真实 App 的以下五个场景尚未完成：启动前断网、请求中断网、有网络但服务器不可达、反复断网恢复、大量待上传 Space 后回前台。现有真机副本只有小规模 Site，探针主动限定为本地工作对照；本次没有建立服务器不可达的网络故障环境，也没有在真实页面上执行触控和 HUD 验证。

建议后续使用可恢复的测试站点及测试网络，每个场景保持相同数据和构建配置：

1. 启动前关闭网络，确认可进入本地页面、加载提示可退出；观察是否有反复本地准备。
2. 上传／时区请求进行中断网，确认失败或业务超时后页面可操作，待上传状态保留；恢复网络后可继续。
3. 在测试网络阻断对应服务器、保持网络连接，记录请求频率及超时期间的主线程和 CPU。
4. 连续多次断网／恢复与回前台，确认任务合并有效，已完成轮次的重复工作频率是否需要阶段 B 降频。
5. 准备大量待上传 Space 和跨 Space Zone 的测试站点，对照总恢复耗时、实际分类器读取数、CPU、内存、触控与 HUD；确认持久化中断后能补做 Site 收尾。

最终体验需人工确认。上述未验证项不得以构建成功、隔离回归或本地探针数据替代。
