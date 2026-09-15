# 组开关外观与 Scheduler 补读回归修复计划

## 目标与当前状态

修复提交 `3b8ac616` 审查中的三项 P2：组页面重入背景过期、补读候选过期、同步上下文不可用时关灯背景错误。两个背景问题合并处理，补读问题独立处理。

本次仅核对源码、既有测试及审查记录并制定计划，尚未修改业务代码、执行修复后测试或进行真机验收。此前构建和脚本通过属于历史验证，不能证明这三项回归已经解决。

实施阶段补充：用户随后要求继续修复，并明确本轮不做真机验证，UI、BLE 和实际体验由用户手工验证。以下真机步骤作为交接清单；本轮自动验证范围为生产逻辑回归、iphoneos 编译和静态布局检查。

## 一、问题与修复落点

| 审查问题 | 已核对的原因 | 修复落点 |
|---|---|---|
| 页面复用后仍显示旧开关背景 | `viewWillAppear` 仅在刷新标记或 `SpacePageRevision` 失效时执行 `updateUI`；实时开关并不属于该版本的完整变更来源 | `GroupsViewController` 增加可见 Cell 的实时外观刷新 |
| 等待期间变为已知的节点仍被补读 | `request` 提前保存候选，`step` 在队列空闲后直接从旧 `pending` 取两个节点 | `SpaceSchedulerReadQueue.step` 在每批实际调用 `read` 前重新筛选 |
| 同步不可用时关灯背景变白 | Cell 先设白色，随后依赖 `NodeSyncReadContext.current` 更新背景；`finishUnavailable` 清理上下文后才回调 | `GroupsViewCell` 将背景与异步同步警示分开更新 |

相关语义必须保留：

- `Group.isOn` 优先使用组的本地覆盖值；无覆盖值时由成员实时状态推导；空组沿用现有开启外观。
- 同步读取不可用仍显示同步警示，不把异常状态当作已同步。
- Scheduler 以各 Scheduler Model 的权威缓存判定是否未知；已知空记录也是已知。旧 `schedulerActions` 仅影响优先级。
- 每批最多两个节点、UUID 去重、忙碌等待、30 秒重试冷却、Space 生命周期隔离及 SDK 节点级完整读回语义保持一致。

## 二、修复方案

### A. 合并修复两个组背景问题

#### 1. 独立的实时外观刷新入口

在 `GroupsViewCell` 增加仅更新开关背景的方法，读取当前组的实时开关状态，使用现有白色和灰色。

- 绑定组时即调用，不再把白色作为等待同步结果的统一背景。
- 方法不重新绑定组，不修改名称、图片、删除按钮或同步警示，不发起同步检查。
- 同步回调负责同步图标；背景正确性不再取决于该回调是否成功、是否存在读取上下文。
- 保留请求 ID 校验和 `prepareForReuse` 取消机制，防止旧组回调覆盖新组。
- 现有单击开关及组状态通知会经过 `reloadCollectionItem` 重新绑定 Cell；绑定时应立即体现新的开关值。

#### 2. 页面复用仍刷新实时状态

在 `GroupsViewController.viewWillAppear` 中继续保留版本判断：需要更新数据时执行原有 `updateUI`；复用页面时刷新可见 Cell 的开关背景。

- 实时刷新不调用整页 `reloadData`，不重新发起同步请求，也不人为使配置或同步版本失效。
- 增加 `willDisplay` 的实时背景更新，覆盖滚动后重新显示、预取及布局后才出现的 Cell。
- 可见 Cell 按其绑定的 Group 更新，保持现有点击地址校验、编辑状态和滚动位置。
- 首次显示由绑定路径保证正确背景；重入与再次显示由生命周期路径保证。

#### 3. 保留成员查询的性能收益

`NodeSyncReadContext.current` 只在同步执行作用域内设置，普通页面回调不能假定它存在。另一方面，SDK 的 `group.nodes` 会遍历真实节点并查询成员关系，直接给每个 Cell 增加该调用可能恢复原有热点。

采取以下顺序：

1. 在 `NodeSyncStatusRefresh` 内提供一个很小的同步读取入口，允许实时刷新复用当前有效、已准备且输入可用的上下文。入口只执行读取，不排队、不重新准备、不修改同步结果。
2. 页面批量刷新在同一有效上下文内执行，使用已有成员索引，但每次重新读取成员的 `isOn`，不缓存开关布尔值。
3. 上下文不可用时仍按 `Group.isOn` 的原有语义求值，不能跳过背景刷新，也不能使用失效上下文。
4. 对无上下文回退单独测量成员查询次数和主线程耗时。若可见 Cell 逐个求值形成重复全网扫描，在本修复范围内将本轮成员查询合并为一次临时投影；只提取现有成员/开关求值逻辑，不增加跨会话的第二套长期缓存。必要时局部修改 `MeshNetwork+SunSmart.swift`。

