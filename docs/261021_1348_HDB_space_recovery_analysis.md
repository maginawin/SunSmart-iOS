# Space 进入时提示无法保存：HDB 旧数据兼容性分析

日期：2026-10-21。分支：`feat/HDB-261020`。核对完成时 HEAD：`5f90fbcd`。

## 修复交付（2026-10-21，用户确认后）

已在 `HDBConfiguration` 的共享解码入口修复，保持现有成员初始化及编码格式：缺失 `broadcast` 时恢复为空广播配置；显式 null、错误类型及非法配置仍拒绝。旧根级 `lightingConfiguration` 为缺失或 null 时允许兼容，有实际值时继续拒绝，防止未经迁移静默丢失设置。

没有改动普通保存保护、网络身份检查或恢复状态机。重新加载合法旧 HDB 后不再设置 `hdbLoadFailed`，已有导入流程可以完成保存，并在成功 finalization 后清除 `invalidStoredHDB`。真正损坏的本地数据仍受原有保护。

验证结果：

- `check_hdb_configuration.py`：通过；覆盖 63-Zone 旧格式、本地/云端解码、编码重载、广播设置保留、错误类型/必填字段/非法 Zone，以及有值旧根配置的拒绝。
- `check_hdb_import_recovery.py`：通过；使用实际生产保存保护与导入准备代码，验证导入前普通保存、旧格式 GET 准备、HDB 模拟持久化重载，并保留 4-node 输入。SQLite、完整 Mesh 导入为测试边界。
- `check_hdb_persistence.py`：通过；确认旧服务端 HDB 与新编码本地配置比较一致，保留原有引用、冲突和失败保护。
- `check_space_recovery_receipts.py`：通过；验证真实恢复状态/文件逻辑清除 `invalidStoredHDB`、导入标记，保存可比较的基线；数据库 checkpoint 在该测试中为替身。
- 原始两份样本使用生产模型解码通过，HDB 相同，63 个 Zone 及服务器 Group 引用有效，编码重载保持一致；未写回样本。
- `SunSmartLocal.xcworkspace` / `SunSmart` / Debug / generic iOS / 禁用签名构建通过。最终兼容保护补齐后增量构建再次退出 0；首轮有其他源码的 weak capture 警告。
- SDK realpath 为约定的 `nordic-sig-mesh-sdk-worktrees/one-dev`，revision `8c5af55`，检查时无未提交修改；本次未改 SDK 或依赖。
- 此解码为五品牌共享 Foundation 逻辑，无品牌条件路径、资源或配置变更；使用 SunSmart 代表构建。

工作树中另有外部产生的 `HDBLightingConfigurationViewController.swift` 修改，本任务未编辑或回退该文件。未提交本任务修改。

待人工验收：安装新构建并重新启动 App，进入原 Space；若显示恢复页，点击 Retry Recovery。预期不再出现无法保存提示，63 个 Zone 和 4 个设备仍在；退出重进及重启后保持正常。尚未运行手机 UI、真实 SQLite 恢复事务或在线云端往返，不以隔离回归和编译替代这些验收。

## 结论

本次样本的直接根因是 App 的 HDB 解码兼容性缺口：本地 SQLite 和服务器均保留不含 `broadcast` 的旧 HDB 结构，当前 `HDBConfiguration` 新增非可选 `broadcast`，但未实现旧格式解码兼容。实际生产模型对样本报 `DecodingError.keyNotFound("broadcast")`。

加载失败使 Space 被标记为 `invalidStoredHDB`。进入时的恢复流程先保存本地候选 Space；保存被 HDB 失败标记拒绝，在云端业务配置导入前返回 `configurationPersistenceFailed`，UI 将它映射为 “The configuration could not be saved on this phone.”。此样本有明确的数据兼容性原因，不能把提示直接解释为磁盘容量或服务器保存失败。

初始分析阶段未修改业务代码、原始样本或服务器；当时只做样本分析、当前源码核对和隔离复现。分析期间既有暂存修改已由外部操作提交到上述 HEAD，本任务没有执行 Git 提交或改动这些内容。用户后续确认实施后的结果见上方“修复交付”。

## 输入与证据

- 本地文件：`/Users/maginawin/Desktop/doing/wwd/Space_Space 1_20261021_134350_821+0800.json`。
- 服务端文件：`/Users/maginawin/Desktop/doing/wwd/server data.json`。
- 本地文件是诊断导出：`_debugInspection.uploadable=false`。顶层 `spaces[0]` 仅有名称和 UUID，不代表本地业务配置已被清空；实际持久化数据在 `_debugInspection.spaces[0].rawLocal`。
- 本地 HDB 路径：`_debugInspection.spaces[0].rawLocal.app.spaces[0].hdb.json`。
- 服务端 HDB 路径：`data.spaceData.hdb`。

| 检查项 | 结果 |
| --- | --- |
| 两端 HDB 内容 | JSON 结构和值完全相同 |
| HDB 根字段 | `schemaVersion`、`lightingZones`、`devices`；缺少 `broadcast` |
| Schema | 两端均为 1 |
| Lighting Zones | 63 个，zoneId 1～63，groupAddress 49153～49215 |
| HDB devices | 空数组 |
| Mesh nodes / groups | 两端均为 4 / 63 |
| Space UUID、NetKey、AppKey | 两端一致，仅记录比较结果，不复制密钥 |
| 本地时间戳、最后确认时间、服务器更新时间 | 均为 1792551575，即 2026-10-21 10:59:35 +08:00 |

