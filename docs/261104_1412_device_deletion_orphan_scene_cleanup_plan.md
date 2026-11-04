# 设备永久删除后残留 Scene 任务：根因与修复方案

> 状态：2026-11-04 用户确认后已实施；离线回归与 SunSmart Debug / generic iOS 构建通过。真实 App 页面、设备和服务器往返验收待用户完成。历史扫描仅在实际进入 Scene 页面时触发；正常/强制删除继续使用原删除事务。未提交、未操作真机或服务器、未修改 SDK。

**Goal:** 设备永久退出 Space 后，清除属于该设备实例的持久化任务和成员引用；修复历史孤立引用，使没有有效清理目标的待删除 Scene 可以完成删除。

**Architecture:** 两类触发共用 Scene 身份清理规则：实际进入 Scene 列表时修复历史孤立成员/任务；设备永久删除成功时，在现有删除事务内清除本次设备相关任务。复用现有身份保护、数据库事务、删除 journal 和云同步队列，不在普通 Space 进入、通用同步准备、导入、导出或上传前新增 Scene 全量清理；UI 状态读取函数保持只读。

**Tech Stack:** Swift、App SQLite、现有 Nordic Mesh SDK、Space 云同步与恢复机制。

**Spec:** 本文第 1～5 节。第 5～7 节为已确认范围；第 10 节记录最终实现与验证边界。

## 1. 结论与证据边界

**本次数据的主要问题是历史设备引用没有被清理，而不是本次删除的两台设备仍留在节点表。** 删除前 App 和服务器已经保存了 6 个设备型 Scene、共 9 条指向旧设备的成员引用。删除当前两台设备后，这些旧身份既不属于本次删除 journal，也不会被现有 Space 自动清理检查覆盖，继续触发待同步状态。点击删除 Scene 又将旧身份写成待删除任务，形成无法完成的状态。

分析阶段只新增本文档，并以生产 codec/resolver 复现。随后按用户授权修改 App 代码和回归夹具；最终真实 SQLite 离线回归及构建结果见第 10 节。未改动用户提供的文件、实际 App 数据库、SDK、服务器或真机。

不能从这三份快照确定旧设备最初在哪一版 App、哪一次删除/恢复/导入中遗留；也不能认定为服务器主动制造了这些引用。文件时间范围内的点击顺序、SDK Scene 行删除的具体时点没有操作日志。

## 2. 输入与工作树

- App：`feat/daylight-saving-261024`，HEAD `eb9caaf3b0059d1cadc4c7ee3bdcc9c25988acf0`。分析开始时工作树干净；相关 Scene 功能已合入当前分支。
- 删除前 App：`/Users/maginawin/Downloads/Space_Space 1_20261104_140142_850+0800.json`。
- 删除前服务器：`/Users/maginawin/Desktop/server data before force delete.txt`。
- 删除后 App：`/Users/maginawin/Downloads/Space_Space 1_20261104_140552_068+0800.json`。
- `SunSmartLocal.xcworkspace` 映射 `.local-sdk/nordic-sig-mesh-sdk` → `nordic-sig-mesh-sdk-worktrees/one-dev`，SDK HEAD `dbcf6f1`。SDK 已有 Scheduler 回包相关未提交改动和测试，非本任务产生，全部保留。本方案预计无需 SDK 修改或新 SDK API。
- 导出包含 `_debugInspection.rawLocal`，可交叉检查 App `sceneInfos` 与 SDK `scenes` 的原始数据库行；导出顶层 `spaces[].scenes` 是合并后的业务视图，不等于 SDK 原始表。

## 3. 数据对比

| 项目 | 删除前 App | 删除前服务器 | 删除后 App |
| --- | ---: | ---: | ---: |
| 节点数 / deviceCount | 2 / 2 | 2 / 2 | 0 / 0 |
| 当前节点 Primary 地址 | `0005`、`000E` | `0005`、`000E` | 无 |
| Group / 业务 Scene / Timed / Switch | 9 / 22 / 4 / 2 | 9 / 22 / 4 / 2 | 9 / 22 / 4 / 2 |
| 设备型 Scene | 6 | 6 | 6 |
| 指向历史身份的成员记录 | 9 | 9 | 9 |
| Scene pendingOperations | 0 | 0 | 1，Scene `0002` 的 remove |
| 原始 App SceneInfo 行 | 22 | 无原始表 | 22 |
| 原始 SDK Scene 行 | 22 | 无原始表 | 21，缺少 `0002` |
| 原始 Node / NodeProperty 行 | 2 / 2 | 无原始表 | 0 / 0 |

