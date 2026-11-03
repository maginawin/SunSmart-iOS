# Space 恢复被 Timed 数据阻断：原因与修复方案

日期：2026-11-03。分支：`feat/device-scene-261028`；分析基线：`b1bab004`。用户确认后已完成下述 App 修复与自动化验证，尚未提交；未修改用户原始数据、服务器或 SDK。实施结果见文末。

## 结论

进入“日出日落”Space 的直接失败原因是 App 的 Timed payload 校验不兼容服务器返回的非 Scene 定时空场景字段：两条 `selectTarget=3` 的 Profile 定时均携带 `sceneAddress: ""`，`TimedSchedulerPayloadPolicy.canonical` 将其拒绝，日志对应 `invalidTimedPayload`。

还存在一个必须一起修复的后续阻塞：服务器 `profiles` 对象有 `groupAddress/profileSceneNumber/groupName/type`，App 的 `ScheduleProfile` 编解码只保留前两个字段，而 canonical 比较整个对象。仅放过空字符串后，存储回读比较仍不相等，按当前导入代码将导致事务失败。

恢复成功后的 Profile 定时处理也有必要保护的风险：当前 App 保留了该类型的数据模型，却没有完整实现其编辑、目标解析和同步；不能仅让导入通过后就宣称两条任务可正常执行。

## 现场证据

输入文件：

- `/Users/maginawin/Downloads/Space_日出日落_20261103_113215_690+0800.json`
- `/Users/maginawin/Desktop/server space data.txt`
- `/Users/maginawin/Desktop/enter site and then enter space.txt`

Space ID：`2AA401ED-DF18-4893-AE38-7580D16EFA41`。

| 项目 | App 导出 | 服务器 get spaceprops |
| --- | --- | --- |
| 最后更新时间（UTC+8） | 2026-11-03 10:50:42 | 2026-11-03 11:25:50 |
| 设备 / Group / Scene 数量 | 14 / 1 / 0 | 14 / 1 / 0 |
| 定时数量 | 0，原始本地 schedules 表也为 0 | 2 |
| timedSchemaVersion | 1 | 1 |
| 网络身份与设备身份 | Space、NetKey/AppKey 内容、设备 UUID/地址集合与 Device Key 均与服务器一致 | 相同，本文不记录密钥 |

两条服务器定时如下，均为启用、每天、渐变 2 秒、`action=2`、`selectTarget=3`：

| id | 名称 | 时间 | sceneAddress | profiles |
| --- | --- | --- | --- | --- |
| 1 | 占用感应 | 14:28 | 空字符串 | C000 / FF00 / 组 1 / type=3 |
| 0 | 节点1 | 16:10 | 空字符串 | C000 / FF00 / 组 1 / type=3 |

`selectTarget=3` 在当前 App 定义中为 Profile；它不等于普通 Scene 目标。不能因为 Space 的普通 Scene 列表为空就删除这两条任务或把 FF00 当成缺失的普通 Scene。

日志中的顺序：

1. `get/siteprops` 返回 HTTP 200，导入该 Space 时打印 `result=rejected reason=invalidTimedPayload`。
2. 用户点击 Space，`get/spaceprops` 返回 HTTP 200。
3. 再次打印同一拒绝原因，随后进入 `SpaceRecoveryViewController`。

两次失败均在 `metadataPrepared` 之前，与 Timed 前置校验的位置吻合。日志中的 Auto Layout 约束警告不是这条导入拒绝链的触发条件。

本地诊断状态为 `configurationInitialized=true`、membership `joined`、recovery `active/writable`，`pendingImport/pendingUpload/pendingDeletionCleanup` 均为 false。说明提示文案本身不能证明存在尚未完成的后台恢复事务；本次进入页面直接由导入拒绝触发。

诊断导出明确标记 `purpose=localConfigurationInspection`、`uploadable=false`。`hasCompleteExportSnapshot=false` 仅表示当前恢复目录没有 `last-complete-export.json`，不能据此推断设备数据丢失或所有保留副本都不可用。该本地样本比服务器旧且没有两条定时，不应拿它覆盖服务器来解锁页面。

## 两个连续失败点

### 1. 空字符串被当作非法 Scene 编号

`ImportData.swift` 的 `SpaceData.update` 在业务数据写入之前调用 Timed 修复、schema、canonical 和 Schedule 解码检查；任一失败都返回 `invalidTimedPayload`。

`TimedSchedulerSlotPolicy.swift` 的 canonical 对所有 target 一律检查非 null 的 `sceneAddress`：必须能解析为大于 0 的 UInt16。空字符串解析失败，即使该记录的实际目标是 Profile。

