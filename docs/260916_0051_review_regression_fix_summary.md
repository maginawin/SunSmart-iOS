# 组实时背景与 Scheduler 补读回归修复结果

## 结论

提交 `3b8ac616` 审查中的三项 P2 已在当前工作区完成代码修复。新增行为回归与已有针对性脚本通过，五个品牌的 Debug / iphoneos 构建通过。尚未提交 Git。

按用户最新要求，本轮不做真机验证，实际 UI、BLE 和性能体验由用户手工验证。以下自动化结果不代表真机验收通过。

## 变更

### 1. 页面复用时更新实时开关背景

- `GroupsViewController` 在配置版本未变、复用列表时批量更新可见 Cell 的开关背景；`willDisplay` 更新重新显示的 Cell。
- `GroupsViewCell` 绑定组时立即更新背景，异步同步回调只负责警示图标。背景不再依赖同步上下文是否存在。
- 实时刷新不重新绑定组，不重新请求同步状态，也不使同步缓存失效。请求 ID 与复用取消机制保持有效。
- 布局约束、圆角、图片/文字位置、删除按钮及手机三列/iPad 六列计算均未修改；已静态核对，实际布局由用户验证。

### 2. 实时开关读取复用成员关系

- `NodeSyncStatusRefresh.groupOnOffStates` 仅复用有效且准备完成的成员索引，每次重新读取成员开关。
- 上下文不可用时，一个批量调用共用一次临时成员投影；仅有组本地开关覆盖值时不查询成员。该投影不跨调用保留。
- `Group.isOn` 的求值局部提取为接受成员集合的方法，保留本地覆盖优先、成员任一开启、空组默认开启的原有语义。
- 首次绑定或单个 Cell 再次显示时，若无有效上下文，仍可能进行一次成员投影；未将隔离测试结果当作真实大空间的页面耗时结论。

### 3. 每批补读前重新筛选

- Mesh 空闲后重新取得当前未知候选，与本轮未处理 UUID 求交集，使用当前节点对象提交。
- 已知、已移除的候选被跳过，继续寻找后面的有效节点；空批次直接收尾，不触发读回或更新通知。
- 保留每批最多两个节点、优先顺序、去重、失败冷却和 Space 退出/切换隔离。跳过的节点不会进入冷却。
- 保留 SDK 完整读回及失败处理；校验发生在 App 提交 SDK 前，不取消已经提交的 SDK 批次。

## 回归覆盖与结果

先添加可变候选用例，在原生产队列上得到失败：`known candidates were dispatched after Mesh busy wait`。加入发送前筛选后通过。

| 检查 | 结果与范围 |
|---|---|
| `check_node_sync_status_refresh.py` | 通过；执行生产队列、开关 getter、同步读取与提取自生产源码的 Cell 绑定/控制器刷新逻辑 |
| 动态补读候选 | 全部/部分变已知、跨批次变化、前缀失效、对象替换、节点移除、UUID 去重、后续新需求、冷却、断连及旧 Space 停止均通过 |
| Scheduler 缓存边界 | 使用生产未知判定策略；已知空和已知非空均排除，部分 Model 未知仍读取 |
| 实时背景行为 | 页面复用不重载仍更新背景、重新显示更新背景、不可用回调保留灰色及警示、Cell 复用、配置变更仍重载均通过 |
| 成员读取性能约束 | 500 节点/50 组/每节点 20 个 Model 夹具：回退批量读取的订阅查询数等于一次成员扫描；缓存有效时连续十次读取不增加成员订阅查询、同步计算或拓扑计划次数 |
| `check_timed_scheduler_single_owner.sh` | owner 策略和接入契约通过 |
| `check_timed_scheduler_persistence.sh` | Scheduler 缓存持久化及完整读回结果判定通过 |
| `check_groups_tap_target_stability.sh` | 组点击目标稳定性契约通过 |
| `check_group_page_ui_refresh_coalescing.sh` | 组详情刷新合并契约通过；这是相关模块检查，组列表重入另由新增用例覆盖 |
| `check_sync_task_builders.py` | 同步计划、成功/重试矩阵、恢复范围通过；输出已有的不可达 default 分支警告 |
| `git diff --check` | 通过 |

新增 `Tests/Group/GroupsLiveAppearanceTests.swift` 使用 macOS 上的最小 UI 属性替身承接颜色和图标，执行实际生产方法体，不包含真实 UIKit 布局或页面转场。脚本仍使用隔离 SDK/数据库边界；它验证 App 决策逻辑，不执行 BLE。

`prepare_node_sync_status_ui_tests.py` 已改为使用生产开关 getter，移除了普通布尔变量替代。生成的隔离工程位于 `/tmp/GroupsLiveAppearance_20260916`，iphoneos 编译通过，未安装或运行。首次编译被沙箱阻止解析 Swift Package，经授权在沙箱外重试后通过。

## 构建

直接执行 `xcodebuild`，使用各品牌 scheme、Debug、iphoneos、generic iOS，禁用签名，无 shell 包装或日志重定向。

| 品牌 | 结果 |
|---|---|
| SunSmart | BUILD SUCCEEDED |
| Archipelago | BUILD SUCCEEDED |
| SLG Sync Plus | BUILD SUCCEEDED |
| SylSmart | BUILD SUCCEEDED |
| Lumineux | BUILD SUCCEEDED |

App 构建及 SDK 相关回归统一使用 `a6246b1b0409824a3227a9c7cad8140219feb182`。脚本显式使用 App 构建对应 checkout：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-daptuisfpzdovoggqsjkgzqtucdv/SourcePackages/checkouts/nordic-sig-mesh-sdk`。没有修改 SDK、依赖版本、品牌资源、国际化文案或 target 配置。

## 用户手工检查

1. **切页后的背景**：选择本次会话中尚未点过组开关的组，保留至少一盏亮灯。先显示 Group，再到 Main 关闭组内最后一盏亮灯，返回 Group 应立即显示灰色；在 Main 开启一个成员后返回应显示白色。滚动离开再回来也应一致。
2. **同步警示下的开关**：若测试环境出现同步读取不可用，已关闭的组仍应为灰色，同时保留同步警示；点击组开关后颜色及时改变。无需为测试破坏真实空间的保护文件，不可用故障分支已有隔离逻辑用例覆盖。
3. **补读候选变化**：共享 Mesh 队列忙碌时进入 Timed，让前台操作先完成同节点权威读取；结合 SDK 发送日志或抓包确认后台不再重复补读该节点，已知 Model 缓存保留。第一批读取期间让后续节点变已知，也应跳过后续节点。
4. **基本交互与适配**：连续切换 Main/Group/Timed、滚动、开关、编辑/退出编辑；检查同步警示、文字、图片和删除按钮。iPad 检查六列布局；真实大空间比较切页和滚动是否卡顿。断连、退出 Space 后确认后台补读停止继续提交。

已完成代码修复与本轮约定的自动验证；真实 UI 布局、BLE 通信及端到端性能尚未验证，最终体验由用户确认。

## 关联

- [原审查](260915_2113_commit_3b8ac61_review.md)。
- [修复计划及真机验证范围调整](260916_0033_review_regression_fix_plan.md)。
