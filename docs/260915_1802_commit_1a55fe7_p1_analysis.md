# 1a55fe7 对首次全空间拓扑主线程阻塞的修复核查

## 结论

**未修复原 P1，建议保留该审查项。**

提交 `1a55fe731008ad1b1e8aeece99be41c4412f50c8` 将保护状态文件读取移到后台并在批次中复用，但首次全空间成员扫描、拓扑构建与 Site 目标准备仍由主线程同步执行。6 ms 预算检查依旧发生在单个节点检查返回以后，无法拆分这段重计算。

本次 macOS 隔离复测恢复 SDK 普通组的字符串订阅查询后，500 节点、50 组、每节点 20 个 Model，仅请求首个节点，三轮完整主线程片段均约 **222 ms**；节点检查开始前排入主队列的回调也被延迟约 **222 ms**。

## 范围

- 比较 `1a55fe7` 与父提交 `28b918b2`，只分析原 P1。
- 开始时工作区干净，HEAD 即目标提交；未修改业务代码、SDK、测试或构建配置。
- 读取项目 `AGENTS.md`，结合原审查、实施计划和提交中的验收记录。
- SDK 本地 HEAD 与 workspace 锁定版本均为 `a6246b1b0409824a3227a9c7cad8140219feb182`，相关订阅及地址转换源文件没有未提交差异。

## 代码证据

| 位置 | 当前行为及影响 |
| --- | --- |
| `NodeSyncStatusRefresh.swift` 第 64–71 行 | `step()` 仍由 `DispatchQueue.main.async` 调度，并要求主线程。 |
| 同文件第 83–113 行 | worker 只执行 `request.read()`，即保护状态快照读取；随后回主队列创建 `NodeSyncReadContext`。第 86–87 行注释明确将完整拓扑迁移留给 R3。 |
| 同文件第 157–166 行 | 同步调用 `getNeedSyncGroup()` / `getNeedSync()`，返回后才检查 6 ms。 |
| `Node+SyncData.swift` 第 731、1685–1686 行 | 组同步检查可以进入邻近照明判断，并触发 `ProximityLightingTopologyPlanner.makePlan(for:contextGroup:)`。 |
| `NodeSyncReadContext.swift` 第 126–149 行 | 首次加载 Space、扫描当前组成员；`basePlan` 为空时直接调用 `makePlan(space:)`，完成后才缓存。 |
| `GroupProximityLightingData.swift` 第 291–333、243–260 行 | 从整个空间取得组与节点，对所有符合条件的组生成快照；每组成员判断继续遍历节点、Element、Model，调用 SDK 订阅查询。 |
| `NodeSyncReadContext.swift` 第 157–158 行 | 首次 Site 目标仍同步调用 `localTargetSnapshot(for:)`。真实实现会读取 Site 数据；参与 Site Zone 时还会进入 Site 计划构建。 |
| `NodeSyncStatusRefresh.swift` 第 194、205–209 行 | 请求耗尽后丢弃 context，下个批次仍可能重新触发首次全空间计算。 |

缓存一次基础计划只能减少批次内重复计算，不能约束首次构建占用主线程的时间。此次提交未改动 `GroupProximityLightingData.swift` 和 `SiteTriggerZoneTopologyReader.swift` 的实现。

## 本次复测

### 原有回归

`python3 scripts/check_node_sync_status_refresh.py` 通过：

- 500 节点、14 个读者：1 次计划构建、500 次订阅数组读取，约 0.015 s。
- 15 个压力批次：主线程片段 P95 6.102 ms、最大 8.894 ms。
- 保护文件读取 30 次，主线程读取 0 次。

此结果证明保护读取和批次复用回归通过，不能证明原 P1 消失：

1. `Tests/Group/NodeSyncStatusRefreshTests.swift` 的 Model 使用 `[UInt16]`，`isSubscribed` 直接比较整数；真实 SDK 使用 `[String]`，执行 `subscribe.contains(address.hex)`，普通地址转换使用十六进制格式化。
2. 压力测试第 276–294 行收集并打印片段耗时，断言只约束保护文件读取，没有 P95/最大主线程片段的失败阈值。
3. `SyncSDKSubscriptionTests.swift` 虽使用真实 SDK 的 10,000 个 Model，但在独立方法中验证订阅结果；真机生成器先执行该方法，再运行使用替身的刷新测试。真实字符串成本没有进入该压力刷新链。

