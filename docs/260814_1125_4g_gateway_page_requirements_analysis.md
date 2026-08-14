# 4G Gateway 页面优化需求分析与方案草案

## 结论

需求方向明确，但目前还不能直接进入开发，主要缺口是设备身份口径未闭合：当前仓库不能证明 `CID 0x0A78 / PID 0x2703` 已被认定为 4G Gateway。

当前源码事实如下：

- 内置 `devices_config.json` 中，明确登记为 4G Gateway 型号 `SR-BL9036T-GW-WP4G` 的 PID 是 `0x2711`；另有 `0x1702` 也登记为同一 4G Gateway 型号。
- `0x0A78 / 0x2721` 被 App 单独识别为 WiFi Gateway。
- 当前仓库及本地 `NordicSigMeshSDK` 均没有 `0x2703` 的显式记录。
- App 会从 `/devicesConfig` 拉取运行时设备配置，并用服务端结果整体替换、缓存本地支持列表。因此，只有生产服务端当前返回了 `0x0A78 / 0x2703` 且 `deviceCategory = Gateway`，运行时才可能把它识别为 Gateway；本轮静态源码检查无法证明这一点。
- Site 页面只对 `0x0A78 / 0x2721` 打开 `WiFiGatewayViewController`；其余已经被识别并出现在 Gateway 列表中的设备都打开 `GatewayViewController`，该页面实际承担非 WiFi Gateway，也就是当前 4G Gateway 页面。

因此，对“`0A78/2703` 目前认定为 4G Gateway，正确吗”的回答是：**按当前仓库不能认定为正确；仓库内明确的 4G PID 是 `2711`，`2703` 是否成立还依赖当前服务端设备配置。**

## 当前页面与需求对照

### 已经满足，不需要重复修改

- `Activate` 已不在 `GatewayViewController.sections` 中，当前主页面不会渲染 Activate 行。
- WiFi Gateway 已使用左侧返回按钮、右侧菜单按钮。
- WiFi Gateway 已使用单独占满底部的 SAVE 按钮。
- WiFi Gateway 的 Delete、Information、Identify 已有真实行为：
  - Delete 复用 Gateway 删除链路；
  - Information 打开共享 `DeviceInformationViewController`，隐藏 Group 和 Scene；
  - Identify 向当前 Node Primary Unicast Address 发送 SIG Mesh Identify。

### 4G Gateway 当前仍需调整

- 当前只有右侧 Close，没有左侧 Back 和右侧 More。
- 仍展示 Mac、Address、Model、Device Type、Firmware 的 Info Section。
- 配置正常时底部仍是 DELETE + SAVE；修复状态时底部可能展示单独 DELETE。
- 没有 4G DFU、Delete、Information、Identify 菜单。

### Information 页面实际内容

若完全复用 WiFi Gateway 当前入口，4G Gateway Information 页面会展示：

- Name
- MAC
- PID
- Address
- Version Identifier
- Model
- Device Type
- Firmware
- Signal Strength

这比主页面待移除的五行更完整，符合“与 WiFi Gateway Information 页面相同”的要求。

## 需求完整性评估

### 已完整的部分

- 导航栏目标布局和菜单顺序明确。
- Delete、Information、Identify 要复用 WiFi Gateway 行为，行为来源明确。
- 4G DFU 当前只展示开发中提示，不进入升级流程，边界明确。
- Info Section 和底部双按钮的移除目标明确。
- 只移除 Activate 的 UI 行，不改 `GatewayModel.activate`、同步数据或协议行为，边界明确。

### 需要确认或采用默认口径的部分

1. **PID 口径**
   - 需要确认实际目标是 `0x2703` 还是仓库已登记的 `0x2711`。
   - 如果实际设备确为 `0x2703`，还需确认它是否已经由生产 `/devicesConfig` 下发为 Gateway；若要求无服务端配置时也能识别，则需把 bundled fallback 配置纳入本次范围。

2. **页面适用范围**
   - 推荐将本次 UI 调整应用于所有“已经识别为 Gateway 且不是 `0x0A78 / 0x2721` WiFi Gateway”的设备，而不是在页面内硬编码 `0x2703`。
   - 这样可同时覆盖当前 `0x1702`、`0x2711` 和未来由服务端配置的 4G Gateway，且不影响 WiFi Gateway 专属网络配置。

3. **修复状态底部行为**
   - 推荐完整对齐 WiFi Gateway：正常状态只显示 SAVE；Key Bind 不完整的修复状态隐藏底部按钮，删除仍从右上角菜单进入。
   - 若只要求替换正常状态的 DELETE + SAVE，而修复状态仍保留底部 DELETE，需要单独说明。

4. **开发中文案**
   - 推荐复用现有国际化 Key `under_development`。当前中文是“哎呀！开发中。”，英文是“Oops! Under development.”。
   - 菜单标题需要新增 `4g_dfu` 的 English 与简体中文翻译；默认 UI 标题使用英文 `4G DFU`。

5. **Copy Gateway Information**
   - WiFi Gateway 当前仍保留底部 Copy Gateway Information，因此推荐 4G Gateway 也继续保留。
   - 本次“移除 Activate 行”按表格行理解；不修改底层 `activate` 字段，也不顺手调整复制内容。

## 可选实现方案

### 方案 A：共享菜单骨架，WiFi 只覆盖 DFU 项（推荐）

在 `GatewayViewController` 中建立 Gateway 页面共同导航与菜单行为：Back、More、Delete、Information、Identify、菜单定位、Information 子页面的模态关闭保护。基类默认提供 4G DFU 占位项；`WiFiGatewayViewController` 只替换第一项为现有真实 WiFi DFU。

