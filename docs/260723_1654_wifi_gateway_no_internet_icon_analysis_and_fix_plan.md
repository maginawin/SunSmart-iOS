# WiFi Gateway No Internet 图标问题分析与修复计划

## 1. 结论

问题存在。

当前 WiFi Gateway 页面收到 `networkStatus == .unavailable`（用户可见状态为 `No Internet`）时：

- 状态文案显示 `No Internet`；
- 图标仍沿用同一响应中的 RSSI 分级结果，即 `wifi_excellent`、`wifi_good`、`wifi_poor`、`wifi_bad`，RSSI 无效时则为 `wifi_no_signal`；
- 不会展示已经存在的 `wifi_no_internet` 图标。

因此，当前行为不满足本次预期：“No Internet 时展示 `wifi_no_internet`，而不是 Wi-Fi 信号图标”。

## 2. 证据链

### 2.1 SDK 正确解析独立 Internet 状态

本地 `NordicSigMeshSDK` 在 `SunricherVendorStatus.swift:58-79` 解析 `0x43/0x0F` 五字节响应：

- 第 3 字节解析为 RSSI result；
- 第 5 字节解析为 `WiFiGatewayNetworkStatus`；
- `network_status = 0x01` 映射为 `.unavailable`。

SDK 的 `WiFiGatewayRSSIStatus` 同时保存 `rssiResult` 和 `networkStatus`。因此本问题不是协议解析丢失 `No Internet` 状态，也不需要修改 SDK。

### 2.2 App 在 UI 映射层沿用了 RSSI 图标

`WiFiGatewayViewController.swift:1311-1333` 先根据 RSSI 生成 `signalStatus`，再根据 Internet 状态决定最终显示：

- `.normal`：使用 `signalStatus`；
- `.unavailable`：文案改为 `wifi_status_no_internet`，但图标仍使用 `signalStatus.iconName`；
- `.unknown/.reserved`：文案改为 `wifi_status_unknown`，图标仍使用 `signalStatus.iconName`。

`GatewayInformationHeaderView.swift:192-198` 将 controller 传入的 icon name 直接交给 `UIImage(named:)` 展示，没有二次覆盖。偏差点可以确定在 `WiFiGatewayViewController` 的 `.unavailable` 映射分支。

### 2.3 现有 `wifi_no_internet` 资源可直接使用

`SunSmart/Assets.xcassets/wifi_no_internet.imageset` 已包含完整的 1x、2x、3x 图片，asset name 为 `wifi_no_internet`。

公共 `SunSmart/Assets.xcassets` 已分别加入以下 target 的 Resources build phase：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

因此无需新增或复制图片，也无需修改 target membership。

### 2.4 当前行为来自旧设计，不是状态解析回归

历史设计 `docs/superpowers/specs/260713_1941_wifi_gateway_rssi_network_status_design.md:36-45` 明确要求：

- Internet unavailable 时显示 `No Internet`；
- 继续展示 RSSI 分级图标。

后续 V1.9 一致性设计 `docs/superpowers/specs/260721_1734_wifi_gateway_v19_conformance_fix_design.md:234-244` 继续保留该规则。

当前代码与旧设计一致，但旧设计与本次确认的新 UI 预期不一致。本次修复应视为 UI 映射要求更新，而不是修复 SDK 协议解析。

### 2.5 现有检查存在覆盖缺口

基线检查结果：

- `scripts/check_wifi_gateway_wifi_status_header.sh`：通过；
- `scripts/check_wifi_gateway_network_connectivity.sh`：通过。

但 `check_wifi_gateway_wifi_status_header.sh:89-96` 只检查：

- 存在 `No Internet` 本地化 key；
- 常规 RSSI、No Signal、Not Connected 图标映射存在。

它没有检查 `.unavailable` 必须使用 `wifi_no_internet`，甚至没有把 `wifi_no_internet` 列入必需映射，所以当前错误行为仍会通过检查。

## 3. 修复方案比较

### 方案 A：在现有 UI 状态模型中新增明确的 No Internet 状态（推荐）

做法：

- 在 `WiFiHeaderStatus` 中增加语义明确的 No Internet 映射，图标为 `wifi_no_internet`，文案 key 保持 `wifi_status_no_internet`；
- `.unavailable` 分支直接使用该状态；
- 不改变 `.normal`、`.unknown/.reserved`、RSSI failure、Not Connected、Not Configured 的现有行为；
- 扩展 focused contract，精确约束 `.unavailable` 的图标和文案组合。

