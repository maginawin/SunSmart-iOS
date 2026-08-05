# Bugly #7002 EFC Store 并发崩溃分析与修复方案

## 1. 结论

Bugly #7002 的直接原因是 `DeviceEmerFireStore` 的共享 `devices` 数组被多个 GCD worker 并发修改，触发 Swift `Array` 存储与对象引用计数破坏，最终以 `SIGABRT` 结束。

这不是 `DeviceEmerFireData` 自定义析构逻辑、整数加法或业务配置值越界导致的崩溃。`DeviceEmerFireData` 没有自定义 `deinit`；堆栈中的符号经 `swift-demangle` 确认为编译器生成的 `DeviceEmerFireData.__deallocating_deinit`。对象是在 `mergeCache` 替换数组元素、释放旧对象时成为崩溃表象。

当前 `fix` 分支 HEAD 为 `4df31ef6`。截至该版本，导致竞态的后台调用和无同步共享数组写入都仍存在，因此结论是：**当前源码仍然存在该缺陷**。

Bugly 日志未提供崩溃包的版本号、commit 或 dSYM UUID，所以不能仅凭此日志断言崩溃包就是当前 HEAD；但当前源码保留了与堆栈逐层一致的可崩溃路径。

## 2. 堆栈与当前源码映射

| 堆栈 | 当前源码 | 含义 |
| --- | --- | --- |
| `GroupsViewCell.group.didSet` | `GroupsViewCell.swift:33-41` | 每个可见 Group cell 都向全局并发队列提交一次同步态计算 |
| `Group.needSync` | `MeshNetwork+SunSmart.swift:1161-1164` | 遍历组内节点并读取 `needSyncGroupData` |
| `Node.getNeedSyncGroup` | `Node+SyncData.swift:656-716` | 当前节点没有更早的未同步项时，继续检查 EFC 关联同步 |
| `makeNodeAssociationSyncs` | `EmergencyFireControllerSyncPlanner.swift:100-130` | 查找影响当前 Group 的 EFC controller |
| `controllersAffecting` | `EmergencyFireControllerSyncPlanner.swift:49-62` | 调用共享 Store 的 `devices(in:)` |
| `DeviceEmerFireStore.devices(in:)` | `DeviceEmerFireData.swift:38-50` | 每次从数据库创建新的 `DeviceEmerFireData` 对象，再合并缓存 |
| `mergeCache` | `DeviceEmerFireData.swift:212-219` | 对共享数组执行 `firstIndex`、元素替换或 `append`，没有锁或串行队列 |
| `DeviceEmerFireData.__deallocating_deinit` | 编译器生成 | 数组元素被新对象替换时释放旧对象；并发写破坏后在这里暴露 |

关键时间线：

- `GroupsViewCell` 从 2025-03-06 起在全局并发队列读取 `group.needSync`。
- EFC Store 的 `devices` 与 `mergeCache` 自 2026-04-29 起就是无同步共享可变数组。
- commit `aef31fad` 在 2026-06-24 将 EFC 关联检查接入 `getNeedSyncGroup`，把上述两个原本分离的条件连成当前崩溃链。
- 从 `aef31fad` 到当前 HEAD，相关 Store 并发边界和 Group cell 调度方式没有被修复。

## 3. 为什么会在析构阶段崩溃

`DeviceEmerFireRepository.load` 每次读取都会创建一批新的 `DeviceEmerFireData` 实例。多个 Group cell 同时计算同步态时，会并发执行以下语义：

1. 在同一个共享数组里查找相同 controller id；
2. 多个线程几乎同时得到同一个数组下标；
3. 多个线程同时用各自新加载的对象替换该元素；
4. 替换动作并发释放旧引用，同时还可能修改同一份 `_ContiguousArrayStorage`；
5. Swift 独占访问、数组存储或 ARC 引用计数被破坏，随后在对象或数组 storage 析构时 abort。

