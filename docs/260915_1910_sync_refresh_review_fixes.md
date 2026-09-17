# 同步刷新竞态与网络回归编译修复

## 结果

已修复 [1a55fe7 审查](260915_1803_review_1a55fe7.md) 中的两项 P2：写入完成后的同步刷新请求被旧保护快照错误结束，以及网络响应独立回归脚本缺少 `AppPerformance` 编译依赖。

## 修改

### 保护快照失效后的刷新

`SunSmart/Common/Data/NodeSyncStatusRefresh.swift` 在后台保护读取返回主队列后，先读取当前保护代数，再分情况处理：

- 当前仍有写入：按原有保护行为结束请求，返回需要同步，避免循环重试。
- 当前已无写入，但快照版本已过期（包括读取时有写入、现在写入已结束）：保留所有待处理请求，清理旧上下文并重新排队读取。
- 快照版本仍有效，但文件读取失败：继续返回保护结果。

这样，导入或清理完成后提交的新请求、同一 owner 替换后的请求，以及仍等待完成的请求，都会根据重新读取的保护状态计算结果。取消请求仍不回调。

### 网络响应回归脚本

`scripts/check_network_response_queue.py` 的独立 `swiftc` 源文件列表加入生产文件 `SunSmart/Common/Data/AppPerformance.swift`，恢复两个网络回调适配器的回归执行。

本次依赖补充仅影响独立测试 runner；未修改 App 依赖声明、品牌 target 配置、资源、本地化或 SDK。

## 回归覆盖

`Tests/Group/NodeSyncStatusRefreshTests.swift` 使用已有性能观察器和信号量控制真实保护读取器的执行时序，不替换刷新算法：

1. 保护读取已完成、尚未回主队列时，清理完成并提交新请求。
2. 保护文件读取过程中，清理完成并提交新请求。
3. 读取开始时存在写入，但主队列处理快照前写入结束。
4. 写入持续进行时，刷新返回保护结果且不重复读取；写入结束后的普通刷新恢复正常。

前三种情况同时验证待处理、新增、替换与取消请求，并断言只补读一次保护快照、各节点只检查一次、同步缓存正确发布。原有不可读保护文件用例继续通过。

## 验证结果

| 验证 | 结果 |
| --- | --- |
| 修复前的网络响应脚本 | 复现 `cannot find 'AppPerformance' in scope` |
| 新增用例搭配修复前的刷新器 | 按预期失败；非优化对照明确报 `pending request used stale protection` |
| `python3 scripts/check_node_sync_status_refresh.py` | 通过，包含新增竞态、取消和保护行为用例 |
| `python3 scripts/check_network_response_queue.py` | 通过；后台解析、主线程成功/失败回调、业务错误映射均通过 |
| `python3 scripts/check_space_protection_snapshot.py` | 通过；真实保护文件、损坏/权限/身份、待处理标记与写入保护均通过 |
| SunSmart Debug、iphoneos、generic/platform=iOS、关闭签名的直接 `xcodebuild` | `BUILD SUCCEEDED` |
| `git diff --check` | 通过 |

非优化对照编译首次被沙箱阻止写入系统模块缓存，获准重跑后完成验证。对照使用临时文件中的旧刷新器，未回退工作区修改。

## 验证边界

- 本次执行 macOS 隔离回归和 SunSmart iPhoneOS 构建；未执行其他品牌构建、真机 UI、真实云端、BLE 或完整导入/清理流程。
- 本次没有布局修改，也不据此宣称完成真机 UI 验收或性能问题修复。
- 人工可在 MtestiPhone15 上检查：成功导入或清理后刷新 Groups/Devices，同步图标应与实际待同步内容一致，无需额外刷新才能纠正状态。
