# 3楼 Space 同步失败：原因与修复方案

建立日期：2026-09-22；最近更新：2026-09-23。当前状态：旧表兼容保存、重复模板清理、唯一索引迁移及失败重试事务修复已实施，相关回归与 SunSmart generic iPhoneOS Debug 编译通过；手机上的云同步与重启验收待用户执行。下文保留首次分析与实施证据，本轮交付见末尾。

## 结论

本次失败有两层已确认原因：首次清理保存了错误的表；修正调用后，旧安装的模板表又因缺少 `UNIQUE(id)`，将替换写入变成追加。09-23 现场导出确认同一模板已累积 13 行，旧的 14 地址行持续触发清理，因此出现 `cleanupExtensionRemaining`。本轮已补完整持久化链，按当前有效地址规范化后将等价重复行事务内合并为一条，保留 3 个地址。

同时，故障注入证实原配置事务失败后没有释放 SQLite 保存点，导致同连接上的后续成功重试可能尚未真正提交。本轮在 App 事务入口修复此问题，未修改 SDK、云端协议或解除完整性保护。以上结论来自现场数据、源码与真实 SQLite 回归；实际手机的上传及服务端确认仍需验收。

## 环境与输入

- 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix`。
- 分支/HEAD：`fix` / `891dca4d`，分析开始时无未提交改动。
- 本地入口：`SunSmartLocal.xcworkspace`，SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `ebbe1c9`，无未提交差异。本任务未修改 SDK。
- 用户日志：`/Users/maginawin/Desktop/tmp/lan/error log.txt`、`/Users/maginawin/Desktop/tmp/lan/enter floor 3 logs.txt`。
- 用户快照：`/Users/maginawin/Desktop/tmp/lan/Space_3楼_20260922_200727_775+0800.json`。
- 目标 Space：`39510799-323F-4E05-B2C4-7993742536C8`，名称“3楼”。运行 App 的构建 revision 未在日志中提供；源码分析对应上述 HEAD。

## 现场证据

### 日志

两份日志合计四次出现 `stage=cleanupPreparation error=-2004 reason=none`。相关 Site/Space GET 接口返回 HTTP 200，后续完成解码；日志中没有本次对应的 Space 上传请求。

进入 Space 时出现 `preserved pending local deletion/recovery`。这是 `ImportData.swift` 中 `preservesLocalChanges` 的分支日志，含义不限于“删除未完成”：待清理引用、待上传本地恢复、待确认提交等同样会保留本地数据。

`reason=none` 仅表示没有 `spaceConfigurationBlocked` 的原因字符串，不表示没有恢复文件，也不表示准备流程已成功。

### 快照

调试状态显示：`configurationInitialized=true`、`membershipPhase=joined`、`recoveryPhase=active`、`pendingImport=false`、`pendingDeletionCleanup=false`，`issues=[]`。原始 Space 行保存了 `syncCloudError=-2004`。

调试状态没有导出 `pending-reference-cleanup.json` 是否存在、authority、submission 等全部恢复状态。因此，不能只凭这些字段排除引用清理保护。`_debugInspection.uploadable=false` 是调试导出的固定标记，不能用来判断业务同步被拒绝的原因。

Space 有 7 个节点、5 个普通 Group、2 个开关虚拟 Group。生产 `SpaceSyncCleanupPolicy.normalize` 对 `spaces[0]` 的执行结果为：7 个设备、0 项修复、拓扑有效。这与日志中的 `ProximityLightingExport repairs=0` 一致。

真正异常保存在 `rawLocal.app.profileLightSensorTemplate`，并不体现在上述拓扑修复计数里：

| 项目 | 现场值 |
| --- | --- |
| 所属 Group | `C009`，组 4 |
| 所属 Profile | `6F0CAD96-2501-4924-B014-88403A73BF51`，type 3 |
| 模板名称 | `150，300` |
| 保存的设备地址数 | 14 |
| 按当前清理规则保留的地址 | `0711`、`0714`、`0720` |
| 已不存在的地址 | `0636`、`070E`、`0717`、`071A`、`071D`、`0723`、`0726`、`0729`、`072C`、`072F`、`0738` |

不能从这些残留引用追溯具体是哪一次历史删除或迁移产生；本次确认的是清理程序无法把合法的清理结果持久化。

## 失败调用链

1. `CloudSynchronizationManager.swift` 中 `.syncSpace`、`.syncSite` 等入口先调用 `SpaceSyncCleanupCoordinator.prepare/prepareBatch`，成功后才生成上传请求。
2. `SpaceSyncCleanupCoordinator.extensionChanges` 的模板分支（335–344 行）检测出上述 11 个失效地址，产生一项清理操作。
3. 操作将模板内存地址改为剩余 3 个，随后调用 `group.info.save(...)`。
4. `Database.swift` 中 `GroupInfo.save` 调用 `Profile.save` 并写 `groupInfos`；`Profile.save` 写 `profiles`，两者均不写 `profileLightSensorTemplate`。模板实际有单独的 `save(profileId:)`，但这里没有调用。
5. 外层事务可以成功，Space 本地更新时间也可能推进，但模板表仍保留 14 个地址。
6. `perform` 重新加载 Space、Mesh 和 GroupInfo，再次计算 `extensionChanges`；228 行要求 `remaining.isEmpty`，此时仍剩一项操作，因此返回失败。
7. `defer` 记录通用 `cleanupPreparation/-2004`；`finishSyncReferenceCleanup` 未执行，上传入口返回 nil。
8. `beginSyncReferenceCleanup` 已创建的待清理记录可继续触发 `preservesLocalChanges`。因此重新 GET 不会覆盖本地配置，而再次同步又重复上述清理，形成持续失败。

第 8 步是生产路径对现象的解释；现有调试导出未包含恢复目录，未直接读取到该手机上的 pending-reference-cleanup 文件。

## 定向复现与验证边界

复用了 `scripts/check_profile_persistence.py` 的抽取方式，在临时目录运行生产 Profile、GroupInfo、模板模型及其真实 SQLite 建表、保存、加载、事务代码，并逐字抽取生产模板清理循环。输入设备集合与模板地址来自现场 JSON；未输出密钥，未连接服务端或设备，未访问 App 的实际数据库。

| 情况 | 内存地址数 | 重新读库地址数 | 再计算剩余清理项 |
| --- | --- | --- | --- |
| 当前代码，第 1 次清理 | 3 | 14 | 1 |
| 当前代码，第 2 次清理 | 3 | 14 | 1 |
| 临时验证中调用现有模板保存接口 | 3 | 3 | 0 |

复现脚本暂存于 `/tmp/space-sync-analysis-260922/reproduce.py`，同目录 `Probe.swift` 为定向测试。临时文件不作为长期回归依赖。

这是生产清理循环与真实持久化的隔离证据，未运行完整 App 协调器、HTTP 提交/确认流程或真机 UI。初次直接使用现有 `check_space_sync_cleanup.py --snapshot` 时，脚本不识别此次调试 JSON 的 `spaces` 外层，触发断言；后续定向测试明确读取 `spaces[0]` 并通过生产策略校验，不能将首次包装格式错误解读为现场 Profile 损坏。

现有测试的覆盖缺口也与本问题一致：Profile 持久化夹具把模板服务替换为空实现，清理读回夹具把 `extensionChanges` 替换为空数组，因而没有验证模板真实写库后的收敛。

## 建议修复范围

1. **修正模板清理的保存入口。** 在该分支使用现有 `template.save(profileId:)`，绑定当前所属 Profile ID，保存失败继续抛出 `persistenceFailed`。保持外围配置事务；不要扩展 `GroupInfo.save` 为隐式保存全部模板，以免影响其他编辑与导入路径。
2. **保留读回和恢复保护。** 仍要求从数据库重新加载后清理项为空，才结束引用清理。由正常上传及确认流程完成恢复标记清除；不直接清除 blocked/pending 文件、不伪造上传成功时间、不用旧云端配置覆盖现场。
3. **补充该失败点的 DEBUG 诊断。** 将“扩展数据读回失败”和“读回仍有清理项”区分为具体阶段，记录剩余项数量；保持现有错误码即可，无需新增用户文案或打印模板内容、密钥。
4. **补行为回归。** 复用现有持久化测试基础，把模板模型与数据库操作接入真实 SQLite；使用脱敏夹具验证下述路径，不提交用户原始 JSON。

回归应覆盖：

- 同时含有效与失效地址：真实清理并重新读库后仅保留有效地址，第二次无需再写。
- 全部有效：无需修改；全部失效：保留模板本身，地址数组变为空。
- 模板名称、阈值、ID、Profile 归属及其他模板不变。
- 模板写入失败：事务失败，不能完成清理或放行上传；失败恢复后重试可成功。

实施后运行模板/清理相关回归，再以现有本地 workspace 对 SunSmart 做一次 generic iPhoneOS Debug 编译。该改动属于品牌共享逻辑，无新增资源、编译条件或 SDK API，默认无需重复五品牌构建。

## 现场验收与下一步

修复版本保留现有 App 数据，进入同一 Site → 3楼 → 执行一次 Space 云同步。预期清理完成、上传及确认成功，重新进入或重启后不再重复该清理错误。再次调试导出时，目标模板地址应为 `0711`、`0714`、`0720`，7 个节点及现有组、场景、日程保留。

如果修复后仍失败，新 DEBUG 阶段用于区分其他准备条件与后续服务器失败；本轮未拿到完整云端 payload，也没有宣称云端内容与本地一致或 Mesh 设备配置同步已通过。

## 已实施与验证（2026-09-22）

用户确认后，已完成以下修改，尚未提交 Git：

- `SpaceSyncCleanupCoordinator.swift`：模板清理捕获所属 Profile ID，调用 `template.save(profileId:)`；保持原有事务、重新读库、恢复保护及上传确认路径。
- 扩展数据读回异常记录 `cleanupExtensionReadback`，读回仍有清理项记录 `cleanupExtensionRemaining`；额外 DEBUG 日志只记录剩余项数量，沿用现有错误码。
- 扩展 `check_profile_persistence.py` / `ProfilePersistenceTests.swift`：使用真实模板模型、SQLite 表、保存/加载和生产清理循环，以脱敏夹具覆盖混合有效/失效地址、全部有效、全部失效、模板元数据与所属 Profile/其他模板不变、二次清理无写入、事务回滚及失败后重试。
- 扩展 `check_space_sync_readback_reuse.py` / `SpaceSyncReadbackReuseTests.swift`：执行生产 `perform`，注入扩展写入失败、写入未持久化及读回失败，验证准备返回 false、恢复不能结束；成功重试后才完成。

新增真实 SQLite 回归在修复前明确失败于“14 → 3 未写入模板表”的断言，修复后通过。最终验证：

| 验证 | 结果 |
| --- | --- |
| `python3 scripts/check_profile_persistence.py /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev` | 通过，含真实模板清理/持久化回归及原 Profile 回归 |
| `python3 scripts/check_space_sync_readback_reuse.py` | 通过，含扩展清理失败、读回与重试保护 |
| `python3 scripts/check_space_sync_cleanup.py` | 通过，完整快照清理与旧格式兼容 |
| `git diff --check` | 通过 |
| `SunSmartLocal.xcworkspace` / SunSmart / Debug / generic iPhoneOS | `BUILD SUCCEEDED`，`CODE_SIGNING_ALLOWED=NO` |

构建使用稳定目录 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-cli`，实际解析到上述本地 SDK；没有运行 Simulator、安装/运行真机或访问服务端。真实 SQLite 证明模板存储收敛，协调器隔离测试证明失败不能完成恢复，构建证明当前 App 编译通过，均不替代上文现场上传确认和重启后的验收。

