# OFFICE Space 升级后持续同步失败分析

日期：2026-09-21。本文保留修复前的调查与复现，末节记录用户确认后的 App 修复及验证。未修改 SDK、客户数据或服务器。

## 结论

服务器样本的邻近照明配置有效，不能把“邻近照明数据无效”直接解释为该 Space 的路径或触发区域损坏。已经复现 1.2.6 升级同步链路中的一个缺陷：兼容预检失败被外层忽略，后续严格比较把合法旧格式差异转成持久保护状态，导致普通同步重试持续失败。

这条路径能解释用户描述的现象，但尚不能确定它就是客户手机第一次失败的实际路径。缺少该手机的本地配置、保护原因及现场日志，无法排除本地存储异常、真实配置差异或其他未完成恢复状态。不能将隔离故障注入说成客户现场已证实的根因。

## 输入与版本

- 用户说明：客户使用 TestFlight，Space 由 1.2.0 创建，后升级到 1.2.6；无法从该版本导出本地 JSON。
- 输入：[服务器返回 JSON](</Users/maginawin/Desktop/tmp/ap invalid sync space.json>)，顶层为 `message/code/data`，不是手机数据库快照。
- Space：`OFFICE-COR & WC`；普通组：`OFFICE / C008`；9 台设备。
- 当前工作树：`fix-gateway`，HEAD `ddc1e8a9`（TestFlight 1.2.7），调查开始时无未提交改动。
- 1.2.6 tag 对应 commit：`2b131861fb8b70251bd063b810f159902a3bcfdb`；1.2.0 tag 对应 commit：`954c51999a5be2e24d7d56f0def0e87a2bd8a2be`。
- 本文涉及的 Safety、Integrity、Cleanup、Export 与 CloudSynchronizationManager 核心文件在 1.2.6 与当前 HEAD 间无差异。因此不能建议“升级到当前 1.2.7 就会解决”。
- 本机 workspace 映射为 `SunSmartLocal.xcworkspace → .local-sdk/nordic-sig-mesh-sdk → nordic-sig-mesh-sdk-worktrees/one-dev`，SDK HEAD `a971027`。SDK 有其他任务的未提交改动，本轮仅查看，未修改，也未用于宣称客户二进制行为。

## 样本校验结果

直接编译 1.2.6 的生产 `SpaceConfigurationIntegrityPolicy`、`SpaceSyncCleanupPolicy`、邻近照明策略与 Reconciler，对输入执行检查：

| 项目 | 结果 |
| --- | --- |
| Profile | type = 8，Relay = 1，Profile 校验通过 |
| Group 成员 | 9 台设备声明 C008、groupState = 1，实际订阅一致 |
| 地址 | 引用均对应现存设备；Vendor Model 位于主元素，不涉及主地址与 Vendor 地址偏移 |
| Sequence | `[569,572,575]`、`[578,581]`，均有效 |
| Group Trigger Zone | `[554,557,575]`、`[581,584,587]`，均有效 |
| 清理结果 | repairs = 0，hardErrors = 0 |
| 邻居数量 | 最大 3，未触及 184 上限 |
| 节点缓存与逻辑目标 | 9 台的 Enabled、Relay、邻居集合全部匹配 |

这里的节点缓存来自服务器记录，不是此次读取真实灯具的结果。它不能证明当前 Mesh 状态或手机其他同步任务已完成。

另运行现有 `scripts/check_proximity_scoped_import.py --snapshot <输入文件>`，输入通过生产导入预检。此夹具的 Node/Group 解码与存储边界使用替身，不能替代完整 SDK 解码、手机数据库加载或 App 运行验收。

## 旧格式差异：存在，但正常路径已有兼容

样本的 `spaceData = {}`，Profile 缺少 `calibrationMode`、`targetNightBrightness`。1.2.6 当前导出会补出：

