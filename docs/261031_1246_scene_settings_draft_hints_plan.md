# Scene Settings 草稿提示优化：方案与实施记录

日期：2026-10-31。状态：用户已确认方案；App 修改、相关回归与 SunSmart generic iOS 构建已完成，真实 UI 待人工验收。

## 结论与需求口径

需求合理，建议以“是否存在尚未保存的配置内容”统一控制提示，而不是以设备是否在线、设备数量、revision 是否变化、正式同步队列是否为空判断。

- Devices Settings：没有未保存修改时隐藏整个 Preview 提示卡片（图标、标题、说明及卡片内操作），收起占位；保留 Selected devices 工具栏及 Preview 按钮。
- 有未保存修改且仍有设备成员时，沿用现有 Preview 状态：需要预览、准备中、发送中、失败/中断；成功后仍隐藏卡片。Preview 成功不等于保存，退出仍需要确认。
- Settings 关闭：没有未保存修改则直接退出；有未保存修改才显示 Discard settings?。建议此规则同时适用于 Groups 和 Devices，两者共用编辑器与关闭入口。
- 已保存但尚未同步的 write/remove pending 不属于本次草稿，不触发上述两种提醒；DONE 仍可进入同步页处理已有任务。
- 删除最后一台设备仍属于未保存修改，关闭要确认；由于没有预览对象，保持现有空页，不显示 Preview 卡片。

用户已确认上述口径及 Groups 的关闭行为联动。另已确认：仅有历史待同步任务时，DONE 仍进入 Sync device(s)，不重新保存或重建已有任务。

## 已证实的实现与原因

1. `SceneSettingsViewController` 由 Scene 详情 Settings、自定义创建后的成员编辑、模板草稿编辑共用。选择设备子页共享同一个 `SceneDraftSelection`，关闭子页只返回父页并保留草稿。
2. `SceneDevicesSelectionView.updateEditorHeader()` 仅依据是否处于选择页、成员是否为空及 Preview 是否成功隐藏卡片，没有检查配置内容是否改变。`SceneDevicePreviewState` 默认是 recommended，因此未编辑也会提示。
3. `closeAction()` 除选择子页、未取得草稿、已经提交外，总是显示 Discard；不存在内容比较。
4. `doneAction()` 已通过 `SceneConfigurationStore.sceneIfUnchanged()` 判断内容相同。无同步任务则退出，有 needSync/pending 则进入 Sync；该方法同时验证权限、来源版本、投影状态并解析当前目标，不宜直接放进频繁 UI 刷新和关闭判定。
5. `SceneDraft` 每次实际变更会更新 revision，但恢复原值不会恢复原 revision。直接比较完整 draft 或 revision 会误判“改后还原”。设备成员已在模型中规范化并排序，可比较身份及完整保存参数。
6. 选择、移除、参数 Apply、类型切换会通过现有 reload 链刷新。搜索、折叠、Identify、Preview 和仅实时控制不修改已保存配置；Preview 的状态与设备 ACK 不应改变草稿是否需要保存。
7. 自定义创建先持久化空 Scene，再进入 Settings；模板入口可以传入尚未保存且没有场景号的草稿。后者不能因“刚进入、与初始值相同”而误判无需保存。

## 行为边界与验收

| 情况 | Preview 卡片 | 关闭 Settings |
| --- | --- | --- |
| 已有 Devices，进入后未修改 | 隐藏 | 直接退出 |
| 只有历史 pending，未编辑 | 隐藏 | 直接退出，pending 保留 |
| 修改成员、开关、亮度或色温 | 有成员时显示，遵循 Preview 状态 | 确认 Discard |
| 增删/参数修改后完整恢复原内容 | 隐藏 | 直接退出 |
| 删除最后一台设备 | 保持空页，不提示预览 | 确认 Discard |
| Preview 成功，修改尚未保存 | 沿用成功后隐藏 | 确认 Discard |
| 仅搜索、折叠、Identify、实时试灯或手动 Preview | 不因此出现草稿提醒 | 没有配置修改则直接退出 |
| 空 Scene 切换类型，未保存 | 无设备时不显示 | 类型不同仍确认；切回原类型且内容相同则直接退出 |
| 已持久化的新建空 Scene，进入后无修改 | 隐藏 | 正常结束创建导航，不删除已建 Scene |
| 尚未落盘的模板草稿 | Devices 且非空时遵循 Preview 状态 | 保留放弃确认，不能当作已保存 |
| Groups 未改/改后恢复 | 不增加 Devices 提示 | 直接退出；有修改仍确认 |