## 2026-09-23 续查：旧表缺少唯一约束，替换写入实际变为追加

### 新日志能确认什么

用户提供的修复后日志两次出现 `stage=extensionReadback remainingChanges=1`，随后为 `stage=cleanupExtensionRemaining error=-2004 reason=none`。这确认新失败诊断已进入运行版本，清理完成后的扩展数据检查仍不收敛；失败仍发生在上传准备阶段，HTTP 200 对应的是下载。

当前工作树为 `fix` / `e3856fc4`（已包含上次修改的提交），续查开始时干净。未拿到修复后的 Space JSON；现有文件仍是 2026-09-22 的旧快照。因此，新日志中的一项残留尚不能直接归属到具体模板或其他扩展记录。

### 已确认的第二处缺陷

Git 历史表明这不是假设出来的异常表结构：

- `1612f274`（2025-12-24）：首次建立 `profileLightSensorTemplate`，`id` 列没有主键或唯一约束。
- `05e78f18`（2026-01-08）：在建表 closure 中增加 `builder.unique(ExpressionKey.id)`。
- 当前 `ProfileLightSensorTemplate.initDatabase()` 仍然只使用 `CREATE TABLE IF NOT EXISTS`，没有为已存在的旧表补约束或迁移重复行。
- 当前 `save(profileId:)` 使用 `INSERT OR REPLACE`。旧表没有唯一冲突时，这条语句只会插入新行，不能替换原行。