6 个设备型 Scene 的成员如下；表中编号是十六进制 Scene number，不等同于名称中的数字。

| Scene number | 名称 | 残留成员 Primary 地址 | 删除后状态 |
| --- | --- | --- | --- |
| `0002` | Scene 2 | `0008` | `isDeleting=true`，1 条 remove，schemaVersion=2 |
| `0003` | Scene 3 | `0008` | 未请求删除，pendingOperations 为空 |
| `0004` | Scene 4 | `0008`、`0011` | 同上 |
| `0006` | Scene 5 | `0008`、`0011` | 同上 |
| `0009` | Scene 8 | `0008`、`0011` | 同上 |
| `000E` | Scene 13 | `0011` | 同上 |

关键核对：

1. 删除前两台设备各有 3 个 Elements，地址范围为 `0005...0007`、`000E...0010`。旧引用 `0008 / 0011` 不在这些范围内，UUID 也不同，不是将 Secondary Element 误当成 Primary。
2. 删除前 App 与服务器的整个 `sceneConfigurations` 数组相同。它们都已包含这 9 条历史成员；不能只通过重新下载当前服务器配置修复。
3. 删除前 SDK Scene `0010 / 0012 / 0013` 各有一条 `0005` 地址缓存，删除后均清空，证明本次目标的这一类缓存确实被清理。
4. 删除后 Scene `0002` 的 `deletionReferences.pending` 与 `scheduleIDs` 均为空，当前阻塞来自旧身份 remove，不是有效的 Scheduler/开关依赖。
5. 4 个 Timed 的 deviceAddresses、needDeleteNodeAddresses、nodeSlots 等目标清理数组均为空；没有证据表明本例还残留 Timed 设备任务。2 个 Timed 保留 Scene 目标 `0001 / 000B`，属于用户配置。
6. 有一个虚拟 Switch 保留 `sceneA=0006`，但 bind/unbind Group 为空。这是业务关联，不能因灯清空就把 Switch 或 Scene 定义一并删除。
7. 删除后诊断为 `pendingDeletionCleanup=false`、`deletionSummary=[]`、`baselineNodeCount=0`、`pendingUpload=false`。这说明现有检查认为当前删除流程已完成，不能代表所有历史 Scene 引用也清理完毕。没有提供删除后的服务器响应，不能据此宣称云端已验收。

## 4. 当前代码如何产生并保留问题

### 4.1 设备永久删除只清理已确认的本次身份

[DevicePermanentDeletionCleanup.swift](../SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift) 的 `cleanExtensions` 已调用 `SceneConfigurationStore.removeConfirmedIdentities`，并处理 Scene 地址、Timed 目标与 slot、Proxy、HDB、传感器、网关关联和分发缓存。通用、单灯、多灯和 Dongle 路径已有共享删除 context。

[SceneConfiguration.swift](../SunSmart/Main/Scene/Model/SceneConfiguration.swift) 的 `removingConfirmedIdentities` 用 UUID + Primary 地址 + Device Key 指纹完整匹配，删除 `deviceMembers`、`pendingOperations`、有身份的 `deletionReferences.pending`。本次 journal 对应 `0005 / 000E`，自然匹配不到旧身份 `0008 / 0011`。应保留这种身份保护，不能改成按地址或 MAC 继承任务。

### 4.2 Space 历史清理漏掉 App Scene 配置

[SpaceSyncCleanupCoordinator.swift](../SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift) 的 `extensionChanges` 清理 SDK `scene.addresses`、Timed、Group、开关等引用，但没有遍历持久化 `SceneInfo.configuration` 清理孤立成员/任务。

现有 `prepareSpace` 已具备完整快照、基线回读、recovery generation、时间戳、事务及再次读取检查，可参考和复用其保护机制。按用户对性能和触发范围的要求，不向该通用入口加入新的 Scene 全量清理；历史残留由 Scene 页面进入时处理。只增强设备删除仍无法修复本例早已存在、且没有本次 journal 记录的旧身份。