- `spaceData.proximityLightingSchemaVersion = 1`；
- `spaceData.triggerZones = []`；
- 本例 Profile 的 `calibrationMode = none`、`targetNightBrightness = 50`。

`configurationData` 不把这三个缺省字段统一为默认值。因此仅补出上述字段，直接比较会得到三个差异：`calibrationMode`、`targetNightBrightness`、`triggerZones`。schema version 本身不进入这个配置比较。

但是，`SpaceSyncCleanupPolicy.baseline` 已经针对这三个旧格式缺省值做兼容。对同一份样本执行正常同步前的迁移比较，结果为相等，并能建立迁移标记、允许上传。

**所以，“旧字段缺失导致所有升级用户必然失败”不成立。真正的问题是两条比较路径不一致，以及预检失败后继续执行。**

## 已复现的持续失败链

相关入口与代码：

- [CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift)：`SyncOperation.getNetworkApi` 的 `.syncSpace` 分支。
- [SpaceSyncCleanupCoordinator.swift](../SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift)：`prepare / perform`。
- [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift)：`verifySyncCleanupBaseline`、`prepareUpload`、`readUploadedConfiguration`、`isBlocked`、`canCleanSyncReferences`。
- [SpaceConfigurationIntegrityPolicy.swift](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift)：`configurationData`。
- [SpaceSyncCleanupPolicy.swift](../SunSmart/Common/Data/SpaceSyncCleanupPolicy.swift)：`baseline`。

触发前提：旧 Space 已上云，尚未建立新版本的 `spaceConfigurationMigrated` 标记；正常兼容预检在完成迁移前返回失败。

1. `.syncSpace` 先调用清理/兼容预检，但用 `_ = await ...prepare(space)` 忽略返回值。
2. 在隔离复现中，让 `verifySyncCleanupBaseline` 的服务器请求失败一次。此时没有写迁移标记，也没有写永久阻塞标记；本应保留为可重试状态。
3. 外层仍调用 `space.export(purpose: .cloudSync)`，进入 `prepareUpload`。
4. `prepareUpload` 发现尚未迁移，再请求服务器。这次请求成功，返回本例旧格式。
5. 此处使用 `configurationData` 的严格比较，没有使用前置迁移的兼容规则；三个合法旧格式差异导致比较失败，写入 `upgradeBaselineNeedsImport`。
6. `isBlocked` 此后为 true。该原因不在 `canCleanSyncReferences` 的允许列表，下一次正常兼容预检直接拒绝；普通导出也因 blocked 拒绝。
7. 因而继续点普通同步不会重新完成迁移。隔离复现确认：后续清理及上传准备再次失败，连新的网络请求都没有发出。

这是“前置兼容预检未完成 → 后置严格比较误判 → 持久保护标记阻断普通重试”的可复现路径。第一次预检失败在客户现场可能有不同原因；本轮只注入了一次网络失败，不推断客户实际发生过该网络错误。

## 为什么文案会变成“邻近照明数据无效”

`SpaceData.export` 使用可空返回值承载很多失败原因：保护状态、未完成导入、Group/Profile/Zone 加载失败、拓扑校验、迁移/权限及快照保存失败等。

`getNetworkApi` 拿不到导出结果时返回 nil；`finishExportFailure` 优先复用已有 `syncCloudError`，没有时默认 `.configurationExportInvalid`。[NetworkRequest.swift](../SunSmart/Common/Network/NetworkRequest.swift) 将它映射为“邻近照明数据无效，无法导出。”

因此，该文案没有准确表达失败阶段，也不能证明服务器邻近照明配置损坏。进入保护状态后，Space 顶部还可能改为显示“同步失败”及配置核对恢复弹窗。若进入设备同步，配置可用性门禁也能阻止执行，但客户尚未明确提示所在页面，不能断言现场 BLE 任务已发出或失败。

## 隔离复现与边界