但 `Scheduler.swift` 的生产 Schedule decoder 会将该空字符串解码为 `sceneNumber=nil`，不会拒绝这两条记录。因此这是 App 内部兼容规则不一致，不能简单归结为 JSON 无法解析或服务器未响应。

### 2. Profile 编解码和回读比较不一致

生产 `ScheduleProfile.CodingKeys` 只有 `groupAddress`、`profileSceneNumber`；其余两个样本字段在解码和重新编码后消失。数据库 `profiles` 列存储的也正是该 Codable JSON。

canonical 却直接保留并比较 `profiles` 原始对象。导入事务写入后，`ImportData.swift` 重新读取 Schedule、编码，并要求 `canonical(timedReadback) == remoteTimedConfiguration`。因此仅修复空字符串会暴露第二处错误，触发 `configurationPersistenceFailed`，事务回滚并保留恢复屏障。

本轮没有运行完整导入事务；上述事务后果由生产调用链推导。字段差异已经用生产策略及生产编解码方法的隔离执行确认。

### 隔离复现结果

直接读取用户服务器文件，编译执行未修改的 `TimedSchedulerPayloadPolicy`，并复用生产 Schedule / ScheduleProfile 编解码方法；UInt16 地址辅助属性和模型外围使用轻量替身。没有操作 SQLite、BLE、服务器或用户文件。

| 实验 | 结果 |
| --- | --- |
| 原服务器样本 canonical | 失败 |
| 原服务器 schedules 通过生产 decoder | 成功，2 条、target 均为 3、scene 均为 nil、各 1 个 Profile |
| 仅在内存将两个空 sceneAddress 改为 null | canonical 成功 |
| 上述输入与生产 Codable 再编码后的 canonical 比较 | 不相等，两条记录均只差 profiles |
| 再在内存将 profiles 投影为 App 当前保留的两个字段 | 与 Codable 回读相等 |

最后一项只用于锁定差异，**不表示建议丢弃服务器的 groupName/type**。现有材料不足以断言 type 仅是无意义元数据，修复应优先无损保留。

## Retry 与 Saved Space Copies 为何无效

- Retry：`SiteViewController.showSpaceRecovery` 再次调用 `loadSpaceReqeust`，GET 后走同一 `restoreConfiguration → update` 校验。服务器数据不变时，必然再次遭到相同拒绝。当前提供的日志只包含初次进入；Retry 的解释来自代码路径，不冒充实际 Retry 日志。
- Saved Space Copies：当前列表点击仅打开 `UIActivityViewController` 分享文件，没有选择副本恢复、重新鉴权或执行导入的调用。它是副本导出入口，不是可直接完成恢复的按钮。
- 普通文件导入接受 Space payload 或 Timed v2 envelope；诊断导出和保留副本还有各自外层包装，不能把这些文件等同于可直接导入的完整备份。此次未收到 Saved Space Copies 内部文件，无法评价具体副本内容。
- `SpaceRecoveryViewController.message` 没有映射 `invalidTimedPayload`，落入笼统的 “This Space has not finished restoring” 文案，掩盖了“当前定时配置无法导入”的实际失败类型。

## 必须考虑的恢复后风险

现有 `.profile` 分支在 `ScheduleAddViewController.setupData` 和 `Schedule.SyncDataRead` 中均没有实现完整处理；`Schedule.targets(node:)` 也不使用 `profiles`。

对本次只有 profiles、没有普通设备/组/Scene 目标的记录：

- 编辑入口不能正确还原 Profile 目标，保存有改变原目标的风险。
- 同步目标集合为空；设备落入 orphan 检查。对于 legacy id=slot 的记录，如果后续读到对应槽位有有效条目且 Model 状态已齐备，`needsDelete` 可将其作为非目标残留列入删除任务。
- `TimedSchedulerBindings.prepare` 同样依赖 `targets`，在槽位迁移或 Group 拓扑变化时可能把绑定标为 pendingRemoval。

这是代码推导的条件性风险，不是这份日志已经发生的设备删除。本次样本节点的 legacy schedules 数组为空，不能据此推定真实设备没有定时，也不能推定设备已被误删。

## 建议实施方案

### A. 修复兼容与持久化一致性