本地诊断记录：

- `blockedReason=invalidStoredHDB`，`comparisonPayloadAvailable=false`。
- `lastSyncDiagnostic.stage=cleanupPreparation`，`error=-2005`。该错误在 App 内对应 `configurationReviewRequired`，不是服务器 HTTP 错误码。
- `membershipPhase=joined`、`membershipNetworkMatches=true`、`recoveryPhase=active`、`recoveryAuthority=writable`。
- `pendingImport=false`、`pendingUpload=false`、`pendingDeletionCleanup=false`。

## 源码因果链

1. `SunSmart/Common/Data/HDBConfiguration.swift`：`HDBConfiguration.broadcast` 为非可选属性，使用合成的 `Decodable`。声明处的默认实例用于普通初始化，不会让合成解码自动接受 JSON 缺字段。
2. `SunSmart/Common/Data/Database.swift`，两处 Space 加载路径：解码 HDB 抛错后设置 `hdbLoadFailed=true`，并调用 `SpaceConfigurationSafety.block(..., reason: "invalidStoredHDB")`。
3. `SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift`：清理准备要求 `canCleanSyncReferences`；`invalidStoredHDB` 不在允许继续的原因中，失败记录为 `cleanupPreparation`。`ExportData.swift` 也拒绝从 `hdbLoadFailed` 的对象生成正常配置导出。
4. `SunSmart/Main/Site/Controller/SiteViewController.swift` 的 `loadSpaceReqeust` 收到 GET 后调用 `restoreConfiguration`。
5. `SunSmart/Common/Data/SpaceMembershipCoordinator.swift` 的 `restoreConfiguration` 复制本地 Space，先执行 `candidate.save()`，之后才调用 `candidate.update(...)` 导入服务器配置；复制会保留 `hdbLoadFailed`。
6. `Database.swift` 的 `save(importingConfiguration: false)` 首先拒绝 `hdbLoadFailed`；即使内存对象未带失败标记，重新加载的持久化行存在同样错误时也会被拒绝。因此恢复入口返回 `configurationPersistenceFailed`。
7. `SunSmart/Main/Space/Controller/SpaceRecoveryViewController.swift` 将该 reason 映射到 `space_recovery_storage_failed`，即用户看到的英文提示。

这还形成恢复阻断：只修改服务端的 `broadcast` 无法绕过本地导入前保存；只清除 blockedReason 也无法消除真实解码错误。当前原始服务端 HDB 自身也不能通过同一个解码器。

## 隔离复现与边界

直接使用当前生产文件 `HDBConfiguration.swift`、`HDBLightingZonePolicy.swift`，通过 `swiftc` 编译临时命令行探针，读取样本中提取的无密钥 HDB 和 Group 引用信息：

- 原始 HDB：确定失败，`keyNotFound("broadcast")`。
- 仅在临时内存副本补入 `broadcast: { lightingConfiguration: null }`：解码、`validate`、`validateReferences` 均通过，63 个 Zone、0 个 HDB device 保留。
- 这说明本样本中 Zone 缺少可选 `lightingConfiguration`、HDB devices 为空以及 63 个 Zone 本身均不是该解码失败的原因。4 个 Mesh node 尚未对应 HDB device 是另一项业务状态，不应借本次兼容处理自动补建或宣称完成设备初始化。
- 历史提交 `e00aa89b` 的 HDB 根模型只有上述三个字段；`9c23a0e0` 仍无 `broadcast`。因此样本符合项目旧结构，不能仅因当前模型不接受就认定服务器返回损坏数据。

没有运行完整 App 构建、手机 UI、SQLite 真实恢复事务或在线服务器往返；隔离结果证明的是样本解码失败及最小字段差异。样本不包含安装包 revision 或本次恢复调用完整日志，具体手机执行序列按当前源码及诊断状态推导，未作运行抓取。

## 初始建议修复边界

1. 在共享 HDB 解码入口接受已知旧格式缺少 `broadcast`，按未配置广播处理；继续严格拒绝错误类型、非法 Zone、设备引用和网络身份。不能用解码失败后整体置空 HDB 来恢复。
2. 对其他历史形态，如旧根级 `lightingConfiguration`，先确认迁移语义，避免兼容解码吞掉已有设置。本样本没有该字段，也没有设备级配置，不足以决定所有历史结构的迁移规则。
3. 验证完整恢复路径：旧 SQLite 行加载、GET 同格式导入、保存及重启、正常导出、成功导入后的 block 清理。对真正不可解码的本地数据与有效云端副本，单独验证导入前保存保护是否阻止合法恢复；不可直接放宽普通保存保护。
4. 最小回归应包括本样本缺 `broadcast`、当前完整结构、非法 `broadcast` 类型，以及旧数据恢复后保留 63 个 Group / 4 个 Node。App 实施后再按项目要求构建代表 scheme，并由用户验收重新进入 Space / Retry Recovery。

本次根因可在 App 端处理，无证据要求固件或服务器修改；不要通过人工删除 Space 或清空配置规避兼容问题。
