# 空间 2 进入时提示“尚未完成恢复”的原因分析

分析与实施日期：2026-10-16（UTC+08:00）。首次分析仅做只读核对；用户随后要求保留定时、自动移除旧入网实例引用，本工作树已实施 App 修复。SDK、输入 JSON、手机数据库和服务器数据均未修改。

当前交付：共享导入、导出、备份和回读比较会移除失效的旧实例绑定；本地同步清理通过既有事务、恢复记录和持久化回读保存修复。相关回归与 SunSmart Debug generic iOS 编译通过，真实手机进入空间及云端同步待人工验收。具体实施与验证见文末。

## 结论

修改前的直接原因已确认：空间 2 的全部 16 条定时任务仍保存 L14 的旧入网实例绑定，而该实例已不在当前节点集合中。服务器返回的数据因此被原 `TimedSchedulerPayloadPolicy.canonical` 拒绝，空间导入返回 `invalidTimedPayload`；进入空间的 UI 将这个原因映射为“此空间尚未完成恢复”的通用提示。下文根因与旧行为描述以分析基线 HEAD 为准。

本地也存在同一组失效绑定：L14 的 UUID 未变，但地址已经从 `0FE0` 变成 `0FE4`，Device Key 指纹也不再匹配。因而本地完整导出同样失败，不能靠普通上传覆盖云端解除问题。重复拉取当前这份云端数据也会再次失败。

这不是由快照中的“导入仍在进行”状态触发。旧绑定具体在哪一次删除、重新入网或恢复操作中未完成清理，现有两份快照不足以还原。

## 分析基线与输入