### B. 每批补读前重新校验候选

保留 `request` 的需求合并与优先级选择；`pending` 表示本轮希望读取的节点范围，不代表发送时仍然需要读取。

`step` 的处理顺序：

1. 检查停止状态、Space/网络/账户/区域身份、连接状态和共享 Mesh 忙碌状态；忙碌时沿用延后调度。
2. 共享队列空闲后重新调用候选提供器，获得当前仍满足未知条件的节点，按 UUID 去重建立查找表。
3. 按本轮尚未处理的 `pending` 顺序取交集，检查冷却期限，并使用最新候选对象组装至多两个节点。跳过已知、已移除或已不符合候选条件的节点。
4. 过滤与提交在同一次主队列执行中完成，中间不再异步等待。下一批再次执行相同校验。
5. 候选全部失效时不调用 `read([])`，释放本轮待处理状态并允许后续新需求启动；部分失效时继续查找后面的有效候选。
6. 仅实际提交的节点在完成后进入冷却，且只有真实读回完成才触发 `updated`；跳过节点不制造缓存失效或刷新通知。

本轮仍只消费最初选中的需求范围，新出现的其他候选由后续需求处理，避免候选持续变化形成无限读取。相同 UUID 的候选对象被替换时必须使用当前对象；已处理节点不能在同一轮重新加入。

校验边界是 App 实际提交 SDK 之前。已经交给 SDK 的批次沿用 SDK 原有执行和失败处理，不在本轮引入 SDK 队列取消或 Model 级拆分。

## 三、补齐回归测试

### 现有覆盖缺口

- `Tests/Group/SpaceRuntimeCacheTests.swift` 已执行生产队列，但候选固定，无法覆盖忙碌等待和批次间候选变化。
- `scripts/prepare_node_sync_status_ui_tests.py` 已加载生产 Cell，但用普通布尔变量替换 `Group.isOn`，也未实际加载 `GroupsViewController`。现有通过记录不能证明成员推导及页面重入路径正确。
- `check_group_page_ui_refresh_coalescing.sh` 主要检查组详情 `GroupViewController`，不能替代组列表 `GroupsViewController` 的重入验证。

### Scheduler 行为测试

扩展现有生产队列夹具，使用可变候选、可控忙碌状态和完成回调，按发送记录断言：

| 场景 | 预期 |
|---|---|
| 请求时忙碌，解除忙碌前全部候选变已知 | 发送数为零；无读回通知；后续需求仍能启动 |
| 等待期间部分候选变已知 | 仅发送剩余未知节点，顺序与批大小符合约定 |
| 第一批执行期间，后续节点变为已知 | 后续批次跳过这些节点 |
| 第一段候选全部失效，后面仍有未知节点 | 能继续读取后面的有效节点，不提前结束或空转 |
| 节点被移除，或同 UUID 替换成新对象 | 不使用已移除/旧对象；符合条件时使用当前对象 |
| 已知空缓存、已知非空缓存、仅部分 Model 未知 | 前两类不补读，最后一类仍补读 |
| 重复需求、重复 UUID、失败后快速重入 | 合并需求、不重复发送、冷却有效 |
| 等待时断连、上下文切换、退出后迟到回调 | 无越界发送或旧 Space 发布 |

未知判定测试应执行生产 `TimedSchedulerCacheRepairPolicy` 或候选适配逻辑；仅从测试数组移除对象不能替代 Model 缓存边界测试。确认跳过节点没有被设置重试冷却。

### UI 与实时状态测试

扩展既有真机夹具，执行生产 Cell 及生产开关 getter，去掉以普通布尔变量替代 getter 的测试捷径。

| 场景 | 预期 |
|---|---|
| 无组本地覆盖值，成员最后一盏亮灯关闭 | 刷新后立即显示灰色 |
| 成员从全关变为至少一盏开启 | 刷新后显示白色 |
| 组已有本地覆盖值、空组 | 保持既有 `Group.isOn` 语义 |
| 同步尚未返回、保护读取失败、拓扑不可用 | 开关背景正确；失败回调保留同步警示 |
| 同步不可用时点击开关 | 背景及时更新，警示仍在 |
| A 组请求未完成便复用为 B 组 | A 的迟到回调不能改变 B 的外观 |
| 同步缓存有效时只改变实时开关 | 背景改变，同步计算/准备计数不增加 |
| 多次复用、滚动重新显示、不同卡片尺寸 | 颜色与绑定组一致，图标/文字/删除按钮布局正常 |

控制器行为必须单独覆盖：在实际 App 完成“Group → Main → 关闭最后一盏亮灯 → Group”和反向开启流程，确认配置版本未变且整页未重载时仍更新背景。仅直接调用 Cell 方法不算页面重入验证。