堆栈中的 `_swift_release_dealloc`、`RefCounts.doDecrementSlow`、`DeviceEmerFireData.__deallocating_deinit` 和 `mergeCache` closure 正好符合该过程。`swift_initStackObject`、`AdditiveArithmetic.+`、`_ContiguousArrayStorage<Int8>` 更接近内存/元数据已受破坏后的运行时表象，不应沿这些符号去修改业务加法或 `Int8` 数据。

## 4. 同构动态验证

已在 `/tmp` 使用与当前 `mergeCache` 相同的“共享对象数组 + `firstIndex` + 同 id 元素替换/追加”模式做独立 Swift 压测：32 个 GCD worker，每个 worker 重复合并 2,000 次。

结果：

- Thread Sanitizer 立即报告 `Swift access race` 和数组元素读写 data race；
- 随后进程在 `_ContiguousArrayStorage.__deallocating_deinit`、`_swift_release_dealloc`、`RefCounts.doDecrementSlow` 和 `merge` closure 链路出现 `BUS` 并 abort；
- 该验证没有依赖 App 数据库、Mesh 或 UI，因此证明的是当前缓存算法本身不支持堆栈中已经存在的并发调用方式。

临时诊断源码和二进制已删除，没有写入工程。

## 5. 快速重现方法

### 5.1 真实 App 路径

准备条件：

1. 当前 Space 至少有 1 条已持久化 EFC controller 记录。是否已经关联灯组不影响 `mergeCache` 被执行，但绑定真实 controller 更接近线上数据。
2. 创建较多可见 Group；iPad 每行 6 个 cell，比 iPhone 更容易同时提交任务。
3. 每个 Group 至少有 1 个已完成 key bind、且 Profile、Scene、Scheduled、Switch、Proximity Lighting 等更早同步检查均已对齐的 Light 节点。这样 `getNeedSyncGroup` 会走到最后的 EFC 检查，而不是提前返回。
4. 冷启动或确保这些节点的 `cacheGroupNeedSync` 尚未命中。

操作步骤：

1. 进入目标 Space 的 Groups 页面。
2. 反复返回并再次进入 Groups，或触发页面 `updateUI/reloadData`，同时快速滚动，让多个 cell 重复执行 `group.didSet`。
3. 重复 20～100 轮。慢速设备、更多 Group 和更多 EFC 记录会扩大竞态窗口。
4. 预期崩溃堆栈落在 `GroupsViewCell -> Group.needSync -> Node.getNeedSyncGroup -> EFC Planner -> DeviceEmerFireStore.mergeCache`，末端可能是 `DeviceEmerFireData` 或 `_ContiguousArrayStorage` 析构。

这是真机业务路径，但竞态崩溃不是每轮必现。

### 5.2 最快的确定性开发复现

在不依赖真实 Mesh 的独立诊断 harness 中，对与 Store 相同的缓存合并逻辑发起 32 路并发、每路 2,000 次同 id 替换，并启用 Thread Sanitizer。修复前应立刻报告 race，且高概率在数组 storage/对象释放阶段崩溃；修复后应无 race、最终只保留一个对应 id。

该 harness 适合证明缓存并发边界；真实 App 修复仍需按 5.1 做真机回归，不能把独立压测等同于完整业务验收。

## 6. 修复方案比较

### 方案 A：同步 Store 缓存访问，推荐

在 `DeviceEmerFireStore` 内建立唯一的缓存并发边界：

- 将共享数组改为真正私有的 backing storage，外部和 Store 其他逻辑只能取得数组快照；
- 使用一把私有锁保护所有缓存赋值、查找、替换、追加、删除和快照读取；
- 锁只覆盖内存数组临界区，不把数据库访问、MeshNetwork 操作、通知发送或 proxy filter 刷新包在锁内，避免阻塞和重入死锁；
- `loadDevices`、`devices(in:)`、`save`、`delete`、`ensurePublishGroupIfNeeded` 全部通过同一缓存原语更新，不保留绕过路径；
- 保持现有 `GroupsViewCell` 后台同步态计算和 EFC 业务语义不变。

