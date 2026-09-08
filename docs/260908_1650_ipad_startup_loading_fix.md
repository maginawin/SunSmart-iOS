# iPad 启动持续转圈修复

日期：2026-09-08。工作区：fix。

## 问题与实际改动

用户的现场栈停在主线程上的 resumePendingSynchronizations → SiteDeviceOwnershipReconciler → MeshNetwork.load → Node.load → Element/Model JSONDecoder。原恢复入口在判定是否需要修复之前就完整加载每个空间的 Mesh；DevicePermanentDeletionContext.resume 即使删除日志为空也再次加载 Mesh。HTTP 完成日志与 HUD 清理同样依赖主队列，因而会被这些同步工作延迟。

本次在 App 侧消除无必要的完整加载，保留真正有待恢复记录或跨空间身份冲突时的原有安全处理：

- 设备归属核对先检查待删除记录。没有待处理记录且正常空间不足两个时，直接结束。
- 多空间场所使用独立只读 SQLite 连接，仅按 meshUUID 查询 subnetworkId、macAddress；按当前正常空间范围检查规范化 MAC 是否跨空间重复，同时包含当前内存中的有效节点身份。不会读取 Element/Model JSON，也不会创建数据库、修改 SDK schema 或写入 Mesh 状态。
- 轻量查询失败时保守回到完整核对，不把读取失败当成“无需修复”。同空间重复 MAC、其他场所同 MAC、非法 MAC 不应引发错误的跨空间判断。
- 空、全部完成或仅包含当前正在执行条目的删除日志不再加载完整 Mesh。真实未完成删除及替代记录继续恢复。
- 完整核对保留加载出的所有 MeshNetwork，避免 Node/Group 的 weak network 链接在循环后失效；先完成删除恢复，再读取用于归属核对的节点，避免使用恢复前的旧对象集合。
- 启动恢复按账户/地区合并正在执行的重复触发；旧任务结束不能释放替代任务的 gate。主队列在恢复前和场所之间有明确的异步交接，异步返回后再次检查账户、地区、网络和任务身份，并重新读取场所。

## 范围与限制

- 复用现有公共代码文件的五品牌 target membership；没有更改 SDK、依赖版本、资源、用户文案或布局。
- 工程继续使用 Package.resolved 中 release 的 86f5ec9e40148b9cd93e0512702337fcec41dd40；只读投影的表名和字段已对照该版本。
- 这次没有把带删除/写入行为的完整核对直接移到后台。发现真实跨空间冲突、待删除记录或预检读取失败时，仍执行原有完整核对；这些路径可能有较高耗时，不能把普通启动的轻量查询数据作为其性能保证。
- 5,001 行查询耗时来自本机测试，不能代表该 iPad 的实测启动时间。尚未在用户 iPad 的原始数据库上复测。

## 自动验证

1. `python3 scripts/check_proximity_scoped_import.py --baseline`：旧代码失败于新增断言“empty deletion journal must not decode any Mesh”，证明旧路径存在无必要加载。
2. `python3 scripts/check_proximity_scoped_import.py`：通过。执行生产核对/删除恢复逻辑，覆盖单空间与多空间无冲突时零 Mesh 加载、读取失败保守回退，以及替代设备、失败重试、时钟回拨、Scene/Scheduler/Path/Zone 清理与跨场所隔离。
3. `python3 scripts/check_startup_ownership_loading.py <resolved-sdk-checkout>`：通过。编译实际 SQLite 投影、任务 gate 和启动恢复函数，验证真实 SQLite 5,001 行、无模型数据读取、只读文件访问、场所隔离、触发合并、主队列交接、异步期间地区切换和旧任务不能释放新 gate。本机投影查询约 0.00494 秒。
4. `zsh scripts/check_device_permanent_deletion_cleanup.sh`：通过。
5. `bash scripts/check_configuration_database_safety.sh <resolved-sdk-checkout>`：通过真实 SQLite WAL 快照、事务回滚、失败 checkpoint 和旧 schema 保存回归。

本次测试使用的 resolved SDK checkout 为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-dzyljvihefrinmercupzevgsnzly/SourcePackages/checkouts/nordic-sig-mesh-sdk`，已核实 revision 与工程 pin 一致。

## 构建

直接执行 xcodebuild，Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO；没有使用 Simulator 或 shell 日志重定向。

- SunSmart：通过。
- Archipelago：通过。
- SLG Sync Plus：通过。
- SylSmart：通过。
- Lumineux：通过。

五个构建均成功退出。构建仍有重复资源名称、旧 UIKit API 等警告；此次未修改这些无关资源或第三方文件。`git diff --check` 通过。

## 真机验收

在原 iPad 保留原数据重新运行，确认 Sites 页面加载结束、点击可响应，HTTP Response/Failure 日志能够继续输出。若出现 `[SiteDeviceOwnership] phase=preflight ... needsRepair=true` 或 `result=unavailable`，需结合后续 `phase=reconcile` 耗时和现场栈检查实际恢复数据；不能只凭构建通过宣称该设备已恢复。

未提交或推送 Git。