同时在 4G 基础页面移除 Info Section，并把底部状态调整为与 WiFi Gateway 一致。

优点：

- 直接落实“除 DFU 外其他都相同”。
- Delete、Information、Identify 只保留一套行为，后续不易漂移。
- 不需要新增 4G 专用页面路由，也不把 UI 绑定到单个 PID。

代价：

- 需要同步更新几项现有 WiFi Gateway 静态 contract，因为共同代码会从 WiFi 子类移动到 Gateway 基类。

### 方案 B：在 4G 基础页面复制一套 WiFi 菜单

保留 WiFi 页面不动，在 `GatewayViewController` 中新增相似菜单和导航代码。

优点是短期改动直观；缺点是 Delete、Information、Identify、菜单动画与模态保护形成两份实现，后续容易出现 WiFi 与 4G 行为不一致，不符合需求强调的“其他都相同”。不推荐。

### 方案 C：新增显式 FourGGatewayViewController

新建 4G 子类，并在 Site 入口按 4G PID 白名单路由。

优点是类型表达清晰；缺点是必须先定义完整 4G PID 权威列表，并扩大入口、分类、测试和 target 配置范围。当前 `0x2703` 身份尚未闭合，过早引入显式白名单风险更高。本轮不推荐。

## 推荐设计

采用方案 A，页面范围为“非 WiFi 的 Gateway”，不在 UI 层新增 `0x2703` 特判。

### 页面结构

- 导航栏：左侧 Back，右侧 More。
- Section：Name、Associated Spaces、APN、Server Information；移除 Info，Activate 继续不展示。
- Footer：保留 Copy Gateway Information。
- Bottom：配置正常时只显示 SAVE；修复状态隐藏底部操作。

### 菜单顺序与行为

1. 4G DFU：展示现有 Under Development 提示，不跳转、不发送 Mesh 命令。
2. Delete：仅在当前仍具备 Gateway 配置权限时展示；复用现有删除确认、服务端删除、关联 Space 权限检查、Mesh 删除和失败处理。
3. Information：打开与 WiFi Gateway 完全相同的共享 Information 页面，不显示 Group/Scene。
4. Identify：向当前 Gateway Primary Unicast Address 发送与 WiFi Gateway 相同的 Identify 命令。

WiFi Gateway 继续保持相同的后三项行为，第一项仍进入真实 WiFi DFU 页面。

### 状态与交互边界

- Back 继续复用现有 `closeAction`，有未保存修改时保留退出确认。
- Information 和 WiFi DFU push 前继续保护外层模态导航栈，完整返回 Gateway 主页面后恢复下滑关闭能力。
- 4G DFU 只显示提示，不需要进入受保护子页面状态。
- 删除能力移动到菜单不改变删除权限、云端接口、Mesh reset 或 force-delete 语义。
- 不修改 Associated Spaces、APN、Server Information、SAVE 同步流程。

## 预计影响范围

### 业务代码与本地化

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
  - 承担共同导航、菜单、Information/Identify/Delete、模态保护与 4G 默认 DFU 项。
  - 移除 4G Info Section，调整底部行为。
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - 保留 WiFi 专属网络配置与真实 WiFi DFU，只移除迁入基类的重复共同逻辑。
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 新增 4G DFU 菜单标题；Identify 使用现有国际化 Key。

### 需要同步调整的聚焦 contract

- `scripts/check_gateway_activate_header_layout.sh`
- `scripts/check_wifi_gateway_info_rows_hidden.sh`
- `scripts/check_wifi_gateway_menu_icons.sh`
- `scripts/check_wifi_gateway_child_page_modal_dismissal.sh`
- `scripts/check_device_menu_icons.sh`
- `scripts/check_device_information_menu_transition.sh`

contract 需要从“共同逻辑必须位于 WiFi 子类”调整为“共同逻辑位于 Gateway 基类，WiFi 只提供 DFU 差异”，同时验证：

- 4G 与 WiFi 菜单顺序一致；
- 4G DFU 只显示开发中提示；
- WiFi DFU 仍进入真实升级页面；
- Delete 权限与原删除方法保持；
- Information 参数、Identify 目标地址一致；
- Info 与 Activate 不出现在主页面；
- 4G 正常/修复状态底部与推荐口径一致；
- 两类 Gateway 的受保护子页面返回逻辑不回退。

## 开发阶段计划

1. 先更新聚焦 contract，使其针对推荐设计失败，建立 RED 基线。
2. 把 Gateway 共同导航、菜单项和模态保护收口到基类，WiFi 子类只保留真实 WiFi DFU 差异。
3. 调整 4G 主页面 Section 与底部按钮状态，不改配置保存、删除或协议链路。
4. 补齐 `4g_dfu` 双语本地化，并把 Identify 改为复用现有国际化 Key。
5. 运行所有受影响的 Gateway/Information/Menu 聚焦 contract 与 `git diff --check`。
6. 直接使用 generic iPhoneOS、关闭签名，依次构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart；不使用 Simulator。
7. 真机分别回归一个 4G Gateway 和 `0x2721` WiFi Gateway，验证菜单、删除、Information、Identify、未保存退出、SAVE、修复状态及子页面下滑关闭保护。

## 验收边界

- 静态 contract 和四品牌构建只能证明源码结构、资源引用及编译通过。
- Identify 必须通过真实 Mesh 设备观察识别效果或协议日志确认。
- Delete 必须验证服务端删除、关联 Space 权限和 Mesh reset 的真实结果。
- `0x2703` 是否被生产配置识别为 Gateway，必须以当前 `/devicesConfig` 响应或实际 Node 的 CID/PID/Device Category 证据确认。
- 本文档是待确认方案；确认前不修改业务代码。