- App 工作树：`feat-SR-BL2421-Mini-261016`，分支 `feat/SR-BL2421-Mini-261016`，HEAD `387069a4a5224a748cbd0e130dc203f5c954c8bf`；开始分析时工作树干净。
- 本地 SDK 映射：`.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `8c5af55f5887e588e71f053ab44e2f6aa53a86a0`，只读核对，无未提交差异。
- [服务器 GET 快照](</Users/maginawin/Desktop/doing/xyy/server data.json>)，SHA256：`339dd2d4bd5553685467571d3bdc2d71aadbdd43fb487fe29869583bbcbfcc3b`。
- [App 导出快照](</Users/maginawin/Desktop/doing/xyy/Site_项目 22_20261016_152558_331+0800.json>)，SHA256：`8936d08d9d9371659f83848d1968b61dbabd141dfce240187377fb739af5be88`。
- 目标空间：空间 2，UUID `7D037B3C-8714-4534-93E2-6BD86E698F62`。
- App 快照采集时间：2026-10-16 15:25:58。服务器文件未提供请求采集时间字段，不把文件修改时间当成接口请求时间。

未记录 NetKey、AppKey、Device Key、密码或完整密钥指纹。

## 两份数据的关键差异

| 项目 | App 本地 | server GET |
| --- | --- | --- |
| 定时 schema | 2 | 2 |
| 定时任务数 | 16，业务 ID 为 0–15 | 16，业务 ID 为 0–15 |
| 定时内容 | 从 SQLite 记录还原后，与服务器全部相等 | 每条任务有 9 个 `nodeSlots` |
| L14 节点 | 存在，地址 `0FE4`，新 Device Key | `nodes` 中缺失 |
| L14 的定时绑定 | 仍指向旧地址 `0FE0` 和旧 Device Key 指纹 | 同样保留旧绑定 |
| 节点数组实际数量 | 15 | 13 |
| L15 | 本地存在，地址 `0FE3` | `nodes` 中缺失 |
| 空间更新时间 | 2026-10-16 11:19:46 | 2026-10-16 09:51:03 |
| 本地最后确认云端时间 | 2026-10-16 09:51:03 | 与本次 GET 的 `updateTimestamp` 相同 |
| NetKey / AppKey 对象 | 与服务器完全相同 | 无此处网络密钥差异 |

L14 UUID 为 `082A0CCE-FAF2-4C67-B7D5-F331050DA398`。其当前本地 `createdTimestamp` 为 2026-10-16 11:19:19；Site exclusions 中包含旧地址 `0FE0`、`0FE1`、`0FE2`。这些证据与同一设备重新入网后产生新实例一致，但不能仅据此确定操作入口或执行客户端版本。

16 条任务一共有 144 条绑定，其中 16 条为 L14 的旧绑定，全部仍为 `assigned`。其余 128 条绑定可对应现存节点；本次探针仅去掉这 16 条失效绑定，就能通过定时校验。不是定时任务总数超过 16，也不是物理槽位重复导致本例失败。

服务器 `deviceCount=15`，实际 `nodes.count=13`，两者不一致。L15 没有被这些定时绑定引用，因此它的缺失不是本次 `invalidTimedPayload` 的直接原因；其缺失来源尚未确认，不据此推断服务器删除过程。

### App 调试导出的含义

目标数据位于 `_debugInspection.spaces` 中空间 2 的记录：

- `issues=["invalidTimedPayload"]`。
- `comparisonPayloadAvailable=false`。
- `recoveryPhase=active`、`recoveryAuthority=writable`。
- `membershipPhase=joined`、`configurationInitialized=true`、`membershipNetworkMatches=true`。
- `pendingImport=false`、`pendingUpload=false`、`pendingDeletionCleanup=false`。
- `requiresRemoteImport=false`、`unbindRequested=false`。
- 没有 `blockedReason` 字段。

所以不能把这次提示解释为仍有一个未完成导入任务。`hasCompleteExportSnapshot=true` 只说明已有保存快照的状态，不代表本次当前数据可通过完整导出校验。

顶层 `site.spaces` 中空间 2 只有名称与 UUID，是 [DebugCloudJSONExporter.swift](../SunSmart/Common/Cloud/DebugCloudJSONExporter.swift) 在完整导出返回 nil 时生成的占位信息；真实本地记录仍在 `_debugInspection.spaces[].rawLocal`，并非本地空间已经被清空。空间 33 和空间 1 的调试导出均无 issues，比较数据可用。

## App 的触发链路

1. [SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift) 的 `selectSpaceAction` 在联网进入已上传空间时调用 `loadSpaceReqeust`，请求 `/sitespace/get/spaceprops`。
2. GET 返回 `code=200` 后，`loadSpaceReqeust` 调用 `restoreConfiguration`。HTTP/API 成功不代表配置内容已通过校验。
3. [SpaceMembershipCoordinator.swift](../SunSmart/Common/Data/SpaceMembershipCoordinator.swift) 处理空间和网络身份，然后进入 `SpaceData.update`。
4. [ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 在替换业务配置前调用 `TimedSchedulerPayloadPolicy.canonical(incomingTimedPayload)`。本样本返回 nil，于是直接返回 `.rejected("invalidTimedPayload")`。
5. [TimedSchedulerSlotPolicy.swift](../SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift) 要求每条绑定的完整身份都存在于本次 payload 的 `nodes`：UUID、主地址和 Device Key 指纹共同匹配。服务器缺少 L14，故旧绑定不可能满足 `identities.contains(binding.identity)`。本地虽有相同 UUID，但地址、Device Key 已变，也不能满足该条件。
6. `loadSpaceReqeust` 收到 rejected 后调用 `showSpaceRecovery`，不进入正常空间页面。
7. [SpaceRecoveryViewController.swift](../SunSmart/Main/Space/Controller/SpaceRecoveryViewController.swift) 的 `message` 未单独处理 `invalidTimedPayload`，落到 default → `space_recovery_unavailable`，中文就是“此空间尚未完成恢复，请重试恢复。在完整配置就绪前，暂时无法修改配置。”

“重试恢复”按钮仍调用同一 GET 和导入链路；只要返回数据不变，就会再次被同一校验拒绝。

## 为什么本地上传和自动清理也未解除问题

[ExportData.swift](../SunSmart/Common/Data/ExportData.swift) 在组装完节点和定时任务后，同样执行 `TimedSchedulerPayloadPolicy.canonical`。本地 L14 的旧绑定与新节点身份不符，因此返回 nil，并在调试导出中记录 `invalidTimedPayload`。

[SpaceSyncCleanupCoordinator.swift](../SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift) 的 `perform` 在清理前要求 `space.export(purpose: .cleanupInspection)` 成功。该出口仍经过上述 Timed 校验，因此这批失效绑定会让清理在准备阶段停止。

快照中相关诊断：

- 15:25:32：`lastSyncDiagnostic.stage=cleanupPreparation`，`error=-2004`（`configurationUnavailable`）。与清理准备无法取得完整导出的路径相符。
- 15:25:53：`lastReadbackDiagnostic.stage=baselineReconciliation`，`reason=membership`，`error=-2002`（`configurationUploadUnconfirmed`）。这里的 membership 是云端节点成员基线对账，不等于当前用户没有空间权限。[SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift) 的 `reconcileCloudMembership` 还要求定时基线投影与远端 canonical 数据一致；当前远端 canonical 为 nil，不能作为有效对账结果。快照没有保存完整基线内容，不能精确断言当次对账最先失败于哪个 guard。

由此形成两端都无法完成的状态：云端不能导入，本地不能完整导出，普通重试无法消除失效绑定。单独清除恢复标记或放开进入页面，都不会修复数据关系。

## 失效绑定的产生边界

当前代码并非完全没有处理旧实例：

- [MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift) 的 `updateResoreData(oldNode:)` 会删除与旧完整身份匹配的 `nodeSlots`。但它依赖当前内存中的 schedules 和旧 Node 身份；保存失败时回滚该 schedule，函数没有把整体清理失败返回给恢复流程。
- [DevicePermanentDeletionCleanup.swift](../SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift) 的 `cleanExtensions` 会按旧 UUID 与主地址删除对应绑定，持久化失败会抛错。
- [TimedSchedulerBindings.swift](../SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift) 的普通分配过程按当前节点身份更新绑定，不能自动替失踪的旧身份完成清理。
- 同 Site 的跨空间实例清理由 `SiteDeviceOwnershipReconciler` 处理，不能据此推定已经覆盖同一空间重新入网后的所有残留。

已证实的是“旧绑定残留，新本地实例与云端节点集合均无法匹配”；未证实的是由恢复、普通重新添加、其他客户端写入、删除与空间上传不同步，还是持久化失败造成。两份 JSON 不含当时操作日志和 App 构建版本，不能把其中任一路径写成已确认历史根因。

## 离线验证与后续建议

使用当前工作树未经修改的 `TimedSchedulerSlotPolicy.swift`，通过临时 Swift 命令行探针执行生产 `canonical`：

| 验证输入 | 结果 |
| --- | --- |
| 原始 server `data` | nil，复现校验拒绝 |
| 从 rawLocal 还原的本地 Timed 数据 | nil，复现身份冲突 |
| server 数据仅在内存中去掉 16 条失效绑定 | 定时校验通过 |
| 本地 Timed 数据仅在内存中去掉 16 条失效绑定 | 定时校验通过 |
| 本地 16 条业务日程与 server 日程逐字段比较 | 全部相同，包括所有 nodeSlots |
| 对原始 server 数据应用旧客户端缺字段默认填充 | 仍失败；显式存在的旧 v2 身份不会被该兼容逻辑修复 |

本地探针依据数据库字段映射还原 schedule 和 Node 身份，是 Timed 校验专项验证，未运行完整 SDK/数据库导出。其容量判断最多只有 16 个不同业务 ID，不依赖组成员推导来解释本例的身份失败。探针临时文件已自动删除，未把原始私有 JSON 复制进仓库。

首次分析提出以下后续方向。第二阶段已实施第 2、3 项所需的旧绑定自动修复及回归；具体历史操作入口仍未确认，未改动恢复页面文案：

1. 用“L14 同 UUID、地址及 Device Key 改变、16 条旧绑定”的夹具覆盖删除、恢复和同空间重新入网，确认旧绑定清理失败的实际入口；清理持久化失败应保留可重试状态。
2. 增加基于旧实例证据的存量恢复路径，使无效 Timed 数据可以被检查和定向修复，不先依赖一次完整导出成功。保留 16 条业务日程和其他节点绑定；新节点的槽位由正常规划流程重新建立，不能仅改地址而继承旧实例的确认状态。
3. 同时覆盖本地较新、云端仍旧且节点缺失时的对账及上传回读，不把远端“缺节点”直接用于删除本地新实例，也不绕过身份、权限或完整性检查。
4. 恢复页面区分 `invalidTimedPayload`，说明定时绑定与节点身份不一致；避免让用户误以为只需继续等待。仅改文案不能解决阻塞。

若后续需要服务器团队核对，仅提供契约：节点集合变更后，`schedules.nodeSlots` 不能继续引用已移除的旧实例，GET 应提供可一致解释的节点与定时版本。现有快照无法判定是谁写出了不一致数据，本次未读取或修改后端代码，也未实施服务器修复。

首次分析未构建 App、未连接或运行真机、未调用线上接口。上述首次分析的“通过”仅针对定时校验探针，不代表已完成空间恢复、云端同步或真实设备验收。

## 第二阶段：自动修复实施

### 行为与范围

- 保留全部业务定时，包括 ID、名称、启用状态、动作、时间、组、场景、Profile 等内容；只移除不再对应当前完整节点集合的 `nodeSlots` 以及属于该旧实例的直接设备目标、待删除设备地址。
- 当前实例的有效绑定保持不变；地址被复用且该任务显式绑定了当前实例时，保留当前实例的目标。仅凭旧地址不能把旧目标或物理槽位转交给新实例。
- 继续拒绝无效节点身份、重复节点 UUID/主地址、损坏的绑定结构、无效槽位或 generation、重复槽位等数据。导出节点编码不完整时直接失败，不能把编码遗漏当成设备已删除。
- 复用 `TimedSchedulerPayloadPolicy.repairingStaleBindings`，统一处理导入预检、实际导入、导出、文件备份、备份读取与 canonical 回读比较。
- 云端导入发生修复时，复用 `preserveRemoteReferenceCleanup` 保存原始与修复候选数据；既有导入事务及 `finishImport` 负责失败重试和后续上传意图。visitor 可以读取修复后的配置，但不生成修复上传。
- 本地 `SpaceSyncCleanupCoordinator.extensionChanges` 比较持久化 Schedule 与修复后的字段，并在既有清理事务中写入，随后重新加载验证；当前 Space 的内存 schedules 沿原有刷新流程更新。待确认上传先完成回读，再执行清理，不改写在途回执。
- 所有修改位于 App 共享代码，五个品牌使用相同路径，无 target、依赖、SDK API 或资源改动；使用 SunSmart 作为代表 scheme 编译。

生产改动集中于 [TimedSchedulerSlotPolicy.swift](../SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift)、[ImportData.swift](../SunSmart/Common/Data/ImportData.swift)、[ExportData.swift](../SunSmart/Common/Data/ExportData.swift)、[SpaceSyncCleanupCoordinator.swift](../SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift)。未提交 Git commit。

### “空间保留副本”入口

恢复页面按钮 `space_saved_copies`（中文“空间保留副本”）调用 `copiesAction`，打开 `SpaceSavedCopiesViewController`，列出本机此前已保存的副本。它本身既不创建当前空间副本，也不执行恢复，因此空列表或查看副本不会解除本次阻塞。

本次保持该按钮的既有职责。实际生成副本的 `preserveCopy` 与正常导出已使用修复后的导出路径；rawLocal 原始诊断记录仍会保留。此类空间应通过正常进入或“重试恢复”完成自动修复，无需依赖副本列表。

### 验证结果

- `scripts/check_timed_device_slots.py --stale-snapshot <server data.json>`：通过。现场服务器数据保留 16 条日程，移除 16 条旧绑定，其余非定时字段保持一致。覆盖节点缺失、同 UUID 换地址/Key、地址复用、pendingRemoval、空目标、备份往返、幂等和损坏数据拒绝。
- 原始 App 导出专项探针：空间 2 保留 16 条任务、移除 16 条旧绑定；空间 33 保留 1 条任务且无绑定删除；空间 1 保持 0 条任务。三个空间的 Timed 校验与备份往返均通过。探针按原有数据库映射还原 Timed 数据，未执行完整 SDK 导出。
- `scripts/check_timed_slot_persistence.py`：通过。真实 SQLite 与生产 Schedule 编解码、存取逻辑验证 16 条任务保留、有效节点绑定不变、事务中途写入失败全部回滚、重试成功及重新打开数据库后修复仍在。
- `scripts/check_space_recovery_receipts.py`：通过。新增 owner/editor/visitor 入口、历史 pending-import 重放、修复上传意图及回读比较；覆盖已接受上传和仅有基线两种情况下，云端删除旧实例并保留旧绑定时，本地同 UUID 新地址/新 Key 的实例不会被删除。权限、网络身份、未知回执及冲突等既有回归也通过。Mesh 实际删除与完整导入仍为该套件的隔离边界。
- `scripts/check_space_sync_readback_reuse.py`：通过。清理写入失败、回读失败、未收敛、取消/上下文变化及 pending upload 保护。原测试替身缺少当前生产代码已有的 `hasPendingUpload`，导致基线编译失败；确认被测 `perform` 与 HEAD 完全相同后补齐替身，并增加在途上传不允许清理的行为验证。
- `scripts/check_timed_empty_target_cloud_sync.py`：通过，空组/空场景定时及旧确认与新编辑的关系保持原有行为。
- SunSmartLocal workspace / SunSmart scheme / Debug / `iphoneos` / `generic/platform=iOS` / `CODE_SIGNING_ALLOWED=NO`：编译通过。使用稳定 DerivedData `SunSmart-feat-SR-BL2421-Mini-261016`；补充节点编码完整性保护后增量编译再次通过。未使用 Simulator，未安装或运行真机。
- `git diff --check`：通过。原始 JSON 内容未修改，私有数据未复制进测试夹具或仓库。

### 最短人工验收

1. 使用本分支新构建，联网进入项目 22 → 空间 2；若仍停在旧恢复页，点击“重试恢复”。此类旧绑定不应再触发“尚未完成恢复”。
2. 检查 16 条定时全部保留，L14 的旧 `0FE0` 实例不再占用这些任务的绑定；现有其他设备目标保持不变，新 L14 `0FE4` 和 L15 `0FE3` 不应被误删。
3. 完成同步后退出并重新进入，确认修复保持；再导出 JSON，空间 2 应能提供完整比较数据，不再出现本次 `invalidTimedPayload`。

真实设备的定时执行、完整 UI 恢复、服务器接受新版本及回读后的最终收敛仍待人工/联调验收。自动化、SQLite 与 generic iOS 编译结果不能替代这些验收。
