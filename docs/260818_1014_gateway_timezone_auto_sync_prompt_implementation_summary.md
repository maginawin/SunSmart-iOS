# Gateway 时区自动同步提示实施总结

## 结果

已按确认方案完成 Wi-Fi 与 4G Gateway 共用详情页的自动时区同步提示：目标 Gateway 达到蓝牙 Mesh Proxy Ready，并完成本 Session 首次 TimeGet 检查后，如果现有 `requiresSync` 判定为需要同步，页面会先刷新 `Sync required` 状态，同时自动展示 `Gateway time zone needs sync`。

- `Later` 只关闭弹窗，不改变 `requiresSync`，Header 继续保留 `Sync required`；
- `SYNC NOW` 继续复用现有 `synchronizeGatewayClock()`，没有复制或修改 Mesh TimeSet、最终 TimeGet 回读校验、本地保存和 Gateway Cloud 排队链路；
- TimeGet 失败或 Gateway 时区未知继续遵循现有语义，显示 `Sync required` 并使用未知时区弹窗文案。

## Session 与重复提示控制

新增 `GatewayClockAutoPromptState`，以 Proxy Ready Session ID 管理临时 UI 状态：

- 同一 Proxy Ready Session 最多自动提示一次；
- 用户选择 `Later` 后，同一 Session 不会再次自动提示；
- 用户点击 `Sync required` 或 `Sync clock` 主动处理后，会取消待自动提示；
- 蓝牙断开会清除待提示，新 Proxy Ready Session 可以重新检查并提示；
- 系统时间/时区变化触发的普通重读不会重复触发本 Session 的自动提示。

该状态不写入数据库或 UserDefaults，仅存在于当前 Gateway 页面实例。

## 弹窗冲突与生命周期

- 自动提示前校验页面仍可见、目标 Node 和 Proxy Ready Session 仍匹配、仍然 `requiresSync`、当前未同步且没有等待启动的同步；
- 如果已有其他 `SRAlertView`，不会调用会替换现有 Alert 的 `show()`，而是每 0.5 秒延迟检查；
- 页面离开、Proxy 断开或用户主动操作时取消延迟任务；
- 每个延迟任务带唯一重试 ID，已取消的旧 DispatchWorkItem 即使后续被调度，也不能清空或触发新的有效任务；
- 页面返回且同一 Session 仍有待提示时，会重新尝试展示，不会跨页面弹出。

## 测试更新

扩展 Gateway Detail Clock 纯逻辑测试，覆盖：

- 已同步时不请求自动提示；
- 需要同步时可提示；
- 同一 Session 只处理一次；
- 新 Session 可以再次提示；
- 页面不可见、同步中、已有等待同步和已有 Alert 时延迟；
- 临时阻塞不会丢失待提示状态；
- Session 结束清除待提示。

扩展 Runtime Contract，约束：

- 首次 Proxy Ready TimeGet 携带 Session 进入自动提示判定；
- 自动提示复用 `requiresSync`；
- 自动提示必须经过 Session 状态门禁；
- 不覆盖已有 `SRAlertView`；
- 手动提示和同步会抑制重复自动提示。

同时修复 `scripts/check_gateway_information_time.sh` 已失效的 loading SVG 参数：原路径资源已不存在，页面当前实际复用 `site_entry_sync_loading`，脚本和契约现已与源码一致。

## 验证结果

以下聚焦检查通过：

- `GatewayTimeInformationCoordinatorTests`
- `GatewayDetailClockCoreTests`
- `GatewayDetailClockRuntimeContractTests`
- `GatewayTimeInformationRuntimeContractTests`
- `GatewayInformationTimeRowsContractTests`
- `GatewayFastAddTimeInitializationTests`
- `GatewayFastAddTimeInitializationContractTests`
- `WiFiGatewayAutomaticLoadGateTests`
- Wi-Fi Gateway Proxy Ready 不自动发送 TimeSet 契约
- 中英文 `Localizable.strings` 校验
- `project.pbxproj` 校验
- `git diff --check`

以下 generic iPhoneOS、Debug、关闭签名构建通过，均使用本地 NordicSigMeshSDK：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

## 改动文件

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
- `SunSmart/Main/Device/Gateway/Model/GatewayDetailClockCoordinator.swift`
- `Tests/Device/GatewayDetailClockCoreTests.swift`
- `Tests/Device/GatewayDetailClockRuntimeContractTests.swift`
- `scripts/check_gateway_information_time.sh`
- `docs/260818_1004_gateway_timezone_auto_sync_prompt_plan.md`
- `docs/260818_1014_gateway_timezone_auto_sync_prompt_implementation_summary.md`

未新增或修改用户文案、资源、target 配置、依赖或 NordicSigMeshSDK 源码。

## 尚未覆盖

- 未使用真实 Wi-Fi/4G Gateway 验证 BLE Proxy Ready、TimeGet、TimeSet 和最终 TimeStatus；
- 未验证真实 Gateway 的时区已同步、明确不一致、未知/读取失败三种矩阵；
- 未验证 `Later`、断开重连、已有其他 Alert 时延迟展示的真机视觉和交互；
- 未验证 Gateway Cloud 最终回读。

自动化测试和 generic iPhoneOS 构建证明源码契约及四品牌编译通过，但不等同于真实 BLE/Mesh、固件、服务器或真机 UI 验收。
