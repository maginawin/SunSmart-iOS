# 4G Gateway 页面优化设计

## 状态

2026-08-14 已确认采用方案 A：共同 Gateway 行为收口到基类，WiFi Gateway 只保留 DFU 与网络配置差异。

## 目标

- 所有已经被识别为 Gateway、且不是 `CID 0x0A78 / PID 0x2721` WiFi Gateway 的设备，使用统一优化后的 4G Gateway 页面。
- 4G 与 WiFi Gateway 共享 Back、More、Delete、Information、Identify、菜单顺序和子页面模态关闭保护。
- 4G DFU 当前只显示开发中提示；WiFi DFU 保持现有真实升级流程。
- 4G 主页面不展示 Activate 行以及 Mac、Address、Model、Device Type、Firmware Section。
- 4G 页面底部与 WiFi 页面一致：配置正常时只显示 SAVE，修复状态隐藏底部操作。

## 非目标

- 不新增 `0x2703`、`0x2711` 或其他 4G PID 特判。
- 不修改 `/devicesConfig`、bundled `devices_config.json` 或设备分类逻辑。
- 不修改 `GatewayModel.activate`、同步数据、云端字段或协议行为。
- 不实现 4G DFU。
- 不改变 Gateway Delete、Associated Spaces、APN、Server Information、SAVE、修复或 force-delete 的业务语义。
- 不修改本地 NordicSigMeshSDK。

## 页面适用范围

Site 入口继续使用现有分流：

- `node.isWiFiGateway == true`：进入 `WiFiGatewayViewController`。
- 其他已进入 Gateway 列表的设备：进入 `GatewayViewController`。

本设计不在 UI 层判断具体 4G PID，因此可覆盖 bundled 配置中的 `0x1702`、`0x2711`，也可覆盖未来由服务端配置为 Gateway 的 `0x2703`。

## 架构

### Gateway 菜单策略

新增 Foundation-only 的 `GatewayMenuPolicy`，负责输出以下可测试决策：

- 当前 DFU 类型是 4G 还是 WiFi。
- 菜单顺序固定为 DFU、可选 Delete、Information、Identify。
- 没有删除权限时只移除 Delete，不改变其他项目顺序。
- 配置正常时底部模式为 Save Only；修复状态为 Hidden。

策略不持有 UIViewController、Node、Site、Gateway 或网络对象，不执行任何副作用。

### GatewayViewController

基类负责所有共同 UI 和副作用：

- 左侧 Back、右侧 More。
- 根据 `GatewayMenuPolicy` 生成菜单。
- 默认 4G DFU 行为：显示现有 `under_development` 提示。
- Delete：调用现有 `deleteBtnAction()`。
- Information：创建现有 `DeviceInformationViewController`，关闭 Group/Scene，并保护外层模态导航栈。
- Identify：调用现有 SIG Mesh Identify，目标为当前 Node Primary Unicast Address。
- Information 完整返回后恢复进入前的 `isModalInPresentation`。
- 基础 Section 不再包含 Info；Activate 继续不包含在 Section 中。
- 配置正常时调用 Save Only UI；修复状态隐藏 Bottom View。

### WiFiGatewayViewController

WiFi 子类只覆盖差异：

- Gateway 菜单类型为 WiFi。
- DFU 行为继续打开 `WiFiFirmwareUpdateViewController`。
- WiFi DFU push 前复用基类的模态导航栈保护。
- 保留 Network Connectivity、WiFi 状态、凭据、时间同步、RSSI 和现有修复恢复逻辑。

删除从 WiFi 子类迁移到基类的共同 Back、More、Delete、Information、Identify、菜单定位和模态保护重复代码。

## UI 结构

### 4G Gateway 主页面

- Navigation：Back / Title / More。
- Sections：Name、Associated Spaces、APN、Server Information。
- Table Footer：继续显示 Copy Gateway Information。
- Configured Bottom：SAVE。
- Repair Bottom：Hidden；页面原 Repair 操作保持。

### 菜单

4G Gateway：

1. 4G DFU
2. Delete（有配置权限时）
3. Information
4. Identify

WiFi Gateway：

1. WiFi DFU
2. Delete（有配置权限时）
3. Information
4. Identify

Diagnosis 继续保持禁用，不纳入菜单。

## 文案与资源

- 新增 `4g_dfu`：English 与简体中文均显示 `4G DFU`。
- 4G DFU 点击提示复用 `under_development`。
- Identify 改为使用现有 `identify` 国际化 Key，移除 Gateway 菜单中的硬编码标题。
- 复用现有 `menu_wifi_dfu`、`menu_delete`、`menu_information`、`menu_identify`、`navigation_back`、`more_vertical` 资源，不新增图片。
- `Localizable.strings` 已进入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个品牌 target；新增 Key 同步检查四个 target。

## 权限和状态

- Gateway 页面入口权限判断保持现状。
- 打开菜单时重新读取 `canConfigureCurrentGateway`；无权限不显示 Delete。
- `deleteBtnAction()` 内部权限复核、服务端删除、关联 Space 权限验证、Mesh reset、force delete 与错误 HUD 保持不变。
- Back 继续调用现有 `closeAction()`；存在未保存修改时保留退出确认。
- 4G DFU 不 push 页面，因此不改变外层模态关闭状态。
- Information 与 WiFi DFU 进入子页面后禁止下滑关闭整个 Gateway 栈；完整返回 Gateway 主页面后恢复原值。

## 测试设计

### 纯策略测试

新增 `GatewayMenuPolicyTests`，覆盖：

- 4G 菜单有 Delete 时的完整顺序。
- 4G 菜单无 Delete 时的完整顺序。
- WiFi 菜单只把第一项替换为 WiFi DFU。
- 配置正常返回 Save Only，修复状态返回 Hidden。

每个期望数组使用手工字面量，不复用生产构造逻辑。

### 集成 contract

更新现有 Gateway shell contracts，验证控制器消费共同策略并保持关键副作用边界：

- 4G DFU 只展示 Under Development。
- WiFi DFU 仍打开现有升级页面。
- Delete、Information、Identify 由基类统一执行。
- Information 参数、Identify 地址、菜单图标和国际化标题正确。
- 基类 Section 不含 Info/Activate。
- 4G Bottom 为 Save Only/Hidden。
- 模态关闭保护从共同 Information 与 WiFi DFU 两个入口生效并在基类恢复。

### 构建与真机

- 运行所有受影响 contracts 和 `git diff --check`。
- 依次构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart 的 generic iPhoneOS Debug，关闭签名，不使用 Simulator。
- 真机回归 4G Gateway 与 `0x2721` WiFi Gateway 的菜单、DFU、Delete、Information、Identify、SAVE、Repair、未保存退出及下滑关闭保护。

## 验收边界

- 自动化与构建不能证明真实 Identify 命令被设备执行。
- 自动化与构建不能证明服务端删除、关联 Space 权限或 Mesh reset 端到端成功。
- 自动化与构建不能证明生产 `/devicesConfig` 已把 `0x2703` 识别为 Gateway。