因此，上次修复后的“调用正确保存接口”对新表有效，但对这种真实存在过的旧表仍不能完成原记录更新。旧记录保留 14 个地址，新行只有 3 个；重新读库会读到两条同 ID 的模板，下一轮仍对旧行生成一项清理操作。

### 生产代码与历史表结构的复现

临时探针从历史提交逐字抽取旧版模板建表方法，再运行当前建表初始化、当前模板保存/加载、当前模板清理循环、当前 App 配置事务。每次清理后重开 SQLite 连接，排除只验证内存对象的情况。夹具只使用脱敏模板与 14 个合成地址（3 个有效、11 个失效）。

| 数据库 | 当前初始化后的索引数 | 清理次数 | 同 ID 记录数 | 各行设备地址数 | remainingChanges |
| --- | --- | --- | --- | --- | --- |
| 新建表 | 1 | 1 | 1 | 3 | 0 |
| 新建表 | 1 | 2、3 | 1 | 3 | 0 |
| 历史旧表 | 0 | 1 | 2 | 3、14 | 1 |
| 历史旧表 | 0 | 2 | 3 | 3、3、14 | 1 |
| 历史旧表 | 0 | 3 | 4 | 3、3、3、14 | 1 |

临时复现：`/tmp/space-sync-legacy-analysis-260923/reproduce.py`、同目录 `Probe.swift`。本轮没有修改生产代码、SDK 或用户数据，也没有构建 App。