可参考现有 [TimedSchedulerSlotPolicy.swift](../SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift) 的 `repairingStaleBindings`：在完整、合法的节点集合上识别旧实例，清理对应 slot/地址引用，保留新实例及其他目标。Scene 需有相同的数据收敛能力，但必须由外层提供可信快照前提。

### 4.3 Pending Sync 不要求 pendingOperations 非空

[SceneTargetResolver.swift](../SunSmart/Main/Scene/Model/SceneTargetResolver.swift) 将找不到完整身份的成员归入 `unresolved(.missingIdentity)`。[SpacePageSyncRead.swift](../SunSmart/Common/Data/SpacePageSyncRead.swift) 只要看到 unresolved，就设置 `configurationPending`，页面因此显示 Pending Sync。

所以本例 5 个 Scene 即使没有显式待办记录，也会显示待同步；根源是成员引用，而不是单独一个 pending 标志。只清空 pending 数组或隐藏提示都不能完成修复。

### 4.4 删除把旧成员转成永远无法执行的 remove

[SceneConfigurationStore.swift](../SunSmart/Main/Scene/Model/SceneConfigurationStore.swift) 的 `prepareDeletion` 将 resolved、unresolved、deviceMembers、既有 pending 的身份合并，保存为 remove。对于真正仍存在但暂时离线的设备，这是正确的保护；对于已退出 Space 的历史身份，如果没有先做可信清理，就会永久保留。

[SceneServer.swift](../SunSmart/Main/Scene/Model/SceneServer.swift) 的 `completePreparedDeletion` 必须等 pending 为空且级联引用完成才能调用 `finishDeletion`。本例旧身份无 Node，自然不能收到清理 ACK。列表长按删除和详情删除共享该入口，均可能提示 Deletion Pending。

Scene `0002` 还呈现“SDK 行已不存在、App 待删除行仍存在”的状态。现有恢复逻辑刻意保留带 pending 的 App tombstone，以防过早复用编号；修复必须覆盖这种记录，不能仅遍历 `manager.scenes`。具体造成 SDK 行先消失的操作顺序，本轮证据不足。

## 5. 收敛后的修复语义

### 5.1 方案取舍

| 方案 | 能解决的范围 | 取舍 |
| --- | --- | --- |
| 仅增强永久删除 journal 清理 | 新发生且有完整身份记录的删除 | 改动小，但本例的历史身份无法清掉，不足以完成需求 |
| **设备删除即时清理 + 进入 Scene 页修复历史残留及收尾** | 本次删除立即处理；历史数据首次进入 Scene 页时修复 | 按用户反馈采用；其他通用入口不新增全量扫描，仅保留既有失败恢复和云同步 |
| 额外建设永久设备删除墓碑库 | 可追踪更长历史 | 增加迁移、同步及生命周期成本；现有 journal/基线机制足够，本轮不采用 |

### 5.2 必须遵守的清理规则

- 正常删除成功或用户确认 Force Delete 后，删除该设备实例拥有的任务、成员引用和已无意义的本地缓存；取消删除不改配置。
- 历史清理使用当前账号/region/Site/Space 的完整持久化节点集合，并通过已有基线与恢复状态校验。扫描没发现、设备离线、加载中的空数组、SDK 内存暂缺、部分 API 响应均不算删除证明。
- UUID、Primary 地址、指纹继续规范化并完整比较。地址被新设备复用时，旧任务不移交给新设备；合法 Restore 先走已有 receipt，不能在恢复尚未完成时删除待迁移引用。
- 清除内容包括 Scene 成员、write/remove 操作、指向已删除实例的级联清理任务，以及相应 Timed slot/设备目标和既有设备扩展任务。其他仍存在设备上的必要同步、解绑或拓扑清理继续保留。
- 无身份的旧级联记录不能仅凭“解析失败”删除。必须有同作用域的已确认删除地址证据，或完整可信成员集合证明目标地址不存在且无 Restore/身份歧义；有其他设备占用该地址时保留并走现有恢复检查。
- 未请求删除的 Scene 清完成员后保留为空 Scene，允许继续编辑或直接删除。Group、Timed、Switch 定义及仍有效关联保留。这是对“清空设备相关任务”的建议边界，不自动扩大成删除所有业务对象。
- 已 `isDeleting=true` 的 Scene，在成员任务与有效级联依赖均清空后，通过既有 `finishDeletion` 删除 App/SDK 行、相关引用并释放编号；不需要联系已移除设备。仍有其他有效依赖则等待那些依赖。
- 清理变更真实落库，重载同步到 live Scene，失效相关读取缓存，再以新的本地版本排队上传。不得仅过滤导出、仅改内存，或把设备删除等同于物理 SceneDelete 已收到 ACK。