优点：

- 改动范围最小，状态定义方式与现有 Excellent、Good、No Signal、Not Connected 一致；
- 图标与文案作为一个语义状态集中定义，避免未来再次出现组合错误；
- 不需要改 SDK、header view、资源、本地化或工程配置；
- 对四个共享品牌 target 自动生效。

风险：

- focused contract 属于源码契约检查，不是运行时 UI 单元测试；仍需要至少一次真机或可用 Gateway 响应确认最终视觉。

### 方案 B：只在 `.unavailable` 分支内替换 icon name

做法：

- 保留当前临时构造 `WiFiHeaderStatus` 的方式，只把图标改为 `wifi_no_internet`。

优点：

- 业务代码改动行数最少。

缺点：

- `No Internet` 语义继续散落在 switch 分支内；
- 与现有静态状态定义模式不一致；
- 后续复用或审查时更容易再次出现图标与文案组合不一致。

### 方案 C：抽取独立可单元测试的 Wi-Fi header 状态 resolver

做法：

- 将 RSSI result 与 network status 到 UI 状态的组合映射抽成独立类型；
- 为所有组合补充 XCTest。

优点：

- 运行时映射覆盖最完整；
- 状态组合更容易持续扩展。

缺点：

- 对单个图标映射问题而言改动明显偏大；
- 需要新增文件、四品牌 target membership 和更多测试接线；
- 超出本次聚焦修复的必要范围。

## 4. 推荐设计

采用方案 A。

新的有效映射为：

| Internet 状态 | RSSI 状态 | 图标 | 文案 |
|---|---|---|---|
| `.normal` | valid | 现有 RSSI 分级图标 | 现有 RSSI 分级文案 |
| `.normal` | unavailable/readFailed/reserved | `wifi_no_signal` | `No Signal` |
| `.unavailable` | 任意 | `wifi_no_internet` | `No Internet` |
| `.unknown/.reserved` | 任意 | 保持当前 RSSI/No Signal 图标 | `Unknown` |

本次只调整 `.unavailable`。`Unknown` 没有对应的新图标需求，保持当前行为，避免扩大范围。

## 5. 待确认实施计划

确认后按以下顺序 Inline Execution：

1. 先扩展 `scripts/check_wifi_gateway_wifi_status_header.sh`：
   - 要求 controller 定义 `wifi_no_internet` + `wifi_status_no_internet` 的组合状态；
   - 要求 `.unavailable` 使用该组合状态；
   - 要求 `wifi_no_internet.imageset` 的 1x、2x、3x 文件存在。
2. 运行 focused contract，确认它在当前代码上因 No Internet 图标映射错误而失败。
3. 只修改 `WiFiGatewayViewController.swift` 的 header 状态定义和 `.unavailable` 分支，使 focused contract 通过。
4. 运行以下自动验证：
   - `scripts/check_wifi_gateway_wifi_status_header.sh`
   - `scripts/check_wifi_gateway_network_connectivity.sh`
   - `git diff --check`
5. 因 controller 与公共 asset catalog 被四个品牌 target 共享，依次执行 generic iPhoneOS Debug build：
   - SunSmart
   - Archipelago
   - SLG Sync Plus
   - SylSmart
6. 记录自动验证结果，并明确区分“代码/构建通过”和“真实 Gateway + 页面视觉尚待验收”。

## 6. 预计改动范围

计划修改：

- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- `scripts/check_wifi_gateway_wifi_status_header.sh`

计划不修改：

- 本地 `NordicSigMeshSDK`
- `GatewayInformationHeaderView.swift`
- `wifi_no_internet.imageset`
- English / 简体中文本地化文件
- Xcode target 配置或依赖

## 7. 验收标准

1. `networkStatus == .unavailable` 时，页面顶部 Wi-Fi 状态固定显示 `wifi_no_internet`。
2. 同一状态的文案保持 `No Internet` / `无互联网连接`。
3. No Internet 图标不受 RSSI 强弱或 RSSI 读取失败影响。
4. `.normal` 的 Excellent、Good、Poor、Bad、No Signal 映射保持不变。
5. `.unknown/.reserved`、Not Connected、Not Configured 行为保持不变。
6. focused checks、`git diff --check` 和四个共享品牌 generic iPhoneOS build 全部通过。
7. 自动验证不替代真实 Gateway 的 `0x43/0x0F ... 0x01` 响应及页面视觉验收。