**结论边界：旧表兼容缺陷已确定性复现，行为与新日志完全吻合，是当前最强原因候选；尚未直接读到该手机实际 schema 或修复后重复记录，不能将现场匹配说成已完成。** 旧快照没有表结构，且拍摄于正确模板保存调用落地前，当时只有一行并不能排除此问题。

### 为什么上次回归没有发现

上次回归虽使用真实 SQLite，但模板表通过当前代码新建，自带唯一约束。它证明了新表上 14 → 3 能写入，并未覆盖“安装旧版本后持续升级”的数据库结构。此次证据说明，仅补保存调用和新表测试不足以关闭该问题。

### 下一步建议

1. 用修复后的 Space 调试导出核对 `rawLocal.app.profileLightSensorTemplate`：重点看同一个 `id` / `profileId` 是否重复、是否同时存在 14 地址旧行和 3 地址新行。已有导出器会读取这些原始行，不必先修改业务代码。
2. 若匹配，在共享模板持久化入口修复旧表的幂等更新，不能继续依赖未经迁移的唯一约束；同一模板反复保存必须更新已有身份，而不是追加。
3. 收敛已产生的重复记录，并补旧表约束迁移。只自动合并身份、归属和配置可证明一致的记录；本例可以比较按当前有效设备集合清理后的地址是否一致。不同 Profile 归属、不同名称/阈值或仍不一致的有效地址不能靠取第一行、最后一行或直接清表解决。去重及建约束必须在事务内，失败保留原数据与同步保护。
4. 补历史 schema → 当前初始化 → 清理 → 重开数据库 → 再清理的行为回归，同时覆盖多轮失败已产生重复行、正常新表、保存失败回滚与重试，以及同 ID 的真实配置冲突。继续保留现有 `remaining.isEmpty` 检查。
5. 扩展 DEBUG 诊断，使剩余清理项能区分模板/日程/场景/开关等来源；仅输出类型、计数及必要的非敏感标识，不输出完整配置或密钥。如新导出不匹配模板重复，先据此精确定位实际残留，不能先迁移数据来试错。

