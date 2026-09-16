# 网关删除修复实现与验证

- 日期：2026-09-16。
- 工作区：`fix-gateway`，基线 `b4716de0`。
- 实施依据：[最终删除方案](260916_1131_gateway_online_server_first_delete_decision.md)。
- 用户明确不需要真机测试；本次未安装、启动或操作真机 App，也未使用 Simulator。

## 修复结果

Owner 和 Editor 均需手机联网才能发起 Delete。确认后先请求 `/sitespace/sapce/gateway/delete`，服务器明确成功才继续：目标蓝牙 Mesh Proxy 就绪则尝试一次 Reset；未就绪或 Reset 未确认成功仍完成本地删除，提示重新添加前手动重置。取消原 FORCE DELETE 二次确认。服务器失败或超时不发送 Reset、不主动删除本地记录。

WiFi 与 4G 共用此流程。网关关联零个、一个或多个 Spaces 均不影响删除资格，保留原有角色权限校验；Editor 需要校验当前服务器关联权限。

原误报已从网关删除调用链移除：Site 网关使用捕获 Site 主网络的专用上下文，不再调用要求 Space 存在的 `DeviceProtocol.deleteNodes`。普通 Space 设备删除保护未更改。原错误直接回归于 `abfbe5a7`（作者 2026-09-07，提交 2026-09-08），详细证据见[根因分析](260916_1045_gateway_delete_scope_analysis_plan.md)。

## 关键实现

- `GatewayDeletionCoordinator` 统一联网、权限、云端结果、Reset 和本地收尾的顺序。服务器成功后手机断网不影响后续蓝牙与本地操作。
- `GatewayDeletionContext` 在调用服务器前捕获 Site、Mesh UUID、主网络 ID、Node UUID、地址、元素地址和配网时间；Reset 成功时 SDK 已移除 Node、清空其 network 引用，也能幂等完成 App 数据清理。
- 清理 Node、GatewayModel、相关 Scene/Schedule 地址、预配置、匹配的 OTA 分发缓存，以及 Space 的网关关联、状态、最后在线信息。保持 SDK 正常废弃地址处理。
- 小型持久化记录分为 prepared、serverDeleted、completed，按账号和区域隔离，不存储认证凭据或设备密钥。它只用于本地恢复和阻止旧云快照重新导入，不是离线云删除队列。
- Site 进入时恢复已确认云端删除的本地收尾，兼容旧 `serverDeletionPendingLocalReset`。未确认服务器结果的中断仅释放准备记录，不推断服务器成功。
- 删除过程中阻止普通注册和旧模型回写；Site 导入的检查与 Node/Gateway 写入和删除共用锁，等待 Reset 时完整云快照不能抢先删除目标，完成后旧快照不能恢复旧实例。
- 配网实例匹配使用 UUID、地址和创建时间；旧删除回调不能删除后来占用地址的新实例。同一个设备重新配网后允许保存和注册。
- 删除期间禁用重复操作，停止网关轮询，取消在途时钟操作的本地持久化回调，防止与 Reset 竞争；云端删除失败时恢复正常页面操作。
- 确认、完成与失败提示复用现有弹窗和 Site Toast。新增／修改文案同步 English、简体中文；新源码加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个 target。未修改 SDK 或依赖。

## 自动化验证

| 检查 | 结果 |
| --- | --- |
| `bash scripts/check_gateway_deletion.sh` | 通过：协调器行为、生产本地删除适配器执行测试、原 Force Clear Spaces 及删除接口契约、五个 target 和双语言集成检查 |
| `bash scripts/check_gateway_detail_proxy_ready_state.sh` | 通过：12 项 Proxy 状态行为及接入检查；修正旧脚本四品牌计数为工程现有五品牌 |
| `bash scripts/check_gateway_multi_role_consistency.sh` | 通过：权限、关联候选和同步代次回归 |
| `bash scripts/check_gateway_information_time.sh` | 通过：详情时钟、同步、自动加载及相关运行时契约 |
| `bash scripts/check_wifi_gateway_server_information_recovery.sh` | 通过：服务器授权恢复契约 |
| `plutil -lint` 工程与两语言文件 | 通过 |
| `git diff --check` | 通过 |

新增行为测试包括：手机离线、权限拒绝/查询失败、服务器失败、预检/落盘失败、服务器成功后的断网、蓝牙未就绪、Reset 失败、重复点击、账号切换、确认过的删除重试、损坏记录、重新配网代次区分。

本地适配器测试编译并执行生产 `GatewayDeletionContext.swift`，仅替换 SDK/存储边界与临时根目录。覆盖四种 Product ID 输入和零/一/三个关联 Space、SDK 先移除 Node、无 Reset 收尾、业务引用清理、中断恢复、并发保护、旧版状态、新配网实例保护。这些是替身环境验证，不代表已验证对应硬件型号。

额外运行了 `check_site_sync_gateways.sh`：前面的行为和接口/UI 契约通过，随后停在既有 `SiteEntryTimeZoneSyncContractTests.swift` 的“四品牌”计数断言。其期待 8 处引用，基线 HEAD 和本次工作区均为 10 处；这是已有测试与五品牌工程不一致，未扩大本次修复范围。脚本后续检查未执行，不计为全套通过。

## 构建与 UI 检查

使用直接 `xcodebuild -workspace SunSmart.xcworkspace -scheme <品牌> -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`，后续增量校验增加 `-quiet`，不包装 shell、不重定向日志。

最终代码的五个品牌增量构建均通过（退出码 0）：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。构建仍有工程已有的重复资源/编译项、Info.plist 资源阶段以及弃用 API 等警告，未扩展处理这些无关项目。

静态检查现有 `SRAlertView` 的多行 messageLabel、按内容高度约束、详情 iPad preferredContentSize，以及删除后 Toast 的展示宿主。无新页面或新布局组件。遵用户要求未做真机 UI 或硬件验证，不能以构建通过宣称 Reset 回执、重新添加和实际文案布局已经验收。

## 剩余验证边界

- 未访问生产删除接口；服务器端行为依据现有接口成功/失败合同和客户端替身测试。
- 请求超时不能推断服务器是否已执行。本次客户端不主动 Reset 或删除本地；用户可重试以确认服务器结果。
- 若旧版本已丢失网关 Node/密钥，本次修复无法替代硬件手动重置。
- 本地持久化失败显示网关专用失败提示并保留可恢复记录，不再误报 Space 数据清理问题。

改动保留在工作区，未创建 Git 提交。