### 5.3 两类触发与性能约束

**入口 A：实际进入 Site → Space → Scene 列表。**

- `ScenesViewController` 是 `SpaceViewController` 的分页子控制器。优先由 `pageController(_:didEnter:withInfo:)` 的实际选中状态驱动页面准备方法；返回页面时也走同一个有幂等保护的准备方法，不在 `viewDidLoad` 或 `viewControllerAt` 中清理，避免分页预加载产生工作。
- 同一页面、同一有效数据版本仅成功检查一次；并发请求合并。复用现有 revision/作用域检查，不新增持久化“已清理”标志。暂因导入、提交、权限或恢复忙碌而跳过时不记为成功，页面仍可见且条件恢复后或下一次进入时再处理。
- 扫描当前 Space 全部持久化 SceneInfo 一次，包含 SDK 缺行的待删除记录；只查相关身份，不运行全 Site/全 App 清理。先发现候选，无候选不准备完整恢复快照、不发基线请求、不写库、不排上传。
- 有候选时才验证完整持久化成员、权限、revision 与恢复状态；可复用已确认基线，不因每次页面出现固定请求服务器。证据不足则等待原有恢复流程，不拿空的内存节点列表做删除依据。
- 页面单元格刷新、状态计算、滚动、Scene 详情页以及 Timed/Switch 的 Scene picker 均不重复触发清理。清理期间避免使用旧 Scene 数据编辑/删除；不要长期阻塞页面显示，完成后局部刷新。
- Scene 页保持可见时，如果已有云同步/恢复完成导致配置版本变化，只使该页面的检查失效并合并重新准备；不向导入器增加全局清理 hook，也不由每次设备状态变化循环扫描。

**入口 B：正常删除设备 / Force Delete 的原有永久删除事务。**

- 不依赖用户打开 Scene 页；确认设备永久退出后，同一删除流程完成所有属于本次设备的任务清理与落库回读。沿用通用、单灯、多灯、Dongle 的共享 `DevicePermanentDeletionContext`，批量删除合并处理。
- 取消或设备删除未成功，不清理其任务。设备已退出但数据库清理失败，不报告整体清理成功；保留原 journal 以便重试。
- 原有 `DevicePermanentDeletionContext.resume` 继续恢复未完成的删除事务。这是对已有 journal 的定向恢复，不新增其他入口的历史全量扫描；否则 App 中断后无法保证任务最终落库清除。

### 5.4 服务器同步时机与有限覆盖

- 只有实际持久数据发生变更才更新本地版本并排队上传。Scene 历史清理与同批待删除 Scene 收尾合并成一次逻辑变更；不为每个 Scene 单独发请求，也不经多次通知重复推进版本。
- 使用现有 `SpaceData.enqueueSpaceSync(site:level:)`，已持久化新版本时不再调用会重复更新时间戳的提交函数。Scene 页历史清理采用现有 `.slow`（等待 10 秒）的合并上传策略；这不是每 10 秒运行一次清理。设备删除保留原 `.network(.address)` 等即时同步语义，把任务清理一起提交。
- 数据未变化时不发请求。离线或上传失败保留持久待上传状态；由现有网络恢复/前台恢复机制重试，不依赖 Scene 页面存活，不新增定时器或恢复队列。若上传正在进行，不修改其已提交快照；等待已有生命周期完成后再判断当前版本。
- 首次打开 Scene 页前，历史脏数据可能仍存在于数据库、导出或其他 Scene picker；这是限制历史扫描触发范围后的明确边界。新发生的设备删除由入口 B 立即保证，不存在“等进入 Scene 页才清任务”的延迟。
- 云端完整导入不主动新增历史扫描。若引入旧残留，Scene 页下次实际进入，或该页可见时收到已有配置变更，按当前版本再次处理。既有版本/身份/权限保护继续阻止旧响应覆盖本次已提交的本地修复。

