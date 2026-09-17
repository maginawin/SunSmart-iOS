# 启动恢复反复导出与 CPU 占用修复

日期：2026-09-15。问题设备：Jesse（iPhone 13）。

## 已确认的代码问题

- `CloudSynchronizationManager.resumePendingSynchronizations()` 在网络恢复、App 激活时遍历所有 Site/Space，没有待处理状态筛选。
- 每个没有运行中云同步任务的 Space 都进入 `SpaceSyncCleanupCoordinator.prepare`；正常完成路径包含清理前导出和持久化读回导出，与用户日志中同一 Space 连续两组 `export` 相符。
- `SpaceData.export` 的主要组装在 MainActor 执行，计时从前置 Mesh 加载之后才开始；日志的 2–3 ms 不能代表整个清理成本。
- `PJUIDebug` 的 tap 输出来自窗口点击探针，未调用导出。
- `SpaceSyncCleanupCoordinator.perform` 收尾调用 `SiteTriggerZoneCoordinator.cleanObsoleteMembers`；旧 `cleanupClassifier` 创建时立即加载该 Site 全部可编辑 Space 的 Mesh、Group 信息和拓扑。每完成一个 Space 又重复整站扫描，即使 Site 没有 Zone 成员，造成扫描次数随 Space 数量呈平方增长。
- 当前代码未发现这段恢复逻辑本身存在无限循环。大量不同 Space 的有限全量扫描也会表现为长时间持续打印；是否还有其他 CPU 热点须以真机采样判断。

## Jesse 真机采样

对仍运行旧代码的 SunSmart（PID 30758）附加 Time Profiler，没有重启 App。设备 iPhone 13、iOS 26.3，采样窗口 11:25:39–11:25:50，总时长约 10.87 秒。

- 主线程累计采样权重约 **10.199 秒**，全部包含 `SpaceSyncCleanupCoordinator.perform → cleanObsoleteMembers → cleanupClassifier`，其中约 **10.163 秒**包含 `MeshNetwork.load`。调用栈涉及 ApplicationKey 解码、密钥派生、AES 等。
- 另一个线程约 **9.494 秒**，主要在 `libRPAC.dylib` 的 `__generateCulledBacktrace_block_invoke_2`、`dladdr`、`findClosestSymbol`。这是运行库回溯符号解析，不能称为后台 Mesh 计算，也没有证据将其等同于 PJUIDebug 点击输出。
- 多线程累计采样权重可以超过墙钟时间，与用户报告接近两个 CPU 核心的占用一致；上述权重不是修复后的 CPU 百分比。
- 原始采样 `/tmp/jesse-startup-before-2609151124.trace`；解析结果 `/tmp/jesse-startup-before-profile.xml`，仅在本机暂存。

## 修复范围

- 启动/前台恢复只清理待上传、有未确认上传或恢复受阻的 Space；已同步且正常的 Space 不再进入完整导出。
- 候选 Space 之间交还主队列；恢复后重新检查账号、区域、网络以及是否已有运行中的同步任务。
- Zone 清理分类器改为按合法成员的 Space ID 延迟加载，单次分类器内复用成功/失败结果。空 Zone、无效成员、无关 Space 不触发 Mesh 读取；新一次清理重新读取，不引入跨操作缓存。
- 继续保留访问权限、恢复阻断、拓扑完整性检查及 `.unknown` 成员；仅删除已确认过期的引用。
- 进入 Space、手动设备同步和正式云上传的完整清理/校验入口保留。历史无标记配置的完整检查延后至实际进入或同步该 Space。
- 不改动 SDK、本地化、UI 布局、品牌配置或日志开关。

## 验证记录

- 增补现有启动恢复执行测试的依赖替身；直接抽取并编译生产恢复方法。
- 旧代码运行新增用例失败：300 个已同步 Space 仍然进入清理。
- 修复后 `check_startup_ownership_loading.py` 通过：已同步 Space 跳过；待上传、未确认上传和受阻候选保留；运行中任务排除；账号/区域切换、恢复合并及主队列交还通过。真实 SQLite 5001 行身份投影约 0.0063 秒，此数字仅代表测试机器上的 SQL 投影。
- `check_site_zone_cleanup_loading.py` 通过：300 个 Space / 100 个空 Zone 为零 Mesh 读取；同一被引用 Space 只读一次；失败读取缓存；跨操作重新加载；有效、失效及未知成员分类保留原有安全边界。
- 将同一分类器回归用例编译到 HEAD 旧实现，断言“空 Zone 必须零 Mesh 读取”失败；新实现通过，证明确实覆盖此次重复加载问题。
- `check_space_sync_cleanup.py`、`check_site_trigger_zones.sh` 全部通过。
- 最新 `SunSmart` Debug generic iPhoneOS 无签名构建成功，`git diff --check` 通过。共享业务源码同时影响其他品牌；本次未改动资源、依赖、SDK 或 target 配置，未执行全品牌构建。
- Jesse 目标的 Debug 真机签名构建也成功；签名包位于 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-daptuisfpzdovoggqsjkgzqtucdv/Build/Products/Debug-iphoneos/SunSmart.app`。
- Jesse 修复后原机 CPU 尚未复测，不能宣称卡顿已经通过真机验收。根据 AGENTS.md“其他个人设备默认由人工操作”，安装/重启这台手机的 App 需用户明确授权或由用户自行运行。当前仅完成旧版本只读采样。
- 用户已选择自行在 Jesse 运行修复版后通知。未执行安装、重启或修复后采样；后续核对启动恢复导出是否持续、空闲 CPU、Sites 列表操作响应，必要时在相同调试配置下再次采样。旧采样同时包含 libRPAC 回溯解析开销，不应把脱离 Xcode 调试的 CPU 数值直接当作同条件对照。