补充边界：

- Select devices 子页的关闭与 DONE 保持返回父页语义；返回时不能重建基线或吞掉之前修改。
- 同一份草稿被父子页共享时，基线只建立一次。搜索、设备上下线、移组、ACK 进度和页面重现不能重置基线。
- 无改动时仍允许手动 Preview；卡片继续受“有未保存修改”约束，保留现有忙碌禁用、结果 Toast 及取消机制，不新增提示形式。
- 关闭仍调用既有 leave/suspend，取消 Preview、实时控制、地址/拓扑回调和编辑器任务；有修改时保留现有取消/Keep editing 路径。预览或实时试灯引起的灯态变化不由 Discard 回滚。
- 外部来源版本/权限变化不应制造本次编辑。保存时继续由现有校验拦截；关闭无修改页面无需依赖设备在线或权限校验成功。草稿读取失败沿用原有退出与错误处理。
- 已提交但投影待恢复时，继续使用 `committedNumber` 分支及既有持久化恢复，不把已落盘内容当成可丢弃草稿。

## 最小实施方案

1. 在 `SceneDraftSelection` 保存初始化时的 draft 基线，提供一个只读的 `hasUnsavedChanges` 判定。比较 kind、name、imageId、groupParameters、规范化 deviceMembers；不比较 revision、pending、在线状态和视图状态。无场景号的未持久化草稿保留需保存语义。基线不随 reload、Preview 或子页返回变化。
2. `SceneDevicesSelectionView.updateEditorHeader()` 在现有显示条件中加入同一个判定；通过现有 UIStackView 隐藏整张卡片，核对间距收起。只读 Scene 详情使用独立布局，不应用编辑提示。
3. `SceneSettingsViewController.closeAction()` 保留选择子页、读取失败、已经提交等优先分支；没有修改时走已有 leave，有修改时走既有 Discard。保持既有生命周期取消与迟到回调保护。
4. 保留 DONE 的 `sceneIfUnchanged` 校验与同步交接，不改变 Store、正式任务生成或 pending；新判定服务于编辑提示，不能替代保存安全校验。

复用取舍：直接调用 `sceneIfUnchanged` 会把权限、拓扑解析及持久状态错误混入 UI 提示；在控制器和视图分别比较会产生两套标准。由已有共享草稿所有者保存内容基线，既覆盖父子页，也无需新增通用框架或改变持久化模型。

本次只涉及 App 共享逻辑，预期不新增文案、资源、依赖或 SDK API，不需要固件、网关或服务端配套。五个品牌共享相关代码，按实际差异确定编译范围。

## 验证安排

- 扩展既有 `SceneDraftSelectionTests.swift` / selection suite：未编辑、修改/还原、移除再加入、删空、类型切换恢复、Groups、模板草稿、共享父子页、历史 pending 不影响结果。
- 使用现有 Swift 行为夹具方式验证生产的卡片显示与关闭入口：有/无修改、Preview 成功/失败/运行中、隐藏后无占位约束、子页返回、已提交及无草稿分支。布局占位最终仍需真实 UI 核对，不以属性替身证明视觉效果。
- 运行相关 `SceneDoneSyncFlowTests.py`、save suite，确认 DONE 未变、pending 不被重建、Preview 不落盘、无修改重试与取消/迟到回调仍成立；共享详情展示测试作为复用回归。
- Swift 修改完成后核对实际 workspace、scheme、SDK realpath，执行一次 SunSmart Debug generic iOS 构建，关闭签名、使用本工作树稳定 DerivedData。无品牌差异、无资源/依赖变更时不机械重复五品牌构建。
- 人工最短验收：进入已有 Devices Settings 不编辑直接关闭 → 修改参数检查提示并关闭确认 → 改回原值检查隐藏且直接关闭 → 删除全部仍需确认 → Preview 成功后未保存仍需确认。补测历史 pending、Groups、选择子页返回和新建入口。
- 不自动安装或运行真机。自动验证执行结果见下方实施记录，UI 验收仍待用户完成。