## 6. 实施任务（已完成自动化范围，运行验收见第 10 节）

### Task 1：将现场数据变成有行为断言的回归

涉及：`Tests/Scene/SceneDeletionFlowTests.swift`、`Tests/Scene/SceneConfigurationTests.swift`、Scene 页面已有生命周期夹具及对应脚本。

- [x] 建立脱敏夹具：当前节点 `0005 / 000E`，历史成员 `0008 / 0011`，6 个 Scene / 9 条引用；使用合成 UUID/Key，不提交原始导出。
- [x] 复现“pending 数组为空仍 unresolved”“删除后留下 remove”“SDK 行缺失而 App 行存在”。验证现有路径在清理完成后仍留下引用，形成失败用例。
- [x] 加入仍有效离线成员、混合新旧成员、同址换身份、未完成 Restore、其他设备级联任务，验证只能移除已确认退出的身份。

### Task 2：实现共用的身份清理与设备删除落库保证

涉及：`SceneConfigurationStore.swift`、`SceneConfiguration.swift`、`DevicePermanentDeletionCleanup.swift`。复用既有保护方法；不修改 `SpaceSyncCleanupCoordinator.prepareSpace` 来增加 Scene 扫描。

- [x] 复用 `SceneConfiguration.removingConfirmedIdentities(_:)` 作为成员/操作/引用统一变换，输入先经规范化。历史身份差集由可信完整快照产生，不修改 resolver 的身份规则。
- [x] 在 Scene Store 提供按显式 scope 读取候选、校验并提交的共用方法，遍历 **全部持久化 SceneInfo**，含 SDK 缺行的 tombstone。页面历史修复仅在存在候选时复用 `beginSyncReferenceCleanup` 和配置事务；设备删除继续使用原 journal 与原事务，不重复建恢复快照。
- [x] 永久删除路径复用相同规则，并把 Scene 成员、pending、级联引用及 Timed slot 的落库回读纳入完成判定；没有必要新增另一套 journal。
- [x] 事务失败保留可重试记录；成功后刷新 SceneInfo/live Scene 和页面缓存。所有无关成员、pending generation、Scene revision 均保持，依靠已有任务配置比较拒绝迟到回调；不使其他已成功设备重新全量同步。
- [x] 补充四类引用（Scheduler、动能开关、Power Switch、EFC）的身份/地址处理和既有 Restore receipt 生命周期回归。终态恢复证据按既有规则回收，正在迁移的证据先恢复，不直接丢弃。

### Task 3：Scene 页面准备、删除收尾与一次合并上传

涉及：`ScenesViewController.swift`、`SpaceViewController.swift` 的分页进入回调、`SceneConfigurationStore.swift`；必要时调整 `SceneDeletionCascade.swift` / `SceneServer.swift` 的共用收尾。`ImportData.swift`、通用同步、导出和上传前不增加历史清理调用。

- [x] 历史清理提交后，执行现有待删除 Scene 恢复/收尾；覆盖零设备、SDK 行已缺失、重复进入及持久化失败。不手工释放编号，不跳过 `canFinish`。
- [x] 在实际 Scene 页进入时调用共用准备方法，合并重复请求并记录成功检查的版本；详情和 picker 只读取结果，预加载/普通刷新不触发。授权、完整导入、pendingUpload 和 Restore 尚未完成时延后，不错误缓存为成功。
- [x] 只有候选变更才准备恢复证据、落库、收尾、刷新 SceneInfo 与 UI；同批完成后标记一次云变更，并通过已有 `.slow` 队列合并上传。检查无变更时数据库写入数和新增上传数均为 0。
- [x] 在清理、保存、页面退出、账号/Space 切换的异步边界复核 scope/版本，迟到任务不得修改新页面或新配置。已完成落库的上传不因页面关闭取消。
- [x] 非活动 Space 不新增历史扫描。原有云确认删除/跨 Space 设备转移仍复用同一永久删除 context，只清其已确认实例，不扩大成历史扫描或切换全局网络。
- [x] 保留既有云导入、冲突保护及失败恢复；验证清理结果上传、重启重试、旧响应到达和可见 Scene 页数据更新，无需服务器新接口或部署。
- [x] `SpaceCloudNodeRemovalPolicy.projectConfiguration` 未裁剪 `deletionReferences.pending` 的一致性问题保留为有界兼容检查：仅在复现证明确认删除被该比较阻挡时，复用同一身份变换修复；不借此新增全局扫描或扩大到无关云同步改造。

