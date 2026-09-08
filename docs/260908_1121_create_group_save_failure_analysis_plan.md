# Create Group 出现 Save Failure 的原因与修复计划

日期：2026-09-08。工作树：`trigger-zone-sep`。分析结束时 HEAD：`0db56b87`。

本轮范围：分析用户日志、核对当前源码、运行临时复现并规划修复。没有修改业务代码、SDK、依赖、数据库或设备配置，也没有提交代码。

## 1. 结论

当前实现存在可确定复现的数值单位校验错误：新建 Group 默认选择类型 1（Occupancy + Daylight），默认 `occupancyLevel` 是 500 lux；数据库 `Profile.loadAll` 却把该字段与百分比亮度一起限定在 0～100。Profile 写入后回读被拒绝，GroupInfo 保存事务回滚，创建页面捕获失败并显示 `save_failure`。

用户日志中的页面进入后直接点击 Done、随后出现 `[ConfigurationPersistence] persistenceFailed`，与此默认路径一致。日志没有输出新 Group 的 Profile 类型、字段和具体失败阶段，因此不能仅凭这一行排除所有其他持久化故障；但当前源码的默认创建路径必然触发上述缺陷，已通过抽取生产代码的临时探针证实。

相同错误还存在于云端数据的 App 侧完整性校验。如果只修改数据库读回，新 Group 可能保存成功，却继续在导入或导出时被拦截。应同时修复两个共享入口。

## 2. 失败调用链与源码证据

| 阶段 | 行为 | 源码位置 |
| --- | --- | --- |
| 默认选择 | 创建页使用 `profiles.first` | `SunSmart/Main/Group/Controller/GroupAddViewController.swift:86` |
| 默认类型 | `defaultGroupProfileTypes` 首项为 `.occupancy_daylight`，rawValue 为 1 | `SunSmart/Main/Profile/Model/Profile.swift:553` |
| 默认配置 | 类型 1、2、5 的 General Scene 设置 `occupancyLevel = 500`、`vacantLevel = 100` | `SunSmart/Main/Profile/Model/Profile.swift:423` |
| 数据复制 | 创建回调进入 `finnished`，`applyGroupInfoEdits` 复制所选 Profile 数据并保存 GroupInfo | `SunSmart/Main/Group/Controller/GroupAddViewController.swift:214`、`:250`、`:278` |
| 原子保存 | 事务内先保存 Profile，再写 GroupInfo，然后按同一身份回读 Profile 并比较类型 | `SunSmart/Common/Data/Database.swift:1058` |
| 错误校验 | `Profile.loadAll` 把 high/low trim、occupancy、vacant、standby、task 全部限制为 0～100；不合格就直接跳过该记录 | `SunSmart/Common/Data/Database.swift:1648` |
| 报错回滚 | 回读为 nil，抛出 `persistenceFailed`；savepoint 回滚并输出日志 | `SunSmart/Common/Data/Database.swift:1063`、`:63` |
| 页面反馈 | `finnished` 捕获失败，显示 `save_failure`；外层尝试移除刚创建的 Mesh Group 并检查清理结果 | `SunSmart/Main/Group/Controller/GroupAddViewController.swift:218`、`:259` |

这里并非必须发生 SQLite INSERT 错误：SQL 写入成功后，被 App 自己的回读规则拒绝，同样会返回保存失败。不能通过取消回读校验或强行返回成功来修复。

字段具有类型相关的单位。`Node+SyncData.swift:1317` 起按 daylightType 分别生成 lux 或百分比任务，`Node+MessageHandles.swift:546` 起把 lux 编码成 illuminance；UI 在 `ProfileLevelSettingsView.swift:591` 起也区分 `%` 与 `lx`。`ProfileType.daylightType` 仅包括 1、2、5；类型 8 虽有 Photocell 条件，并不属于该集合，其场景亮度不能直接按 lux 放宽。

## 3. 其他日志如何解释

### missing profile

`GroupInfo.load` 在 `Profile.load` 返回 nil 时统一输出 `missing profile`（`Database.swift:958`）。nil 既可能来自记录不存在、身份不匹配、查询失败，也可能来自字段或场景解码被拒绝。因此这批日志不等于大量 Profile 已经物理丢失。