## 当前工作区保护

分支 `feat/device-scene-261028`，HEAD `d2b5a4b5`。开始分析时已有暂存改动：SceneViewController、SceneDeviceSettingsCell、SceneDevicesSelectionView、两种语言 Localizable.strings、SceneDetailsPresentationTests.py 及详情 UI 方案文档。

本方案预计与已有 `SceneDevicesSelectionView` 修改共存，实施时在当前内容上最小增量修改，保留详情 UI 成果及其他任务差异。本轮仅新增本方案文档。

分析结束时检测到上述已有改动已由外部提交为 `b94a233b`（`feat: improve device scene devices list`）；本代理未执行提交。已核对该提交未修改 Settings 控制器、草稿模型/所有者或 Store；共享视图变化对应本轮读取的详情 UI 实现，不改变本方案结论。当前仅本方案文档未跟踪。

## 实施与验证记录（2026-10-31 12:53）

基于 `b94a233b` 实施，未提交 Git。修改 3 个生产 Swift 文件：

- `SceneDraftSelection` 捕获不可变初始基线并提供 `hasUnsavedChanges`；无场景号的草稿保留需保存语义。
- `SceneDevicesSelectionView` 依据该判定隐藏整个编辑提示卡片，复用现有纵向 UIStackView 收起隐藏项；Preview 按钮保留。
- `SceneSettingsViewController.closeAction` 无修改直接走原退出/清理逻辑，有修改保留确认；未改 DONE、Store、任务生成或协议。

扩展现有 selection 夹具及脚本，执行真实草稿逻辑、生产 header 更新方法和关闭方法，UI 接收对象使用替身。

| 验证 | 结果与边界 |
| --- | --- |
| `check_scene_configuration.py --suite selection` | 73 项通过，另含 DeviceNameFilterSession 测试；覆盖参数修改/还原、成员增删恢复、删空、历史 write/remove、Groups、未保存模板、子页共享、Preview 各状态与关闭分支 |
| `SceneDoneSyncFlowTests.py` | 通过；分别验证仅 needSync、仅 pending 均进入同步页且不调用保存，无待同步任务则直接退出；含 Preview/取消/迟到回调与提交恢复 |
| `check_scene_configuration.py --suite save` | 通过；含原内容不变/恢复原值、已有 pending 幂等、权限、投影恢复及保存协调器回归 |
| `SceneDetailsPresentationTests.py` | 22 项通过，保护共享视图的已有详情行为 |
| SunSmart Debug generic iOS | 12:53 构建成功，`SunSmartLocal.xcworkspace` / `SunSmart`，`CODE_SIGNING_ALLOWED=NO`，固定 DerivedData `SunSmart-feat-device-scene-261028-cli` |
| 差异检查 | `git diff --check` 通过 |

新夹具首次运行时，历史 pending 测试直接比较了原数组与模型规范化排序后的数组而失败；已把期望配置按生产规则规范化，重跑 selection 全部通过。未因此放宽生产逻辑。

本地 SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `ccdf101`；沿用已有 `MeshMessageManager.swift` 修改及未跟踪的 `MeshGroupControlSession.swift`、`check_group_control_session.py`。本次未修改 SDK、资源、国际化或工程依赖。共享代码无新增品牌条件路径，本轮只运行代表品牌 SunSmart 编译。

未运行真机、Simulator 或其他品牌完整构建。待用户按上方最短步骤验收卡片收起后的实际布局、关闭确认及历史任务 DONE 跳转；自动化与编译不能替代这些真实 UI/设备验收。