### Task 4：验证并更新本文档

- [x] 用真实 SceneInfo SQLite 写入、清理、重载和导出往返证明任务已从数据库清除；仅测试集合过滤或源码字符串不算完成。
- [x] 按修改范围运行现有 Scene model/targets、deletion flow/cascade、页面生命周期、设备永久删除/批量删除与 Timed slot 回归；复用的恢复/上传边界需有失败回归，不机械跑所有 Space 清理或同步套件。
- [x] 性能行为回归：分页预加载 0 次历史扫描；同版本重复进入复用成功结果；无残留时 0 次写入和 0 个新增上传；批量修复多个 Scene 只排一次合并上传。实际大项目进页耗时另由相同规模数据测量，不以调用次数代替体验验收。
- [x] 生产代码一轮完成后，核对 workspace/SDK 实际状态，以 SunSmart / Debug / generic iOS / `CODE_SIGNING_ALLOWED=NO` 构建一次，使用当前工作树独立 DerivedData。不跑 Simulator、不自动安装真机。
- [x] 共享逻辑影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux；无品牌差异时代表构建。若新增文件或资源，核对所有 target 归属并按项目规则扩大品牌编译。

## 7. 验证矩阵与现场预期

| 场景 | 必须满足 |
| --- | --- |
| 本次删除后快照 | 9 条旧成员及 Scene 2 的 1 条 remove 清除；Scene 2 收尾后剩 21 个 Scene，其他 5 个设备型 Scene 为空且无 Pending Sync |
| 删除前快照 | 完整成员基线确认后清掉旧成员；当前 `0005 / 000E` 及其有效组任务保持 |
| 删除一个、保留一个；被保留设备离线 | 只清退出实例，仍存在设备的待办继续可重试 |
| 取消 Force Delete / 部分批量成功 | 取消与失败的设备不清理；仅成功退出实例被处理 |
| 空 Space / 空 Scene | 允许无设备任务完成；不把缺字段、加载中或权限失败当作合法空数据 |
| 同地址换 UUID/Key；合法 Restore | 不向替代设备下发旧任务；Restore receipt 按原流程迁移 |
| 引用设备仍存在 | Scheduler/开关/EFC 的必要清理完成前不释放 Scene 编号 |
| 保存失败、应用中断、迟到 ACK | 不提前标记 cleaned；重进幂等恢复；迟到回执不复活已删除任务 |
| 云导入/上传/旧响应 | 导入不新增清理；进入 Scene 页后修复并排队上传；清理后的 SQLite、导出和重新加载一致，旧基线不能静默复活引用 |
| 只读角色、切换账号或 Space | 不跨 scope 写入，不以本地清理绕过服务器权限 |
| 正常项目 / 页面预加载 / 重复进入 | 未选中 Scene 不扫描；有效版本重复进入复用检查；无变更不写库、不排上传 |
| 多个 Scene 一次修复 / 离开页面 / 离线上传 | 合并一次逻辑变更与上传；离开页面后仍能依靠现有队列及持久状态完成同步 |
| 设备删除后始终不进入 Scene 页 | 本次设备的相关任务仍在删除事务中清完；中断则由已有 journal 定向恢复 |

建议人工最短路径：保留现有 App 数据升级 → 进入原 Site / Space 并完成已有云基线确认 → 实际选中 Scene 页 → 查看 Scene 2 自动收尾、其余 5 个设备型 Scene 无 pending → 删除其中一个空 Scene，应立即完成 → 退出重进并重启 App → 再导出并核对服务器回读。另补一次“部分设备离线后 Force Delete，全程不进入 Scene 页而直接导出”，确认已删设备任务已清空；重新加入设备后旧任务不转移给新身份。

## 8. 分析阶段的根因验证（实施前）

