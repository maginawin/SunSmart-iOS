# 创建或编辑 Scene 后，首次返回列表仍显示待同步

**实施结果**　创建和编辑 Scene 共用的 Settings 流程已在同步退出时发布单个 Scene 的更新通知。列表按当前快照刷新，全部完成后恢复 Scene 图标，仍有待办时保留提示。三组离线回归及 SunSmart Debug 构建通过，实际弹层返回和 BLE 设备行为待真机验收。

分支为 `feat/timed-simple-261106`，修复基于 `d8c45b40`。现场日志记录的是已有 Scene 的 Group 编辑路径，创建和直接选择 Devices 也使用本次修改的退出回调。

## 日志能确认什么

| 日志行 | 观察结果 | 含义 |
| --- | --- | --- |
| 28、65–74 | 进入 Settings，Scene 1 的 `pending=2`，同步目标为 `0x0004`、`0x0007` | 刚保存时存在两项待执行操作。安装计划时的 `taskRows=0` 统计的是步骤子行，随后确实选择并执行了两个设备任务。 |
| 90、106–108、128、143–147 | 两台设备各有一次成功的参数设置，各自返回 `SceneRegisterStatus(Success, currentScene: 1, scenes: [1])`，两次结果均为 `applied=true`。最终为 `syncSuccess`，失败模型为 0 | 本轮设备已确认 Scene Store，App 也接受了两台设备的结果。中途的 CTL Client 绑定提示未阻断这轮回执。 |
| 162–193 | Space 上传 `/sitespace/sync/spaceprops` 返回 HTTP 500，业务码 9999 | 本次云端上传确实失败。Space 导航栏有独立的云状态，Scene 卡片读取本地设备同步快照。响应只给出 `unknown error`，云端原因待对应服务日志确认。 |
| 194、217–225 | 同步后先进入单数的 `SceneViewController`（详情）。关闭详情、切到 Group 再切回后，才记录复数的 `ScenesViewController`（列表）进入 | 这与用户看到的图标恢复时机吻合。日志未记录卡片每次读取的快照，也未记录关闭弹层时全部 UIKit 生命周期，无法据此判定具体是哪一次布局或回调重绑了卡片。 |

## 修复前从回执到图标的断点

1. **保存。** `SceneSettingsViewController.commit` 调用 `saveForSync`。取得保存后的 Scene 后，`openSyncPage` 在推入 Sync 页**之前**发布 `sceneDataUpdateNotificationName` 和 `scenesRefreshNotificationName`。新建后进入成员设置、从详情编辑以及已有待办时再次点 Done 都能走到这里。
2. **写回。** `SyncExecutionSession.applyResult` 按设备身份交给 Scene 回执处理。`SceneMessageContext.apply` 更新设备的 Scene 参数记录、移除匹配的待办并保存，清理节点同步缓存。保存失败会返回失败。`finishRun` 在拟报告 Scene 成功时还会检查 `scene.needSync`。本轮日志通过了这些检查。缓存版本失效会让下一次查询重算，已经显示的卡片仍需要一个发起查询的入口。
3. **返回。** Sync 成功后，`SyncDevicesViewController` 调用 `syncSuccessCallback`；手动返回走 `backActionCallback`。两者进入 Settings 的同一个 `finish` 闭包，修复前只处理一次性导航。执行器另发的 `spaceDataChangedNotificaitonName(.syncResult)` 由 Space 页面用于安排云上传。Scene 列表并未订阅这个云上传入口。
4. **列表显示。** `ScenesViewController` 收到单个 Scene 的变更时调用 `reloadCollectionItem(scene:)`。列表可见时会重绑对应卡片，当前不可见则置 `refreshData`，下次出现再读。`ScenesViewCell` 绑定时才向 `requestSceneGroups` 申请快照，按 `needsAnySync` 绘制图标。同一 Scene 等待新结果或收到空快照时，会保留已确认的图标。若弹层消失时底层列表未重新进入，先前那个正确的待同步图标就会留在屏幕上；切页提供了下一次刷新机会。

## 实际改动

