# 删除最后一台设备后无法再次添加：数据分析

结论：App 已完成本地设备删除，并提交了空设备配置；服务器返回相同的新版本号和 `deviceCount = 0`，但 `nodes` 仍包含已删除设备。App 上传回读发现成员配置不一致，记录 `uploadReadbackConflict`，从而关闭该 Space 的添加、编辑和删除权限。

已证实故障停在云端配置回读一致性环节。服务器内部究竟是空数组未执行删除、关联记录未清理、缓存未失效，还是并发旧写入覆盖，现有两份数据不能区分。优先由服务端核对该 Space 的同步写入与读取链路，不应通过忽略 `nodes` 差异或清除 App 保护标记掩盖问题。

## 样本与范围

- App 导出：[Space_空间 1_20261103_144650_148+0800.json](</Users/maginawin/Downloads/Space_空间 1_20261103_144650_148+0800.json>)。
- 服务器 GET 返回：[cannot add device again.txt](</Users/maginawin/Desktop/cannot add device again.txt>)。
- Site：`753F917F-E479-4BF1-B16A-08FA03CBB279`。
- Space：`1C7947F2-27E8-4123-98D3-8999936DF4AB`，名称“空间 1”。
- 删除设备：`6BC3D933-4163-4E05-943C-26CCBE9C81FA`，名称 `L1`，Primary 地址 `0005`，3 个 Elements，PID `2503`。
- 分析代码：`feat/device-scene-261028`，HEAD `ba8e608c`。仅分析及新增本文档，不修改业务代码、SDK、服务器或配置。

## 直接证据

| 项目 | App 本地/提交状态 | 服务器返回 |
| --- | --- | --- |
| `uuid` | 上述 Space | 完全相同 |
| `updateTimestamp` | `1793688390` | `1793688390` |
| `deviceCount` | `0` | `0` |
| `nodes` | `[]`；原始 Mesh 存储也为 `[]` | 1 台，正是已删除 UUID、地址 `0005` |
| Groups / Scenes / Schedules | 均为空 | 均为空 |
| `spaceData` | 空 Scene 配置、空 Trigger Zone 等 | 与本地完全一致 |
| NetKey / AppKey | 有效本地配置 | 两份样本逐字段一致，不在本文记录密钥 |
| 所有者 | 本地有写权限 | `role = owner`，owner 与导出用户一致 |

本地状态明确记录：

- `deletionSummary.kind = localDeletion`、`stage = cleaned`，UUID 与服务器残留设备一致。
- `pendingDeletionCleanup = false`、`pendingImport = false`。
- `configurationInitialized = true`、`membershipPhase = joined`、`membershipNetworkMatches = true`。
- `recoveryPhase = active`、`recoveryAuthority = writable`、`requiresRemoteImport = false`、`unbindRequested = false`。
- `submissionPhase = accepted`、`submittedTimestamp = 1793688390`、`pendingUpload = true`。
- `blockedReason = uploadReadbackConflict`。
- `lastReadbackDiagnostic.stage = remoteValidation`、`reason = remoteConfigurationMismatch`、`error = -2002`。

因此，本地清理未完成、成员初始化缺失、访客权限和网络密钥差异均不是本样本记录的阻断原因。`-2002` 是 App 的“配置上传尚未确认”错误，不是服务器 HTTP 错误码。服务器接口的 `code = 200` 不代表回读配置与提交内容一致。

导出中的 `_debugInspection.uploadable = false` 是调试检查文件的固定标识，不能据此认定上传失败原因。服务器缺少 `appKeyIndex` 是现有代码允许的冗余字段缺省，也不是这次冲突。

## 提交内容与旧基线的交叉核对

按当前 `SpaceConfigurationIntegrityPolicy.configurationData` / `serializeConfiguration` 的规则，对本样本为空的 Group、Scene、Trigger Zone 及设备成员生成比较数据，并以排序后的紧凑 JSON 计算 SHA-256 前 8 字节：

| 配置来源 | 计算所得摘要 | 导出中持久化摘要 | 结果 |
| --- | --- | --- | --- |
| 本地空设备配置 | `24aab134cb68ebe5` | `submissionSHA256 = 24aab134cb68ebe5` | 一致 |
| 服务器含旧设备配置 | `fac0f7d782cbb3f7` | `baselineSHA256 = fac0f7d782cbb3f7` | 一致 |

本次差异就是 `memberships`：本地为 `[]`；服务器为原 UUID、`unicastAddress = 0005`、`groupState = 0`。服务器空字符串 `groupAddress` 按现有规则移除后仍存在该成员差异。

这说明当前本地比较配置与持久化提交摘要一致，而服务器的成员配置仍对应删除前已确认基线。该摘要覆盖 App 用于回读校验的配置，不代表服务器全部原始 JSON 与旧数据逐字相同。

## 时间顺序（UTC+08:00）