- 三份输入均成功解析；核对顶层业务数据和 `_debugInspection.rawLocal` 的 App/SDK 行，确认上述数量与差异。
- 使用 `scripts/check_scene_configuration.py` 的既有 `target_sources` 夹具，在临时目录编译并执行生产 `SceneConfiguration`、`SceneTargetResolver`、`TimedSchedulerPayloadPolicy.identity`。三份数据结果均为：6 个受影响 Scene、9 条成员、9 个 unresolved、0 个可解析目标；只传入当前节点身份执行清理后，9 条旧成员仍存在。
- 对照实验显式提供旧身份时，现有 `removingConfirmedIdentities` 可清除这些成员和 remove；真实 codec 编解码往返保留了现场状态。这说明需要补齐可信旧身份的发现、持久化调用及收尾，不需要放宽身份比较。
- 夹具的 Node/SDK 环境为替身，本轮未运行真实 SQLite 清理流程、完整 App 构建、UI、无线或云服务验收。上述结果是根因证据，不能表述为修复已完成。

## 9. 用户反馈后的范围修订

用户要求把历史清理限制在进入 Scene 页面，设备正常/强制删除时即时清除相关任务，避免其他入口重复清理。本次据此重写第 5～7 节，替代初稿在通用 Space 清理、导入、上传等边界添加扫描的建议。

当前代码核对：Scene 列表只由 Space 分页创建，详情由列表进入；分页提供实际 `didEnter` 回调。现有 `.common` 云变更采用 `.slow`（10 秒），`enqueueSpaceSync` 可上传已经落库的版本而不再次更新时间戳；网络恢复/前台恢复已有待上传恢复机制。删除 journal 的 `resume` 先检查是否有未清理记录，保留其定向恢复是数据可靠性要求，不新增全量检查。

此轮反馈只收敛方案；随后用户明确“确认实施此方案”，按两个触发入口完成以下实现。


## 10. 实施与最终验证（2026-11-04 14:50 +08）

### 10.1 最终行为

- `ScenesViewController` 的准备方法只在分页 `didEnter` 授予实际选中状态后运行；返回已选中的 Scene 页面、该页可见时收到已有权限/云完成通知也复用此入口。预加载、普通刷新、滚动、详情和 picker 不扫描。使用现有 `SpacePageRevision` 缓存成功检查；并发请求合并，失败不会自循环重试。
- 准备时比对持久化与活动网络的完整设备身份、全部已占用 Element 地址，包含离线及未配置完成的设备；缺失 Key、Scope 改变、保存版本改变、权限不足、未完成 Restore、Mesh 忙碌或上传/删除恢复未完成时延后。异步导出与基线核验后重新比对成员、待清理配置及 Restore receipt。
- 无候选不导出、不验证云基线、不写库、不排上传。有候选才使用既有 reference-cleanup journal；App 配置与本地版本在同一 SQLite 事务中落库，成功后安装 live SceneInfo，再通过原 `finishDeletion` 收尾。失败保留 journal，交给已有恢复/上传流程；已落库上传不依赖页面存活。无变更的成功检查是零写入；发生存储失败时允许排一次既有恢复操作。
- 成功修复一次只推进一个本地版本，并排一次 `.slow` 上传。现有队列负责离线与失败重试；未新增计时器、全局扫描、持久化标记或第二套恢复机制。
- 永久删除共用模型规则清除成员、write/remove、四类级联任务；只有地址而无身份的旧记录必须由已确认空缺地址授权。增加 Scene 落库回读与 Timed slot 回读，相关任务未清空不能将 deletion journal 标记 cleaned。SDK 缺行的 tombstone 也使用原收尾方法完成删除。
- Restore 已验证的新实例被永久删除时，依据同 Scope/同恢复 generation 的 receipt 清除其尚未迁移的旧身份任务；当前仍存在的旧实例继续保留。关联 receipt 在清理回读后删除，写失败保留 deletion journal 以便重试；未关联 receipt 保持不变。
- 云删除投影的有界检查复现了差异：原 `projectConfiguration` 会留下 `deletionReferences.pending`，与 App 侧已清理配置不一致。已复用同一身份/地址变换，保留 Key 缺失时的严格身份边界。这只是 App 内比较规则一致性修正，没有新增清理触发，也不要求服务器配套。

### 10.2 回归与构建

Swift 独立脚本统一指定 `CLANG_MODULE_CACHE_PATH` 和 `SWIFT_MODULECACHE_PATH` 为 `/tmp/sunsmart-scene-cleanup-module-cache`，避开默认 Clang cache 的沙箱权限问题；没有删除共享缓存。

