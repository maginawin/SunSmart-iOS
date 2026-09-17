# 未提交代码审查

## 范围与结论

审查工作区相对 HEAD 的全部代码差异、新增测试及四份未跟踪文档；暂存区无差异。发现一项 P2 性能回归，未修改生产代码或仓库测试。

### P2：首次显示仍逐个 Cell 同步扫描全网成员

- 定位：`GroupsViewCell.refreshOnOffAppearance` 默认传入单个 Group；绑定和 `GroupsViewController.collectionView(_:willDisplay:forItemAt:)` 都调用它。
- 条件：同步上下文未准备好、已失效或不可用，且组未设置本地开关覆盖值。
- `groupOnOffStates` 的成员投影仅在一次调用内共享。因此一次列表显示有 V 个 Cell 时，绑定加显示会执行 2V 次全网成员扫描，并同步占用主线程。旧实现只在异步同步回调内通过已准备好的成员索引读取背景，不执行这些渲染路径上的全网扫描。
- 新增批量测试直接将所有组传给辅助方法，未覆盖实际 Cell 调用方式；`viewWillAppear` 的复用分支虽已批量化，但首次显示和失效重载未覆盖。
- 建议让首次绑定、显示和重载共用本轮成员投影，继续实时读取成员开关，不缓存开关布尔值。按 [AGENTS.md 的性能验证要求](../AGENTS.md#L35) 做针对性真机验证。

## 独立复现

在临时目录中复用现有脚本生成的生产方法体与隔离 SDK/UI 边界，不改仓库测试。创建 500 节点、50 组、每节点 20 个 Model 的数据，清空刷新上下文后，在同一主线程调用中依次绑定并显示 14 个生产 Cell 方法体。

| 成员订阅位置 | 订阅查询次数 | 隔离主线程耗时 |
|---|---:|---:|
| 第一个 Model | 14,000 | 约 8.4 ms |
| 最后一个 Model | 280,000 | 约 85.8 ms |

两种情况均对应 28 次全网扫描。以上耗时来自 macOS 优化编译的隔离夹具，不是真实 iPhone 的页面耗时；查询次数证明了重复扫描路径。

## 已验证

- `python3 scripts/check_node_sync_status_refresh.py`：通过，包含动态 Scheduler 候选与实时外观行为用例。
- `bash scripts/check_groups_tap_target_stability.sh`：通过。
- `bash scripts/check_group_page_ui_refresh_coalescing.sh`：通过；覆盖相关组详情刷新契约，不代替组列表性能测试。
- `git diff --check`：通过。
- 直接运行 `xcodebuild`：SunSmart / Debug / iphoneos / generic iOS / 禁用签名，构建成功；SDK 解析为 release 的 `a6246b1`。
- 沿生产 SDK 核对 `Group.nodes`、`Node.group` 与 `Model.subscriptions` 的成员查询语义；未修改 SDK。
- Scheduler 提交前重新筛选、UUID 去重、当前实例替换、空批次退出与冷却处理未发现本次新增的可报告缺陷。

## 验证边界与人工检查

本次未运行真机 UI、BLE 或端到端性能验证，也未重新构建其余品牌；构建成功和隔离测试不表示 UI 验收通过。

建议在 MtestiPhone15 或人工操作的测试设备上，用大空间验证首次进入 Group、修改配置后返回 Group，以及同步输入不可用时的滚动。分别记录页面主线程耗时，确认绑定与显示不再按 Cell 数量重复扫描全网，同时检查背景即时更新及同步警示保留。