### 补充首次节点复测

从当前脚本 `production()` 提取相同的生产刷新器、上下文、邻近照明判断与拓扑代码。复用当前 `stressFixture()`：500 节点、50 个邻近照明组，每组 10 节点，每节点 20 个 Model，均已同步。只请求第一个节点，运行 3 个新批次。

保留整数替身作为对照；另一份临时源将 Model 底层订阅改为字符串，普通组直接查询恢复为字符串包含判断及地址格式化。夹具赋值仍用整数适配接口，转换发生在计时前。没有修改生产调度器或拓扑算法。

通过提交已有的 `AppPerformance` 观察器记录 `SyncNodeCheck`、`SyncTopologyRead`、`SyncMainStep`。在 `SyncNodeComputed` 事件中立即排入另一个主队列回调，测量该回调等候当前节点计算让出主队列的时间。该方法不把后台保护文件等待混入主线程阻塞指标。

环境：macOS 26.6.2（25G83）、arm64、Apple Swift 6.3.3，`swiftc -O -D SUNSMART_PERFORMANCE -parse-as-library`。两种版本按顺序执行，没有并行运行基准。

| 订阅边界 / 轮次 | 单节点检查 ms | 首次拓扑读取 ms | 最大主线程 step ms | 排队主回调等待 ms |
| --- | ---: | ---: | ---: | ---: |
| 整数 / 1 | 7.898 | 7.862 | 7.918 | 7.910 |
| 整数 / 2 | 6.765 | 6.749 | 6.776 | 6.773 |
| 整数 / 3 | 6.296 | 6.285 | 6.302 | 6.302 |
| 字符串 / 1 | 222.331 | 221.828 | 222.351 | 222.346 |
| 字符串 / 2 | 222.423 | 221.987 | 222.435 | 222.433 |
| 字符串 / 3 | 222.407 | 221.960 | 222.421 | 222.419 |

每轮均断言只检查 1 个节点、构建 1 次全空间计划，回调在主线程且同步状态正确。结果表明：一次全空间构建本身仍可以阻塞主队列数百毫秒，即使只请求一个节点。

临时复现源及二进制保存在 `/tmp/review_1a55fe7_p1/`，分别为 `integer.swift` / `integer`、`string.swift` / `string`。这些是隔离边界复测，未链接完整 SDK；Space、数据库版本、其他 Node 业务判断及 Site 数据仍使用原测试替身，不代表完整 App 或实际 iPhone/iPad 耗时。

**不能据此把原审查的约 326 ms 与本次约 222 ms 当作提交前后性能提升。** 两次复测的夹具和编译条件没有建立统一对照；本次数字用于证明当前提交仍可在首次计算中长时间占用主线程。

## 提交内真机证据及完成条件

[R0/R1/R2 验收记录](260915_1752_r012_performance_acceptance.md) 明确写明：只完成 R0～R2，R3～R5 尚未实施；MtestiPhone15 隔离压力测试主线程片段 P95 9.716 ms、最大 9.899 ms，P95 超过计划的 8 ms；首次拓扑、成员/Site 计划迁移仍待 R3。该记录与当前代码一致，不支持将原 P1 标记为已修复。

关闭 P1 至少需要：

1. 落实 [实施计划 R3](260915_1728_ipad_performance_optimization_plan.md)：渐进捕获必要数据，在隔离的不可变输入上后台构建成员索引、基础拓扑和 Site 目标，或把全空间计算本身拆成可让出主队列的步骤。
2. 压力刷新链纳入实际 SDK 字符串订阅成本，并对首次节点、首次准备和完整主线程片段设置耗时验收条件。
3. 按项目真机验证规则，在相关真实数据规模验证最大片段与交互响应；MtestiPhone15 可用于自查，其他个人设备及最终体验由人工确认。

本次只进行代码核查和 macOS 隔离复测，未重新执行完整 Xcode 构建、真机运行、BLE 或云端操作，未使用 Computer Use。真机数据引用提交内已有记录，不表述为本次重新测量。仓库仅新增本文档。