1. 在共享 `TimedSchedulerPayloadPolicy` 中明确处理已知 legacy 表达：schema 1 且 target 为非 Scene 时，`sceneAddress: ""` 在 canonical 中等价于 null。保留实际正整数/十六进制 Scene 值；不将任意非法字符串、越界值或错误类型转成空值，不扩大普通 Scene 目标的容错范围。
2. 复用现有 Schedule decoder 的空值行为。确保原始 GET、首次导入、pending-import 重试、SQLite 回读、export 和上传回执比较使用一致表示。空值表示兼容本身不应伪装成目标删除，也不应无条件增加云端覆盖上传。
3. 最小扩展现有 `ScheduleProfile`，以可选字段保留样本中的 `groupName/type`，编码时缺失仍缺失；现有只含两个地址字段的旧记录继续可读。复用已有 profiles JSON 列，不建立第二套持久化模型；复制、保存、重新导出不得丢失这些字段。
4. canonical 与实际持久化模型的字段和规范化规则一致；真实目标、时间、开关、动作变化仍必须产生差异。对未来未知字段不以本次兼容为理由整体关闭完整性检查。
5. 沿原导入事务完成两条定时的保存和回读校验，再解除恢复屏障。不得吞掉错误、替换成空 schedules、强制初始化完成或只改时间戳。

共享影响包括 Site/Space 导入、恢复重试、备份导入导出、云端确认和旧基线比较。修改共享规则能覆盖这些入口；仅在恢复页面预处理数据会留下其他入口重复失败。

### B. 保护暂未完整支持的 Profile 定时

建议本次先以“可进入 Space、无损保留 Profile 定时、不误修改设备”为边界，而非顺带实现新的定时能力。

1. 明确显示 Profile 目标及暂不支持的编辑能力，避免其被编辑成空 Group/Scene；防护覆盖编辑、启停、删除等会改变任务的入口。
2. 在实际任务生成和槽位规划边界保护未支持类型，不因无法解析目标而生成 orphan 删除或迁移为 pendingRemoval。对可能占用的旧槽位保守保留，不能只跳过记录后将槽位重新分配。
3. 对无法安全判断的关联拓扑操作给出明确限制，避免新保护阻断导入、纯读取以及不相关的普通定时操作。后续实施需用已观察到有效槽位和未知槽位两个夹具核对。
4. 完整 Profile 定时编辑、目标展开和设备执行作为独立功能；需先确认 Profile 场景编号、每个 Group 的执行目标与固件/网关支持契约。本次不推定 FF00 的全部执行语义。

### C. 让恢复页面准确反馈失败

1. 给 `invalidTimedPayload` 提供专用中英文提示，说明定时配置导入失败，避免将确定性数据拒绝表述为等待后台恢复。
2. DEBUG 日志细分 schema、canonical、decoder、readback 阶段，输出 schedule id 和字段路径；不输出完整 payload 或密钥。
3. Saved Space Copies 文案说明当前动作是查看/导出；本次不新增整套“副本恢复覆盖云端”流程。该功能需要独立设计当前权限验证、完整性检查和冲突选择。

### 范围及外部配套

- 必要改动均在 App；目前没有证据要求修改 Nordic SDK、固件或服务器。
- 不修改服务器样本来规避 App 缺陷，不删除两条定时，不重建 Space，不覆盖旧本地数据到云端。
- 如果服务端未来统一输出 null，应作为接口约定由服务端团队处理；App 仍需兼容已经存在的这类数据。本次修复不依赖服务端先发布。
- 共享实现影响五个品牌。开发验证选 SunSmart；涉及新增本地化时核对所有品牌资源归属，存在不同资源或编译路径风险时再覆盖对应品牌构建。

## 验证与交付边界

实施后优先扩展现有测试，不另建临时 Xcode 工程：

1. `TimedPayloadTests`：以脱敏的两条 Profile 定时复现；覆盖空字符串/null/缺字段、非法非空 Scene 值、旧两字段 Profile、新四字段 Profile，以及 v1/v2 原有槽位约束。
2. 生产 Codable + Schedule SQLite 保存/重读：四字段无损、两条任务数量不变、canonical 一致；不得以全空 schedules 获得通过。
3. `check_space_recovery_receipts.py` 对应导入/回执夹具：初次进入、Retry、退出重进、导入中断后恢复、失败不破坏原配置；原始服务器表达与 App 再导出表达可比较，真实业务变化仍不等价。
4. 复用 `check_timed_slot_persistence.py`、`check_timed_device_slots.py`、`check_schedule_scene_target_export.py` 及关联任务测试：Profile 记录不被误编辑、自动清理或错误释放槽位；普通 Group/Device/Scene 定时行为保持正确。
5. 一轮 Swift 修改完成后运行一次 SunSmart generic iOS Debug 构建。构建前核对实际 workspace、scheme、SDK realpath；不使用 Simulator、不自动安装真机。
6. 人工最短验收：更新 App → 进入 Site/Space 或点 Retry → 正常进入且保留 14 台设备、1 个 Group、2 条 Profile 定时 → 退出重进仍保留；检查受限制的编辑/同步入口不会改变原任务。真实设备槽位和真实云端再读取分别验收，不能由离线测试代替。

