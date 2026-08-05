# Bugly #7002 EFC Store Race 修复实施总结

## 结论

方案 A 已完成：把 `DeviceEmerFireStore` 的共享设备数组收口到独立的线程安全缓存容器，通过私有 `NSLock` 对 replace、merge、remove 和 snapshot 建立单一并发边界。数据库、Mesh、通知和 proxy filter 操作仍在锁外执行，未扩大锁的业务范围。

本次修复消除了已定位的 `DeviceEmerFireStore.mergeCache(with:)` 并发读写 Swift Array 风险。代码级并发压力测试及 Thread Sanitizer 验证均已通过。

## 实施内容

- 新增 `DeviceEmerFireCache<Element>`，集中保护数组容器访问。
- `DeviceEmerFireStore.devices` 改为返回缓存快照，避免调用方持有并发可变数组。
- `loadDevices`、`mergeCache` 和 `delete` 的缓存写入统一走同步容器。
- 新增独立回归测试，覆盖 replace、merge、remove、snapshot 和并发 merge/read。
- 将缓存回归测试接入现有 EFC controller flow contract 脚本。
- 将新 Swift 文件加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。

## TDD 与并发验证证据

1. 测试先行 RED：只编译测试时失败，明确提示找不到 `DeviceEmerFireCache`。
2. Race RED：临时无锁实现运行 Thread Sanitizer，报告 `Swift access race`，进程以 134 退出。
3. 最小实现 GREEN：加入 `NSLock` 后，普通压力测试通过。
4. TSan GREEN：32 个并发 worker、每个 2,000 次 merge/read 的压力测试通过，未报告 race。
5. EFC contract GREEN：`bash scripts/check_efc_controller_flows.sh` 通过，并执行缓存回归测试。
6. `git diff --check` 通过。

## 构建验证

以下 scheme 均使用 Debug、generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO` 构建成功：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

构建中仍可见部分 Info.plist、重复 Compile Sources 或 AppIntents metadata 警告；本次改动未涉及相应配置，且四个 target 均输出 `BUILD SUCCEEDED`。

## 改动边界

- 未修改 SDK、依赖、本地化、资源或 Auth 信息。
- 未重构 `Group.needSync`、Node 同步缓存、EFC Repository 或 Mesh 并发模型。
- 未执行 Git commit、push 或 merge。
- 当前证据证明已定位的 Store 数组竞争在代码和 TSan 压力测试层面得到修复；尚未完成真机 Groups 页面连续滚动/刷新压力测试，也尚未经过版本发布后的 Bugly 线上观察，因此不能把“构建通过”表述为线上崩溃已归零。

## 建议发布后验收

- 在包含多个 EFC 设备和多个 Group 的真实 Mesh 数据下，连续进入 Groups 页面、快速滚动并反复刷新。
- 同时触发设备缓存刷新或 EFC 数据更新，观察 `needSync` 并发计算。
- 发布后按版本监控 Bugly #7002 及同一 `DeviceEmerFireStore.mergeCache` 特征栈，确认不再新增。