不建议清空 App 数据、删除模板或直接解除恢复保护；这些操作会绕开失败现场，不能证明持久化链路已经修好。

## 新现场导出确认（2026-09-23 14:23）

用户补充 `/Users/maginawin/Desktop/tmp/Space_3楼_20260923_142335_528+0800.json`，捕获时间 `2026-09-23T06:23:35Z`。与 09-22 快照对比确认：

| 项目 | 09-22 | 09-23 |
| --- | --- | --- |
| 目标模板记录总数 | 1 | 13 |
| 同 ID 的 14 地址旧行 | 1 | 1 |
| 同 ID 的 3 地址清理后行 | 0 | 12 |

13 行的 `id` 均为 `53B94F5B-61EA-448F-A889-4EF04C35D2F4`，`profileId` 均为 `6F0CAD96-2501-4924-B014-88403A73BF51`。除 `deviceAddresses` 外，所有字段逐项一致；12 条清理后记录完全一致，均只含 `0711`、`0714`、`0720`。旧行按当前有效设备集合清理后也恰好等于这三项，因此本例没有名称、阈值、归属或有效设备集合的去重冲突。

这直接确认了清理后追加新行、旧行未被替换的现场数据形态，与历史旧表复现完全一致，能够解释每次 `remainingChanges=1`。13 条重复 ID 也证明实际表没有有效的全表 `UNIQUE(id)` 约束；具体 schema 文本仍未导出，但已经不影响本次保存语义缺陷的判断。

其他数据核对：节点仍为 7，Group 为 7（含 2 个虚拟组），场景 6、日程 1、开关 1；原始 Mesh 表与网络配置逐项未变。导出节点的 schedules 数组存在顺序变化，按 id 排序并排除 Space 更新时间后，业务导出 payload 与旧快照相同。App 原始行变化还包括替换写产生的行号及等价 JSON blob 编码，不构成新的设备配置变化证据。

新快照的 `syncCloudError` 已为空，但 `lastUploadCloudTimestamp` 仍为 `1779070832`，并未随本地 `lastUpdateTimestamp=1790144609` 推进；结合新日志的明确失败，不能把错误字段为空当作同步成功。

下一步可以直接针对已确认问题制定实施：共享模板保存入口兼容无唯一约束旧表、事务内安全合并本例重复数据，并补约束迁移及历史表回归；保留原来的清理读回和上传确认保护。不能仅删除 12 条新记录，因为剩下的旧行仍含 11 个无效引用；正确结果应为一条保留模板名称、阈值和归属、仅含 3 个有效地址的记录。本次补充仍只做分析和文档更新，未修改业务代码。

## 本轮修复与验证（2026-09-23）

用户授权“修复这些问题”后，修改基于 `fix` / `e3856fc4`，当前未提交。SDK 仍为本地 `one-dev` / `ebbe1c9`，无 SDK 修改或新增 API 依赖。

### 实际行为