优点：直接修复共享可变状态根因；改动集中；不引入主线程数据库/同步态计算卡顿；其他保存、删除、导入和后台读取路径同时受保护。

代价：需要严格审计 Store 内全部访问点；锁只能保证缓存容器安全，不代表任意 `DeviceEmerFireData` 实例可在多线程随意修改，因此仍需保持业务对象修改的现有线程约束。

### 方案 B：删除 Store 内存缓存

移除当前未被外部直接读取的 `devices` 数组，让查询直接返回 Repository 结果，保存/删除只落库和发通知。

优点：从结构上消除本次共享数组竞态，代码量可能更少。

代价：改变 Store 生命周期语义；需要重新核实绑定、自动补齐真实 EFC、publish group、Space 切换、导入和通知刷新是否依赖缓存对象身份。当前任务缺少证据证明缓存可以安全删除，风险高于方案 A。

### 方案 C：只串行化 `GroupsViewCell` 调用

把每个 cell 的全局并发计算改成单一串行队列或主线程计算。

优点：改动最小，能降低当前堆栈路径的并发度。

代价：只封堵一个入口；Store 仍可能被 Space 加载、同步回调、保存、删除、导入或其他后台任务并发访问。主线程计算还可能造成 Groups 页面卡顿。该方案适合临时止血，不适合作为最终修复。

## 7. 推荐实施范围

推荐采用方案 A，保持改动聚焦：

1. 修改 `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift`，收口并同步缓存访问。
2. 新增 `Tests/Device/DeviceEmerFireStoreConcurrencyContractTests.swift`，覆盖缓存只能经同步原语访问、所有写入口均受保护等确定性源码契约。
3. 扩展 `scripts/check_efc_controller_flows.sh`，防止未来重新出现直接数组写入或绕过同步原语。
4. 使用独立并发 stress harness 验证同 id 替换、不同 id 追加、删除与快照并发时不再出现 TSan race，且结果无重复 id。
5. 真机按第 5.1 节重复进入/刷新 Groups 页面，验证不再崩溃，并确认每个 Group 的 sync failed 图标仍与实际同步任务一致。

本次不建议顺手重构 `Group.needSync`、Node 同步缓存、EFC Repository 或整个 Mesh 并发模型。若修复后 Thread Sanitizer 或新崩溃继续指向 Repository/SQLite/MeshNetwork，再基于新证据单独立项。

## 8. 验证矩阵

### 静态与自动化

- 新增并发边界 contract 通过。
- `scripts/check_efc_controller_flows.sh` 全部通过。
- `git diff --check` 通过。
- 检查没有新增 Auth、硬编码用户文案、本地化或资源变更。

### 构建

`DeviceEmerFireData.swift` 属于共享业务代码，需要用 generic iPhoneOS、关闭签名的方式分别构建：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

不使用 Simulator 作为构建校验。

### 真机业务回归

- 无 EFC、无 Group、单 Group、多 Group、多 EFC 数据集均能正常进入 Groups。
- 冷启动首次进入、多次返回再进入、快速滚动、EFC 配置变更触发 reload 均不崩溃。
- 有 EFC 待关联/清理任务时显示 sync failed 图标；完全同步时不误显示。
- EFC 新增、编辑、保存、删除、导入、Space 切换后列表和同步态仍正确。

### 验收边界

静态 contract、并发 harness 和四 target 构建只能证明源码约束、缓存算法及编译兼容性，不能替代真机页面压力回归。Bugly 上是否彻底归零还需要带修复 commit/version 发布后持续观察。

## 9. 待确认

建议确认采用方案 A 后，再按 TDD 顺序编写详细实施计划并修改代码。本分析阶段未修改任何业务源码。
