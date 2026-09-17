# Debug JSON 在同步异常时导出本地配置

## 已定位原因

- `DebugCloudJSONExporter.Snapshot.validate()` 将 `canReadDebugSnapshot == false` 统一转成数据/权限变化；该检查还包含恢复阶段、pending-import 和待清理删除记录，与 Owner 权限无关。
- Debug 导出虽然绕过上传，但仍受触发区反序列化、Group Profile 加载、邻近照明硬错误和未应用拓扑修复等校验限制。
- `configurationExportInvalid` 统一映射成邻近照明导出无效。此文案不足以证明本地与服务器不兼容，更不能定位具体字段。

## 本次实现

- 调试导出允许同步错误、待同步、恢复保护和待导入状态；账号、区域、对象和实际角色变化仍保护。
- 保留可生成的同步字段，不应用拓扑修复；增加 `_debugInspection` 诊断和当前范围的数据库原始记录。JSON Blob 同时提供可读内容与原始 Base64，解析失败仍保留原字节。
- 无法组装的 Space 不阻断整个 Site，不用空 nodes/groups 伪装成完整同步请求；明确记录组装失败，原始记录继续导出。
- 保留原有 Mesh 配置值；不新增登录 Token、Keychain、密码等 Auth 信息。导出不发网络请求、不修改同步状态或恢复记录。
- 文件写入处理已捕获的快照，写入完成后只复核访问上下文，避免随后发生的普通数据更新使已生成文件失效。

## 验证安排

覆盖受保护 Space、异常拓扑、原始 Blob、Site 部分组装失败、权限/账号变化、数据库读取错误及只读性。执行相关自动化回归及 iPhoneOS 构建；真机能连接时运行现有导出 UI harness。

## 导出文件阅读方式

保留原接口的 Site `site.spaces[]` / Space `spaces[]` 外层供字段对比；增加 `_debugInspection`，整个文件是本地诊断材料，不是可直接提交的上传请求。

| 路径 | 用途 |
| --- | --- |
| `_debugInspection.spaces[].spaceId` | 用 UUID 定位 Space，避免依赖数组顺序。 |
| `_debugInspection.spaces[].issues` | 邻近照明硬错误、未应用修复、孤立组成员、加载失败位置及 Profile 校验错误。 |
| `_debugInspection.spaces[].status` | 本地 blockedReason、pendingImport、pendingDeletionCleanup、recoveryPhase。 |
| `_debugInspection.spaces[].comparisonPayloadAvailable` | 是否成功组装模型层的对比内容；不代表云端接受，也不证明字段未经模型转换。 |
| `_debugInspection.spaces[].rawLocal.app` | 当前 Space 的原始 spaces、groupInfos、profiles、sceneInfos、schedules、switchs、emergencyFireControllers、pjEightKeySwitchs、引用的 profileLightSensorTemplate 和 node_preConfiguration 行。 |
| `_debugInspection.spaces[].rawLocal.mesh` | 当前子网的 nodes、nodePropertys、groups、scenes 原始行，包括正常模型导出可能过滤的记录。 |
| `_debugInspection.spaces[].rawLocal.networkConfiguration` | 当前 Space 的 Mesh NetKey / AppKey；组或触发区解码失败时仍尝试保留。网络本身不能加载时明确标记 unavailable。 |
| `_debugInspection.rawSite` | Site 导出额外保留 Site 行、扩展状态、Site Mesh 网络原始行及地址排除记录。 |

SQLite Blob 中 `json` 是便于阅读的解析内容，`base64` 保留原字节；无法解析的 UTF-8 数据放在 `utf8`。坏 JSON、重复节点、孤立引用不会被调试导出自动修复。数据库确实无法读取时仍会失败，不把读错误替换为空数组。

若 `comparisonPayloadAvailable` 为 false，该 Space 的接口对比位置仅保留 UUID / 名称；完整的已覆盖配置表记录在 `rawLocal`，不产生具有删除含义的空 nodes/groups。此功能覆盖本次 Site/Space 配置排查，不是整个账号数据库、历史请求或服务器备份；密码、分享凭据、登录 Token 和 Keychain 不在导出范围。

## 验证结果

- `scripts/check_debug_json_export.py` 通过：执行实际 SQL / Blob 导出、快照协调器、JSON 文件读写。覆盖原始损坏 JSON、任意二进制、类型/时间戳、旧 Profile 引用、Site/Space 隔离、Auth 排除、数据库无写入、查询错误不变为空集合、异常 Space 不阻断 Site、捕获后普通更新允许分享、账号/区域/角色变化拒绝分享。
- `scripts/check_proximity_scoped_import.py` 通过：现有生产拓扑适配器、恢复/删除、作用域隔离与无云端副作用回归。
- 工程文件语法及 `git diff --check` 通过；新增文件接入五个品牌 target，未修改 SDK 或本地化资源。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五品牌 Debug generic iPhoneOS 构建通过；SunSmart Release 构建结果继续补充。
- 在 MtestiPhone15 安装并直接运行独立测试 App，真机输出快照测试 PASS。未安装/替换用户的业务 App。
- 受保护数据分享 UI 自动化在测试启动前受阻：XCTest Driver 拒绝连接，Runner 在建立连接前退出（code 74）。未执行分享断言，不能据此宣称分享 UI 验收通过。测试结果位于 `/tmp/DebugJSONSyncInspection/ProtectedExportVerified.xcresult`。
- 本次没有取得用户实际故障 Space 的本地与服务器 JSON，因此尚不能断言具体哪个业务字段与云端不兼容。

## 人工检查

1. 重新运行修改后的 Debug App，保持问题 Space 的同步错误和待同步状态，分别从 Site 与 Space 菜单点击 Export Json。
2. 在系统分享面板保存文件；确认问题 Space 的 UUID 存在，查看对应 `issues`、`status` 和 `rawLocal`，并确认 App 原同步错误未被导出清除。
3. 与同一 Site/Space UUID 的服务器 JSON 对比。优先检查报错组地址对应的 Profile、proximityLightingPath，以及 spaces.triggerZones 的 `json`/`utf8` 原值。
4. 真实界面的分享、取消、iPad popover 和最终体验仍由人工确认。