- 共享模板保存入口使用事务内显式替换，不再依赖旧表上不存在的唯一约束。同一 ID 反复保存只有一行；缺少数据库连接、跨 Profile 同 ID、冲突重复或损坏数据返回失败。
- Space 清理按 Profile 读取原始模板行、按模板 ID 生成一次操作。名称、阈值、归属必须一致，按已验证的当前 Space 有效地址集合过滤后，地址集合也必须一致，才允许合并。现场形态由 13 行收敛为 1 行，地址为 `0711`、`0714`、`0720`。
- 即使重复行的地址已经全部有效，也会清理重复；准备阶段不写库，执行前再核对原始记录，防止覆盖准备后出现的变更。沿用原有备份、配置事务、清理回读及上传确认保护。
- 初始化时为没有重复 ID 的旧表补唯一索引；有重复时延迟。当前 Profile 安全清理后再次尝试建索引。若其他 Profile 还有重复或冲突，不擅自处理其他数据；当前模板保存仍可在没有索引时正确更新。
- 增加 DEBUG 模板清理阶段、合并前后行数和保留地址数诊断；冲突/损坏明确记录原因，不打印凭据或完整配置。

### 失败重试的事务补充修复

真实 SQLite 新增测试在原代码上确定性失败：先执行失败事务、再执行失败的嵌套事务，然后在同一连接上成功更新；当前连接可以读到新值，独立连接仍读到旧值。SDK 的 `savepoint` 失败路径只执行 `ROLLBACK TO SAVEPOINT`，该语句不会关闭保存点，后续重试仍被困在外层未提交事务中。

App 的 `configurationTransaction` 现在在同一串行连接内捕获业务异常、回滚到本次保存点，让 SDK 正常释放保存点后再返回失败。保留嵌套事务及外层回滚语义，不修改共享 SDK。回归确认同连接重试的成功结果可从独立连接读取。这个缺陷由本轮故障注入确认，不把它声称为已在用户手机日志中单独识别的错误。

### 回归与构建证据

| 验证 | 本轮结果与边界 |
| --- | --- |
| `check_profile_persistence.py`（实际模型、SQL、清理调用与 SQLite） | 通过。历史无约束表、13 行现场形态、无失效地址的重复、重复保存、重开/独立连接回读、清理及共享保存失败回滚、同连接重试、索引迁移与重复插入拒绝、旧表无重复时升级均覆盖 |
| 模板冲突与隔离回归（同上） | 通过。名称、白天/夜间阈值、有效地址、跨 Profile 归属冲突及损坏 JSON/非法地址/非法阈值不被覆盖；其他 Profile 冲突不阻断当前 Profile；准备后被修改的数据拒绝覆盖 |
| `check_configuration_database_safety.sh` | 通过。原 WAL 快照与嵌套回滚回归，加失败后同连接重试、独立连接读取已提交结果 |
| `check_space_sync_readback_reuse.py` | 通过。执行生产准备流程的隔离测试，写入失败、读回异常和仍有清理项均不能完成恢复 |
| `check_space_sync_cleanup.py` | 通过。完整快照清理、旧格式兼容及重复执行行为 |
| SunSmart / Debug / generic iPhoneOS | `BUILD SUCCEEDED`；`SunSmartLocal.xcworkspace`，`CODE_SIGNING_ALLOWED=NO`，稳定 DerivedData 为 `SunSmart-fix-cli` |

历史表回归在修复前失败于“清理后仍非一行”的断言；失败后重试回归在修复前失败于独立连接看不到已宣称成功的写入。修复后上述测试均通过。生产代码只有 App 数据持久化和模板清理入口变化，各品牌无新增资源、依赖或不同编译路径，因此选择 SunSmart 代表构建，没有机械重复五品牌编译。

### 最短现场验收

保留原 App 数据安装本轮版本，进入原 Site → 3楼 → 执行云同步。预期模板清理诊断为 `rowsBefore=13 rowsAfter=1 addressesAfter=3`（若期间又重试过，起始行数可更多），随后清理回读通过并进入上传及确认。仅有该诊断还不能代表整笔事务或云同步成功。

同步后再进入或重启 App，确认不再出现 `cleanupExtensionRemaining`；如再导出，目标模板应只有 1 行、保留上述 3 个地址，节点/组/场景/日程仍在，上传确认状态正常。未自动安装运行真机或操作服务端，用户原始 JSON 文件未修改。