- **改动位置。** 在 `SceneSettingsViewController.openSyncPage` 的共用 `finish` 闭包中，通过现有 `didFinish` 防重后、执行 pop 或 dismiss 前，主线程向 `sceneDataUpdateNotificationName` 发布本次保存的 Scene 一次。发送端核对当前 Mesh 中的 Scene 对象及子网，列表端核对本页 Space 的 Mesh UUID 和子网。成功、失败后返回、部分完成后返回均沿用同一入口。创建继续原来的向导或关闭路径，编辑返回原详情。
- **图标判定。** 复用列表的单项刷新和卡片的请求编号校验。最新有效快照显示有剩余写入、删除或配置异常时保留提示；确认全部完成时恢复 Scene 图标。耗时读取或暂时拿不到快照时，沿用已有的显示策略。回调只触发读取，无需为 UI 重发 Mesh 命令、写数据库或额外排入云上传。
- **影响范围。** 修改位于各品牌共用的 App Settings 流程。已有的详情、Timed 和开关 Scene 选择器也监听单项通知。Scene 删除入口有自己的完成回调，保留各自的收尾逻辑。数据库和 export JSON 均无结构变更，无需 SDK、固件或服务端配套。HTTP 500 可以独立跟进。

## 验证与验收

**已做的离线复现。** 在临时 Swift 夹具中提取当前 `openSyncPage` 和 `ScenesViewCell` 的实际绑定代码，使用 Foundation 通知，固定初始快照为待同步。模拟底层卡片持续存在，手动交付后续快照。

| 条件 | 修复前 | 在临时夹具中加入单项通知 |
| --- | --- | --- |
| 创建或编辑后，全部设备成功 | 退出回调触发 0 次新读取，保留待同步图标。模拟重新绑定后恢复正常图标 | 退出回调触发 1 次新读取，交付完成快照后恢复正常图标 |
| 创建或编辑后，部分完成并手动返回 | 退出回调触发 0 次新读取 | 退出回调触发 1 次新读取，仍有待办时继续显示提示 |

模拟成功与返回回调重复到达时，导航只执行一次；在候选实现中，旧读取的迟到结果也未覆盖新图标。夹具以替身提供导航、列表观察者和快照，未运行 UIKit、真实异步快照获取、SQLite 或 BLE。

**实施后的离线回归。** 已补齐原先阻塞三个脚本的测试替身，实际运行结果如下。

| 检查 | 结果 |
| --- | --- |
| `SceneDoneSyncFlowTests.py` | 通过。真实退出闭包在成功和手动返回时只通知目标 Scene 一次，失败停留在 Sync 页，已换子网或 Scene 对象被替换时丢弃旧通知。原有创建、编辑、空 Scene 和重试导航用例通过。 |
| `SceneListSyncDisplayTests.py` | 通过。实际列表通知接收、单项刷新及卡片绑定代码在受控快照下只更新目标卡片。其他卡片的待办、换 Space 后的同号 Scene、迟到的旧读取和离屏重进均已覆盖。 |
| `check_node_sync_status_refresh.py` | 通过。共享读取器覆盖 Group 与 Devices 两种 Scene 的待办、清除、空配置、缓存失效及取消。拓扑与存储输入由夹具提供。 |

**构建。** `SunSmartLocal.xcworkspace` 的 SunSmart scheme 已通过 Debug、generic iOS、关闭签名的构建，编译器有既有警告。SDK 映射到本机 `one-dev`，revision 为 `2809c54`。生产修改为共享 Swift 逻辑，采用 SunSmart 作为代表 target。

**待真机验收**

1. 按“创建 / 编辑 × Group / Devices”走完成功路径。编辑从同步页自动返回详情后关闭，创建按原流程退出。首次看到列表时，当前 Scene 应自行恢复正常，无需切页或再次同步。
2. 两台灯中让一台离线或在第一台完成后 STOP，再手动返回。目标 Scene 应继续提示，退出重进后仍可重试。重试仅下发尚有待办的设备，成功后卡片自行恢复。若同时复现 HTTP 500，核对 Scene 卡片与 Space 云上传失败提示可各自正确显示。
3. 若真机仍残留图标，最小诊断是在 DEBUG 下关联记录退出原因、Scene 编号、列表是否可见、单项是否重绑，以及读取结果（空快照 / 待同步 / 已同步），区分未收到通知、读取暂不可用和本地确有待办。