复用现有 recovery receipts 装配脚本，在临时目录注入两个对照场景；网络、Space 对象和数据库检查点沿用既有测试替身，执行生产 Safety 方法，未连接客户服务器、蓝牙或设备：

| 场景 | 实测 |
| --- | --- |
| 旧样本，兼容基线请求成功 | 建立迁移标记，上传准备通过，未 blocked |
| 旧样本，兼容基线请求失败一次，后续严格回读成功 | 上传准备失败，blocked reason 为 `upgradeBaselineNeedsImport` |
| 上述状态再次清理/上传准备 | 仍失败；网络调用计数不增加 |

第一次装配因现有脚本未包含 `SiteGatewayLastOnlineSnapshot` 的依赖而无法编译；仅在临时装配中补入生产 `SiteGatewayAssociationConsistencyPolicy.swift` 后完成上述复现。没有修改仓库脚本，也没有把原有完整 receipts 套件称为通过。

没有运行 App 构建、Simulator、真机或真实服务器往返。分析范围内无需构建；客户 TestFlight 的本地状态未取得。

## 建议处理方向

### App 修复范围

1. 让正常升级与上传准备使用一致的、范围明确的旧格式比较；只兼容已知省略默认值，不忽略真实 Group/节点/路径/非空 Zone 差异。正式提交后的回读确认不能一并放宽为允许字段丢失。
2. 不把失败的兼容预检无条件丢弃；至少区分未准备好、瞬时失败与需要用户核对，防止继续走另一套规则并制造永久阻塞。
3. 对已经进入 `upgradeBaselineNeedsImport` 的 Space 提供范围明确的恢复：重新获取云端并校验双方完整配置，仅在兼容规范化后等价、无待处理导入/删除/真实本地变更时解除该原因；否则保留现有核对入口。
4. 将失败阶段和保护原因传到错误展示，区分配置不可用、迁移需核对、拓扑无效与网络失败。不能所有 nil 导出都默认归因于邻近照明。
5. 添加正常升级、一次预检失败后恢复、已有阻塞恢复及真实配置冲突的行为回归。无需为此修改 SDK 或服务器配置。

上述范围已获用户授权实施；具体改动和验收边界见文末。

### 客户处理与最小现场证据

1.2.6 的 `debug_features.json` 确实将 JSON 导出限制为 DEBUG；客户通过 TestFlight 看不到入口符合代码配置。现阶段不依赖客户提供完整本地 JSON。

先确认提示所在页面以及点击顶部失败标记后出现的完整文字/恢复选项。若能发布诊断版本，最有价值的是导出阶段、`blockedReason`、是否完成迁移、是否有 pending import/cleanup、Group/Profile/Zone 加载状态及脱敏差异路径；不需要 Mesh 密钥或整份配置。

如果客户确认服务器这份配置就是希望保留的最终配置，且手机没有需要保留的未同步修改，可尝试已有的“重新加载云端数据”入口。该操作成功完成有效导入后会清除保护并建立迁移标记，但会采用云端配置，应由客户明确选择；本轮未执行或验证该客户的恢复。仅重复普通同步不会处理已形成的保护状态。

## App 修复实施记录

### 已实现的行为