本缺陷足以让原本存在的日光 Profile 被误报缺失。用户未提供设备数据库，无法确定每条启动日志的具体原因；重复输出也不能直接推断重复写入或重复删除。新 Group 失败后没有再次打印 `missing profile` 是正常的：事务直接调用 `Profile.load`，该数值分支静默跳过记录，随后只输出通用 `persistenceFailed`。

### HTTP、权限、时间戳及系统提示

- siteInfo、spaceInfo 等请求均返回 HTTP 200 / 业务 200；点击创建 Done 后没有出现对应上传请求，现有证据指向本地保存阶段。
- `serverUpdateTimestampNotNewer` 是云数据未覆盖本地的时间戳分支，不能解释新 Group 默认 Profile 回读失败，也不能证明旧本地 Profile 完整有效。
- `editProtected=true` 与其他 editor 信息并不足以说明此次创建被锁定；日志显示 owner 心跳，而且失败实际进入本地持久化回调。
- AppleLanguages、空 App Group container、网络 endpoint、XPC、RenderBox、EFC proxy pending：目前没有证据把这些提示接到此次 `save_failure` 调用链上，暂不纳入本次修复。
- 请求头声明 gzip 而实际 body 非 gzip 是独立的请求一致性问题；本次这些请求成功，且本地创建失败前没有新请求，不能把它作为本次直接原因。

## 4. 影响范围及现有测试缺口

数据库读取与保存后回读共享这一错误，影响新建、编辑保存、旧数据重载及依赖配置可用性的操作。

`SpaceConfigurationIntegrityPolicy.profileIssue` 同样对顶层 occupancy/vacant/task 使用 0～100。`ImportData.swift:1635` 用它拒绝远端配置并设置保护状态；`ExportData.swift:920` 用它拒绝生成导出结果。这是 App 侧校验缺陷，当前无需据此要求修改服务端。

临时探针输出：

| Profile 类型 | 默认 occupancyLevel | 当前本地 level 校验 | 当前云端 profileIssue |
| --- | ---: | --- | --- |
| 1 Occupancy + Daylight | 500 | 拒绝 | invalidProfileField:occupancyLevel |
| 2 Vacancy + Daylight | 500 | 拒绝 | invalidProfileField:occupancyLevel |
| 3 Occupancy | 100 | 通过 | 无错误 |
| 4 Vacancy | 100 | 通过 | 无错误 |
| 5 Daylight | 500 | 拒绝 | invalidProfileField:occupancyLevel |
| 6 Manual Control | 100 | 通过 | 无错误 |
| 7 Proximity Lighting | 100 | 通过 | 无错误 |
| 8 Proximity Lighting with Photocell | 100 | 通过 | 无错误（合成完整条件夹具） |

“通过”仅指探针中的字段检查，不代表各类型完整 UI 或数据库链路均已验证。

既有 `SpaceConfigurationIntegrityPolicyTests` 本轮运行通过。但其中类型切换测试复用 occupancyLevel=100 的字典，只替换 type，没有使用真实默认 500 lux。`ConfigurationDatabaseCheckpointTests` 的 Profile 兼容性测试只建简化表并检查历史列和 type，也没有执行真实 Profile 字段回读，因此不能覆盖本问题。

## 5. 建议修复步骤

### A. 在共享校验处修复单位语义

1. 建立小范围、可独立测试的 Profile 字段校验策略，由数据库读取/保存验证与云端完整性检查复用，避免再次出现两套边界。
2. highEndTrim、lowEndTrim 保留百分比约束；类型 1、2、5 的 occupancy/vacant/standby/task 按现有日光字段语义允许 lux。类型 3、4、6、7、8 仍按百分比约束；类型 8 的 day/night 场景和引用完整性保护继续保留。
3. lux 存储边界按实际 App/SDK 支持能力定义。当前本地开发 SDK 的 lux 缓存为 UInt16，可采用 0～65535 作为候选边界；落地前应核对工程实际 resolved SDK 的编码、解码与历史数据约定。UI 的 0～1500 默认输入范围不直接作为历史持久化上限。保留校准模式下已有数值含义，不重新换算已有数据。
4. 保持默认 500 lux，不将它截断为 100，不更换默认 Profile 来绕开问题，不无条件放宽所有字段。
5. 顶层和 scenes 内的数据采用一致的类型规则；旧字段缺省兼容策略按现有约定保留。负数、超界、非整数、类型错误、必填字段缺失继续拒绝。