分析阶段已完成原始文件对照、生产调用链分析和两处 Timed 不一致的隔离复现。以下为随后获得实施授权后的结果。

## 实施与验证结果

### 已实施

- canonical 接受 schema 1 非 Scene 目标的空字符串，等价于 null；普通 Scene 和原生 v2 的非法空字符串仍拒绝。既有旧写入方 id≥16 自动升 v2 路径在升级前处理该 sentinel，避免兼容被升级动作自身破坏。
- `ScheduleProfile` 无损保留可选 `groupName/type`，使用原有 JSON 数据库列；canonical 将这两个字段的 null 与缺失视为等价，保留有意义的值差异和未知字段检查。
- Profile 定时以只读方式保留。列表显示 Profile 目标；编辑、启停、删除的 UI 和服务入口均拦截；目标/删除判断、发送预留及迟到回调也受保护。
- legacy Profile 在现有 Scheduler 节点保守保留 id 对应槽位；v2 保留已存在 binding 的状态、槽位和 generation。不会因“不支持目标”而标记删除或释放槽位。无绑定的 v2 Profile 不猜测槽位；普通任务仍须完整读取设备后才可分配未占用槽。
- `profiles.groupAddress` 命中的 Group 不允许成员变更或删除；跨组加入同时检查源 Group。无关 Group 退出不再尝试删除 Profile 槽，仍可操作。未将全局数据库保存/导入/设备身份清理封锁。
- 恢复页增加 Timed 专用失败提示；Saved Space Copies 说明仅查看/导出。DEBUG 诊断输出校验阶段、记录 id/字段路径或回读 id，不输出 payload、密钥和 decoder 的原始错误描述。

### 自动化证据

| 检查 | 结果与范围 |
| --- | --- |
| `scripts/check_timed_device_slots.py` | 通过；含 legacy 空地址、升 v2、非法输入、槽位保留与普通任务分配 |
| `scripts/check_schedule_scene_target_export.py` + 用户 server 文件 | 通过；两条真实样本经生产 Codable 再编码后 canonical 相等；另含可选字段 null/缺失与实际变化 |
| `scripts/check_timed_slot_persistence.py` | 通过；生产 Schedule SQLite 保存、重新打开、两条 Profile 数据无损、回读一致；启停拒绝、关联/无关 Group、保留槽位与迟到回调 |
| `scripts/check_space_recovery_receipts.py` | 通过；新增 owner/editor/visitor 初次与中断重试准备、持久回执、离线失败后 legacy 空字符串/null 等价确认；原有恢复回归仍通过 |
| 中英文本地化 plist 检查、`git diff --check` | 通过 |
| SunSmart generic iOS Debug | 通过；命令退出码 0，Xcode 构建记录 0 errors / 0 test failures，保留现有 122 warnings；没有安装或启动 App |

构建使用 `SunSmartLocal.xcworkspace`、`SunSmart` scheme、`CODE_SIGNING_ALLOWED=NO`，DerivedData 为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-checks`。SDK realpath 为约定的 `nordic-sig-mesh-sdk-worktrees/one-dev`，revision `dbcf6f1`，SDK 工作树干净且本次未写入。正式依赖声明未变；没有新增 SDK API 发布依赖。

已核对五个品牌均引用同一 `Localizable.strings` 资源组，没有新增资源文件或 target 配置。此次共享逻辑无品牌条件分支，代表构建为 SunSmart；未重复五品牌构建。

### 待人工验收与已知边界

恢复回执测试执行生产导入准备/回执代码，Mesh 和完整 App 存储边界有替身；Schedule SQLite 测试与完整 App 跨存储事务分开验证。因此自动化通过不等于已经完成完整 App 恢复、真实云端 round trip 或设备验收。

最短验收：运行新构建 → 进入 Site/Space 或 Retry → 确认能进入，仍有 14 台设备、1 个 Group、2 条 Profile 定时 → 退出重进确认保留。Profile 定时本次应显示只读，启停/编辑/删除提示限制；关联 Group 成员变更/删除受限，无关 Group 和普通定时保持可用。实际设备任务未被误清理、最终显示布局和真实云端再读取由人工确认。

完整 Profile 定时执行与编辑仍未实现；本次恢复修复不宣称 FF00 已完成设备执行验证。原有其他任务文档未修改，未执行 commit/push。
