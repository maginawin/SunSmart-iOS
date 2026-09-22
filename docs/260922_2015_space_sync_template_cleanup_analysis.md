# 3楼 Space 同步失败：原因与修复方案

日期：2026-09-22。状态：已按确认范围实施，相关回归与 SunSmart generic iPhoneOS Debug 构建通过，待现场验收。下文保留修复前分析证据，实施结果见末尾。

## 结论

已复现一处与现场数据、重复失败日志一致的持久化缺陷：同步前清理光感模板的失效设备引用时，代码修改了 `ProfileLightSensorTemplate.deviceAddresses`，却调用 `GroupInfo.save()`；后者只保存 GroupInfo 与 Profile，不保存独立的模板表。重新读库后失效引用仍然存在，清理无法收敛，上传准备返回 `configurationUnavailable`（-2004）。

建议仅修正模板清理分支的保存对象，复用现有模板保存接口、事务与清理读回校验。无需修改 Mesh SDK、云端协议或放宽完整性保护。现场日志未记录具体 guard，不能证明运行时仅有这一项失败；但本缺陷已用现场数据及真实 SQLite 确定性复现，足以独立阻断同步。

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