| 检查 | 最终结果与范围 |
| --- | --- |
| `check_scene_configuration.py --suite model` | 30 passed，含四类级联引用、未知身份的空缺/占用地址保护 |
| `check_scene_configuration.py --suite targets` | 28 passed，保持原身份与目标解析边界 |
| `check_scene_deletion_flow.py` | 通过：6 Scene / 9 旧成员、真实 SceneInfo SQLite、事务失败回滚、重载、导出记录、SDK 缺行收尾、重复检查、迟到 ACK、Restore 及 receipt 写失败 |
| `check_scene_deletion_flow.py --page-cleanup` | 通过：实际生产页面准备逻辑 + SQLite；无候选零写入/导出/上传、一次上传、权限/Restore/忙碌 gate、异步退出/Scope/成员/配置改变、预加载及重复进入合并 |
| `check_scene_deletion_cascade.py` | 204 passed，四类实际级联依赖与收尾保护 |
| `check_scene_deletion_ui.py` | 列表和详情的删除确认、离线 pending、失败、完成与重试均通过 |
| `check_device_permanent_deletion_cleanup.sh` | 通过，含云删除投影与本地 Scene 清理相等、重复投影稳定；新用例在修复前明确失败、修复后通过 |
| `check_lights_batch_deletion_context.py` | 通过，删除准备、取消/强制删除及恢复授权；修正旧脚本过宽源码提取和落后于生产接口的替身 |
| `check_proximity_scoped_import.py` | 实际永久删除/恢复/部分成功/Force Delete/Site 隔离链通过；128 设备批次保持 2 次网络载入、1 次保护快照、1 次通知 |
| `check_timed_device_slots.py` | 通过，身份/旧数据/空目标/解绑及 slot 规则 |
| `check_timed_slot_persistence.py` | 通过，真实 Schedule SQLite、旧数据、失败回滚、重载、Scene/Timed 关联 |
| `check_space_recovery_receipts.py` | 通过，实际恢复文件、旧/迟到云响应、权限与 generation、清理失败重试、版本保护、上传回读及严格字段比较 |
| `git diff --check` | 通过 |
| SunSmart Debug / generic iOS | 最终代码 `BUILD SUCCEEDED`；使用 `SunSmartLocal.xcworkspace`、`-sdk iphoneos`、`CODE_SIGNING_ALLOWED=NO`，未运行 Simulator 或安装真机 |

构建命令：

```sh
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-cli CODE_SIGNING_ALLOWED=NO
```

SDK 仍为 `one-dev` / `dbcf6f1` 加任务开始前已有的 Scheduler/MeshProxy 未提交差异；没有新 SDK API 或依赖声明变化。共享逻辑影响五个品牌，没有新增生产文件、资源、条件编译或品牌分支，因此选择 SunSmart 代表构建。补充云比较修正后进行了最终增量重建；无关 Release/其他品牌构建未重复执行。

### 10.3 证据边界与人工验收

- Scene Store 和 Schedule 的 SQLite 流程真实执行；页面测试的 UIKit、网络导出、云请求/队列和恢复文件为控制边界。实际恢复文件/云状态机另由 recovery suite 覆盖，不能合并宣称已经完成整 App 的服务器往返。
- 永久删除链路测试执行生产 context、清理、journal 及拓扑流程，SDK/存储以替身隔离；其中 whole-Scene 收尾明确为边界，独立 Scene suite 才执行真实 App SQLite 收尾。未将集合过滤或源码断言当作数据库删除证明。
- 尚未验证真实分页生命周期、蓝牙设备、服务器 get spaceprops 回读、离线重启后整条自动上传及大项目进页耗时。调用次数断言只证明没有新增全局/重复扫描，不是整 App 性能测量。
- 最短人工验收沿用第 7 节：保留当前数据升级，进入原 Site → Space → Scene，预期 Scene 2 收尾、其他 5 个设备型 Scene 无旧 pending；删除空 Scene、退出重进/重启后再导出并比对服务器。另做正常删除和 Force Delete，删除后不进 Scene 页直接导出；有效离线设备的任务应仍保留。
- 工作树未 commit/push，用户原始样本与 SDK 原有未提交改动均保留；无需服务器或固件部署。