| 时间 | 记录 |
| --- | --- |
| 2026-11-03 14:45:38 | 创建 Space，`createTimestamp = 1793688338` |
| 14:46:18 | 最近一次确认上传，`lastConfirmedTimestamp = 1793688378`，基线设备数 1 |
| 14:46:29 | 设备本地删除清理完成，`completedTimestamp = 1793688389` |
| 14:46:30 | 本地/提交版本 `1793688390`；服务器返回版本也是该值 |
| 14:46:42 | 最近一次回读诊断为 `remoteConfigurationMismatch` |
| 14:46:50 | 导出 App 检查数据，仍保留 accepted 提交和保护状态 |

两份文件不包含当时的完整 HTTP POST 原始请求、响应及服务器写入日志；`accepted` 是 App 已处理上传成功响应后保存的状态，不等于节点删除已在云端正确生效。

## 为什么再次添加被禁止

1. [ExportData.swift](../SunSmart/Common/Data/ExportData.swift) 的 Space 导出始终写入 `nodes` 与其实际数量 `deviceCount`；合法空设备列表仍写为 `[]`。上传参数直接包含完整 Space 快照。
2. [CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift) 在请求前保存提交比较数据，上传成功响应后标记 `accepted`，随后调用 `resumeUpload` 回读确认。
3. [SpaceConfigurationIntegrityPolicy.swift](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift) 从 `nodes` 生成 `memberships`；不使用 `deviceCount` 替代真实成员列表。空成员与残留一个成员不相等。
4. [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift) 的 `resumeUpload` 对同一提交最多回读 3 次，仍不一致就写入 `uploadReadbackConflict` 并返回 `-2002`。本次是普通本地删除，且删除完成版本早于提交版本，不适用较晚的云端移除/替换记录对旧提交的投影处理。
5. [SpaceData.swift](../SunSmart/Common/Data/SpaceData.swift) 的 `deviceOperates` 在保护状态下最多返回 `.control`，不再包含 `.add`。Group、Scene、Schedule 的配置权限也受同一保护影响。
6. [DeviceLightsViewController.swift](../SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift) 依照 `.add` 禁用添加按钮，点击入口再次检查；Switches 页面也遵循相同权限。该路径在进入实际配网之前已经拦截。

## 重试与恢复边界

后台同步和重新进入 Space 允许带有 pending submission 的受保护空间继续回读。同步任务先运行 `resumeUpload`；它返回失败时任务结束，不会继续发送新的完整快照。所以服务器持续返回旧设备时，反复同步仍会停在同一冲突。

如果服务器同版本回读恢复为本次提交的空配置，现有流程可将提交标记为 verified，更新确认基线、清除 pending submission 和本次 `uploadReadbackConflict`，从而恢复添加权限。服务器若返回更高版本，则进入现有较新云端导入流程，仍需联调确认结果。

不建议在云端残留设备尚未纠正时选择“重新加载云端数据”作为本次修复：该数据仍包含已删除设备。直接清除保护或把 accepted 当作最终成功，也不能保证设备成员一致性。

## 服务端核查与验收

责任方：服务端团队；本任务仅提供核查契约，不修改后端、数据库或运行配置。

1. 定位上述 Site/Space 在 14:46:29–14:46:42 的 `/sitespace/sync/spaceprops` 或 `/sitespace/sync/siteprops` 写入，核对实际解码后的 Space 版本 `1793688390` 和显式 `nodes: []`。本样本不能确定本次具体由单 Space 还是 Site 批量上传发出。
2. 对显式空 `nodes` 按全量设备集合语义清空该 Space 的成员关系；缺少字段与空数组不能混为一谈。检查是否仅更新 Space 头部版本/计数，或只 upsert 非空节点而未删除缺席成员。
3. 核对 `/sitespace/get/spaceprops` 的数据库关联查询、缓存及异步写入结果。确保已删除 UUID 不再由旧关系或缓存回填；同一已接受版本的头部与成员集合应一致。涉及其他 Space 的设备时，仅处理当前 Space 归属，不全局误删其他归属。
4. 修复后回读应为目标 Space、正确网络身份、`nodes = []`，计数与集合一致。让原 App 重试同步，确认错误与保护解除，然后重新添加设备。
5. 验收覆盖删除最后一台、删除部分设备、同一设备重新加入、退出重进。重新添加后云端仅有当前有效设备实例，本地与云端数量及成员一致，不复活旧实例。

目前不需要新增 SDK API 或固件协议来解释或解除已定位的回读冲突。是否有固件 Reset/广播异常属于后续实际重新配网验收；本次文件不包含对应 BLE 运行证据。若后端修改必要，由服务端独立发布并完成上述联调；App 离线检查不能代替该发布结果。

## 本次验证

- 两份原始数据定向比较及比较摘要复算完成，未输出或复制完整密钥。
- `python3 scripts/check_space_recovery_receipts.py` 退出码 0。现有用例包含：提交空设备、服务器 `deviceCount = 0` 但返回旧节点时连续 3 次回读仍拒绝确认并保留保护；随后匹配的回读解除保护。
- 上述是现有生产逻辑的隔离回归，网络、数据库及部分 SDK 为测试边界；样本摘要复算为 Python 定向验证，并未将原始样本送入真实服务器。
- 未执行 App 构建、真机操作、固件 Reset 验证或服务器写入/联调。分析过程中发现的工作区其他任务改动保持不动。
