# Device 信息与灯详情文案国际化分析及修复计划

## 背景

用户点名检查以下文案在 App 中是否未正确国际化：

- 产品id
- address
- Version Identifier
- Set Proxy
- Reboot
- Relay

本次仅做代码事实分析和修复规划，未修改源码。

## 结论

真实存在国际化问题，但每个文案的问题类型不同：

| 文案 | 当前状态 | 判断 |
| --- | --- | --- |
| 产品id / PID | `DeviceInformationViewController` 使用 `"PID".localizedString`；英文为 `PID`，中文为 `产品id` | 已走国际化，但中文翻译大小写不规范，建议改为 `产品ID` 或按产品要求保留 `PID` |
| address | 代码使用 `"address".localizedString`；英文有 key，中文缺少 `address` key | 真实未完整国际化。中文环境会 fallback 为 `address` |
| Version Identifier | 信息页直接硬编码 `Version Identifier` | 真实未国际化 |
| Set Proxy | 灯详情右上菜单直接硬编码 `Set Proxy` | 真实未国际化 |
| Reboot | 灯详情右上菜单直接硬编码 `Reboot` | 真实未国际化 |
| Relay | 灯详情页 Relay 开关 label 直接硬编码 `Relay` | 真实未国际化 |

## 代码证据

- `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift`
  - `PID`：第 143 行使用 `"PID".localizedString`
  - `address`：第 145 行使用 `"address".localizedString`
  - `Version Identifier`：第 147 行硬编码
- `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - `Set Proxy`：第 364 行硬编码
  - `Reboot`：第 389 行硬编码
  - `Relay`：第 1273 行硬编码
- `SunSmart/en.lproj/Localizable.strings`
  - 有 `"PID" = "PID";`
  - 有 `"address" = "Address";`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 有 `"PID" = "产品id";`
  - 缺少 `"address"`
- `String.localizedString` 只是 `NSLocalizedString(self, comment: "")` 的封装；缺失 key 时会显示 key 本身。

## 影响面

- `address` key 不只影响设备信息页，也影响 Gateway 信息复制和 Gateway 信息 cell 标题：
  - `GatewayViewController.copyGateway`
  - `GatewayViewController.InfoCellType.address`
- `Set Proxy`、`Reboot`、`Relay` 当前只在 `DeviceLightViewController` 的灯详情页发现直接命中点。
- 本次不涉及菜单图标、菜单顺序、权限判断、Mesh 命令发送逻辑或 `supportsLightDetailRelayControl` 能力判断。

## 推荐方案

采用最小修复：

1. 在 `DeviceInformationViewController` 中将 `Version Identifier` 改为新 key，例如 `version_identifier.localizedString`。
2. 在 `DeviceLightViewController` 中将：
   - `Set Proxy` 改为 `set_proxy.localizedString`
   - `Reboot` 改为 `reboot.localizedString`
   - `Relay` 改为 `relay.localizedString`
3. 在 `SunSmart/en.lproj/Localizable.strings` 和 `SunSmart/zh-Hans.lproj/Localizable.strings` 同步补齐 key：
   - `address`: `Address` / `地址`
   - `version_identifier`: `Version Identifier` / `版本标识符`
   - `set_proxy`: `Set Proxy` / `设置代理`
   - `reboot`: `Reboot` / `重启`
   - `relay`: `Relay` / `中继`
4. `PID` 不属于硬编码问题；建议只把中文值从 `产品id` 调整为 `产品ID`。如果产品希望信息页显示协议字段名，也可以保持中英文都显示 `PID`，这需要产品确认。

## 可选方案

### 方案 A：最小补 key

只修上述命中点和 strings。风险最低，影响面清晰。推荐。

### 方案 B：复用已有近义 key

尝试复用 `proxy`、`version` 等已有 key。改动更少，但语义不完全一致，例如 `Set Proxy` 是动作，`proxy` 是名词，不推荐。

### 方案 C：顺手扫描全设备页硬编码

扩大范围清理更多硬编码。能提升整体质量，但容易引入无关改动，不符合本次聚焦要求，不推荐本轮做。

## 验证计划

1. 用 `rg` 确认上述硬编码不再直接出现在 UI 构造处。
2. 用 `rg` 确认新增 key 在英文和中文 `Localizable.strings` 中均存在。
3. 运行 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 验证主 target 编译。
4. 如修改 strings 后担心品牌 target 资源影响，再检查 `Archipelago`、`SLG Sync Plus`、`SylSmart` 对主 bundle strings 的引用是否仍按现有方式工作；本次预计只改 `SunSmart` 主 strings，不改 target 配置。

## 待确认

请确认 `PID` 中文显示采用哪一种：

- 推荐：`产品ID`
- 保守：`PID`

其余文案建议按推荐方案 A 修复。