预计核心改动：`Database.swift`、`SpaceConfigurationIntegrityPolicy.swift`，必要时增加共用的纯校验文件。创建页无需通过业务特判绕开保存失败。

### B. 保留保存事务，并改善错误定位

1. 保留 Profile + GroupInfo 的 savepoint、回读以及失败时 Mesh Group 清理。
2. 在保存前应用同一字段规则，回读仍验证可恢复性；让失败结果带有阶段，例如 profileWrite、profileReadback、groupInfoWrite。
3. 将 `missing profile` 区分为 rowMissing、invalidField、decodeFailed、queryFailed 等可定位原因，输出 profileType、字段名及必要数值；不输出完整 Profile、密钥或鉴权信息。
4. 复用现有国际化 `save_failure`。若确需新增用户可见说明，同步检查各品牌英文/简体中文资源；本次优先保持页面布局与文案不变。

### C. 兼容已有数据与保护状态

1. 先修读取策略并重载原记录。对于仅因 500 lux 被误判的数据，应保留原 Profile ID、参数、scenes、Group 关联与拓扑，不重新生成默认 Profile，不清空数据库。
2. 同时间戳云端数据跳过导入时，也应验证旧本地记录能由修正后的读取恢复，而不是通过无条件覆盖本地实现恢复。
3. 对已持久化的 invalidRemoteProfile 等保护状态，先检查具体原因，并通过现有恢复/校验流程处理；不能全局清空 blocked 状态。若原始记录确实缺失或损坏，继续保留保护并走现有恢复流程。
4. 失败创建的 Mesh Group、GroupInfo、Profile 不留半成品；清理失败仍保留现有阻断机制。记录本次失败是否残留，不能仅从用户日志宣称已清理成功。

### D. 回归与验收

- 八种真实默认 Profile：创建、保存、重载、Profile ID 与参数一致；重点包含 1/2/5 的 500 lux。
- lux 边界：100、101、500、1500、支持上限及上限+1；百分比边界 0、100、101；负数、非法类型、损坏 scenes。
- 真正执行 GroupInfo.save → Profile.save → Profile.load 的 SQLite 回归，覆盖新数据库、旧表兼容列、旧记录重载和回读失败回滚，不能只检查简化表 type。
- Group 从 7/8 切换到完整日光 Profile，验证合法照度、scenes、既有 Proximity 拓扑生命周期和通用设备同步。
- 导出→导入→重载→再导出的字段一致性，保留历史缺省字段兼容；验证合法日光配置不再触发 invalidRemoteProfile。
- 注入写入/回读失败：创建页不报告成功、不上传半成品、不留下残余 Group；清理失败仍阻断。
- 既有完整性、数据库安全、Proximity 生命周期、autoMinLevel 等相关回归保持通过。
- 对 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个共享品牌直接执行 generic iPhoneOS 的 xcodebuild 校验；不用 Simulator，不使用 shell 包装或日志重定向。无需为本缺陷修改 SDK 或依赖。
- 真机验收完整路径：进入 Space → Groups → Add → 保持默认 Profile → Done → 添加成员；重启重入，确认参数仍在。再验证编辑、云端同步与另一端读取；构建成功不能替代这些验收。

## 6. 本轮验证记录与边界

- 已阅读当前创建、GroupInfo/Profile 持久化、字段模型、云端导入导出、同步消息与相关测试源码。
- 临时探针：`/tmp/group_save_failure_analysis_260908/main.swift`；二进制：同目录 `probe`。
- 探针抽取生产 generalScene 方法、LightControlData 初始化方法、本地 level 检查表达式，并编译完整生产 SpaceConfigurationIntegrityPolicy；外壳类型为最小替身，类型 8 条件数据为合成夹具。它确认规则冲突，不冒充完整 Profile.load/SQLite/UI 测试。
- 现有完整性测试二进制：`/tmp/group_save_failure_analysis_260908/integrity_tests`，本轮运行通过；同时确认该测试漏掉真实默认照度。
- 未读取用户真机数据库，未调用业务服务器，未运行 App 构建或真机 UI。日志中的每条历史 missing profile 原因、该次创建清理结果仍需后续验证。
- 本轮只新增本文档。等待用户确认修复范围后实施。