1. 升级导入校验、同步清理基线及上传前的升级比较共用 `upgradeConfigurationData`，只补齐已知旧格式默认值。未知 schema、schema 1 缺少必需 Zone 字段、非空 Zone 及真实配置差异不会因此被忽略。正式提交/恢复回执仍使用原来的严格配置比较。
2. 单 Space 同步必须等待预检成功才导出；显式 Site/addSpaces 上传要求全部选定 Space 预检成功。后台扫描保留逐 Space 的处理方式，失败空间不阻止继续检查其他空间。并发等待同一个预检任务的不同 Space 对象会获得相同失败原因。
3. 预检请求失败保留网络错误和重试能力；兼容比较后仍存在真实差异时才标记需要配置核对。新增的错误分类复用现有中英文文案，区分配置暂不可用、需要核对和拓扑无效；通用导出失败不再默认显示邻近照明无效。
4. 对已有 `upgradeBaselineNeedsImport`，在正常 Space 预检时尝试范围受限的恢复：要求可编辑权限、版本已同步、没有本地待上传修改、待导入/引用清理/删除记录/提交/本地恢复意图。重新获取云端、验证同一 Space 和云端版本，确认完整可读且无需清理的配置等价后，才清除此原因并持久化迁移状态。
5. 自动恢复额外比较 Network/App Key 身份、Group 设置、场景、日程、开关和应急配置。云端请求前后重新导出本地并比较完整快照，防止同秒修改在等待期间被忽略；权限、账号、取消、保存失败都会保留恢复条件或原有保护。
6. 自动恢复条件采用保守限制：哪怕配置看似等价，只要本机仍标记待上传或存在未完成操作，也不会自动清除阻塞，而是保留现有人工核对入口。它不承诺覆盖所有客户历史状态。

没有新增 SDK API、依赖、target 配置或本地化资源；复用了 `configuration_sync_unavailable`、`configuration_review_message` 等已有 Key。共享逻辑没有品牌分支，构建选择代表 scheme SunSmart。

### 自动化验证

- 新增旧格式重试用例在修复前按预期失败：`known legacy defaults must not create a permanent upgrade block`；修复后通过。
- `check_space_recovery_receipts.py`：升级重试、已有阻塞恢复、Owner/Editor、真实配置与 Key 差异、待处理操作、两次本地读取、持久化失败、取消、错误码往返及既有回执/权限/删除保护用例通过。
- `SpaceConfigurationIntegrityPolicyTests.swift`：旧格式兼容与正式回读隔离、无效 schema、缺字段、非空 Zone、既有 Profile/回读差异诊断通过。
- `check_site_zone_cleanup_batch.py`：实际生产单 Space/批量上传入口在预检失败时不导出，可重试；并发等待者错误一致；现有 SQLite、批量所有权、取消与跨 Site 隔离通过。
- `check_space_sync_readback_reuse.py`：存储读回、同时间戳旧对象、损坏 Zone 与原有恢复保护通过。
- `check_space_sync_cleanup.py --snapshot <客户样本>`、`check_proximity_scoped_import.py --snapshot <客户样本>`：服务器样本保持有效，9 台设备、不产生邻近照明清理或变更；既有清理及导入回归通过。
- 修补了上述既有测试装配缺少的 `SiteGatewayLastOnlineSnapshot` 生产依赖，以及批量夹具遗漏的 Membership 边界替身。未借此修改 App 的 Membership 行为。

这些是生产策略和受控网络/存储边界的隔离验证，不能代替真实手机升级、服务器往返或 BLE/Mesh 验收。

### 构建与人工验收

SunSmart Debug generic iOS 无签名构建通过，输出 `BUILD SUCCEEDED`。使用 `SunSmartLocal.xcworkspace`、`SunSmart-fix-gateway-cli` DerivedData，SDK 为前述 `one-dev`，保留其其他任务的未提交改动。未构建其他品牌或 Release；本次没有品牌编译分支、依赖、资源归属或 Debug/Release 行为差异变更。`git diff --check` 通过。

尚未进行真机或客户 TestFlight 验收。发布含此修复的测试版本后，最短人工检查为：

1. 使用旧版本创建的 Space 升级；一次云端预检失败后恢复网络并重试，预期能够继续迁移和同步，不误报邻近照明数据无效。
2. 已有旧升级阻塞、云端与本机相同且没有未同步操作的 Space，重新进入或触发同步后应恢复；存在真实本地/云端差异时仍应要求核对。
3. 核对 OFFICE 的 9 台设备、两条路径和两个组内触发区域保持原配置。需要设备下发的实际任务仍按原同步流程执行，自动化结果不代表灯具已验收。