## 四、实施顺序与验证

1. **先固化失败用例**：扩展队列测试和 Cell 真机夹具，确认能暴露原始问题。
2. **修复背景刷新**：Cell 独立入口、控制器复用/显示路径、有效上下文复用；运行相关行为用例。
3. **修复补读队列**：提交前筛选、空批次收尾、当前对象及冷却处理；运行队列完整生命周期用例。
4. **执行针对性回归**：
   - `python3 scripts/check_node_sync_status_refresh.py`。
   - `zsh scripts/check_timed_scheduler_single_owner.sh`。
   - `zsh scripts/check_timed_scheduler_persistence.sh`。
   - `bash scripts/check_groups_tap_target_stability.sh`。
   - `bash scripts/check_group_page_ui_refresh_coalescing.sh`。
   - `python3 scripts/check_sync_task_builders.py`。
   - `git diff --check`。
   - 涉及 SDK 的脚本需记录实际使用的 SDK 路径和版本，并与 App 构建解析版本核对，避免把不同 SDK 版本的通过结果混用。
5. **构建检查**：直接使用 `xcodebuild`，按仓库规定构建 SunSmart / Debug / iphoneos / generic iOS，禁用签名；不使用 shell 包装、日志重定向或 Simulator。因代码由五个品牌共享，依次对 Archipelago、SLG Sync Plus、SylSmart、Lumineux 执行相同配置的编译验证；失败时区分本次代码问题与既有依赖/品牌配置问题。
6. **真机与性能验证**：按以下范围执行，并分别记录结果。

### 真机范围

- 在 `MtestiPhone15` 上复用现有隔离测试工程，运行生产 Cell、异步刷新与布局用例；检查小/大卡片尺寸及英文、中文名称显示。其他个人设备由人工操作。
- 在实际 App 验证页面切换、成员开关、滚动、编辑按钮、同步警示；iPad 六列适配由人工在测试设备检查，隔离尺寸测试不替代 iPad 体验确认。
- 真实 BLE 场景：占用共享 Mesh 队列后进入 Timed，让前台读取先将同节点的 Scheduler Model 变为已知；解除忙碌后确认没有再次提交该节点，其权威缓存保留。另测跨批次状态变化和读回过程中切页。
- 失败场景优先通过隔离夹具注入保护/拓扑读取失败，避免为测试修改真实空间的保护文件。
- 不使用 Computer Use。设备、签名、数据或硬件条件受阻时停止重复尝试，列出已验证项、未验证项及人工复测步骤。

### 性能验收

- 对同一 Space 连续切换至少 10 次，比较修复前后同数据、同构建配置下的页面进入时间和主线程耗时。
- 同步版本未变时，仅刷新开关不增加 `SyncGroupRequest`、`SyncNodeComputed` 或同步保护/拓扑准备次数。
- 正常缓存路径继续复用成员索引；无上下文回退单独记录耗时和订阅查询次数，不能用总平均值掩盖失败路径卡顿。
- 复用已有 500 节点、50 组、每节点 20 个 Model 夹具作对照；历史分片耗时只作参考，不当作本次页面端到端耗时。
- `SchedulerRepairBatch` 只记录实际非空批次，已知节点被跳过时不新增蓝牙发送。新增诊断输出遵守 `#if DEBUG` 规则。

## 五、预计文件范围与完成标准

主要业务文件：

- `SunSmart/Main/Group/Controller/GroupsViewController.swift`。
- `SunSmart/Main/Group/View/GroupsViewCell.swift`。
- `SunSmart/Common/Data/NodeSyncStatusRefresh.swift`：提供有效上下文的同步只读复用入口。
- `SunSmart/Common/Data/SpaceSchedulerReadCoordinator.swift`。
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`：仅在需要合并回退成员查询时局部提取现有开关求值逻辑。

测试优先扩展 `Tests/Group/SpaceRuntimeCacheTests.swift`、`Tests/Group/NodeSyncStatusRefreshTests.swift`、`scripts/check_node_sync_status_refresh.py` 和 `scripts/prepare_node_sync_status_ui_tests.py`。本轮预计沿用已有 SDK、资源、国际化 Key 和 target 配置。

完成标准：三项原始复现场景均得到验证；同步不可用仍保持警示；缓存复用、成员开关语义、队列冷却和退出隔离无回归；针对性测试与品牌编译结果明确；真机 UI、真实 BLE 和性能结果单独记录。最终体验由人工确认，不能仅凭构建或截图宣称 UI 验收通过。

实施完成后另存带时间戳的总结，列出实际变更、测试结果与剩余人工检查项。

## 参考

- [原提交审查](260915_2113_commit_3b8ac61_review.md)。
- [Space 运行时缓存实施结果](260915_2104_space_runtime_cache_implementation.md)。
