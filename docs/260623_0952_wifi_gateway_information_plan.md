# WiFi Gateway Information 页面开发方案

## 背景

WiFi Gateway 右上角菜单中的 Information 目前已经展示菜单项，但点击后没有动作。普通 light 设备的 Information 菜单会跳转到 `DeviceInformationViewController`，该页面展示设备信息、group 和 scene。

本次需求是：WiFi Gateway 点击 Information 后跳转到 WiFi Gateway 的 Information 页面；页面内容与普通 light 设备一致，但不展示 group 和 scene。

## 当前代码事实

- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift` 中 Information 菜单项目前是空闭包。
- 普通 light 设备入口会 push `DeviceInformationViewController(node:)`。
- `DeviceInformationViewController` 当前支持通过参数隐藏 scene，但不支持隐藏 group。
- `DeviceInformationViewController` 的设备信息内容已经包含 name、MAC、PID、address、Version Identifier、model、device_type、firmware、signal_strength 等普通 light Information 页面内容。

## 方案选项

### 方案 A：扩展 `DeviceInformationViewController` 的 section 配置

给 `DeviceInformationViewController` 增加一个默认开启的 group 显示参数，让现有调用保持不变。WiFi Gateway 调用时关闭 group 和 scene，只保留 deviceInfo section。

优点：

- 复用普通 light Information 页面，满足“内容与普通 light 设备一样”的要求。
- 改动最小，只影响一个通用页面的可配置能力和 WiFi Gateway 菜单闭包。
- 现有 light、switch、EFC 等调用默认值不变，回归风险较低。

缺点：

- 通用页面会多一个初始化参数，需要保持命名清晰，避免后续调用误用。

### 方案 B：为 WiFi Gateway 单独创建 Information 页面

新建一个 WiFi Gateway 专用 Information controller，复制或重组普通设备信息行，只不添加 group 和 scene。

优点：

- WiFi Gateway 页面完全隔离，未来若网关信息展示差异很大，扩展更自由。

缺点：

- 与普通 light 信息页产生重复逻辑，后续字段、RSSI、固件信息展示规则变化时更容易漂移。
- 本次需求只要求隐藏 group 和 scene，单独建页偏重。

### 方案 C：复用现有 `showsSceneSection`，通过传空 group 文案隐藏视觉内容

不改 section 配置，只尝试通过空文案或 header 高度规避 group 展示。

优点：

- 表面改动少。

缺点：

- group section 仍存在，只是被弱化，不符合“不要展示 group 和 scene”。
- 容易产生空白 header 或点击行为不一致，不推荐。

## 推荐方案

推荐采用方案 A。

具体做法：

1. 修改 `DeviceInformationViewController` 初始化参数，新增默认值为开启的 group section 控制项。
2. 根据 group 和 scene 两个布尔配置生成 `sections`，普通设备默认仍是 deviceInfo、group、scene。
3. 修改 WiFi Gateway Information 菜单闭包，点击后 push `DeviceInformationViewController`，关闭 group 和 scene。
4. 扩展现有静态校验脚本，验证 WiFi Gateway Information 菜单不再是空闭包，并且跳转到 `DeviceInformationViewController` 时关闭 group 和 scene。

## 验证计划

- 运行 `bash scripts/check_wifi_gateway_menu_icons.sh`，确认菜单图标、Identify 命令和 Information 跳转规则符合预期。
- 运行 `git diff --check`。
- 运行 iPhoneOS 构建：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- 因本次会修改共享页面 `DeviceInformationViewController`，如改动进入实现阶段，还应检查相关品牌 target 的 iPhoneOS 构建，至少覆盖 `Archipelago`、`SLG Sync Plus`、`SylSmart`。

## 范围边界

- 不修改 WiFi DFU、Delete、Identify、Diagnosis 的既有行为。
- 不新增 WiFi Gateway 专属信息字段。
- 不改普通 light、switch、EFC 等已有 Information 入口的默认展示。
- 不触碰 4G Gateway legacy 页面。
