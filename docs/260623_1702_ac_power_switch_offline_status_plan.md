# AC Power Switch Offline 状态细化分析与开发计划

## 结论

问题真实存在。

当前 AC Power Switch 顶部状态只有 Online / Offline 两种展示，Offline 只由 AC Power Switch 对应的真实 Mesh 节点 `state` 决定。因此以下两种不同场景会被合并成同一个 Offline：

- 当前 Space 没有连接任何 Proxy。
- 当前 Space 已连接 Proxy，但该 AC Power Switch 节点离线。

需求是把这两种 Offline 拆成明确文案：

- 当前 Space 没有连接任何 Proxy：显示 `Space Offline`。
- 当前 Space 已连接某个 Proxy，但 AC Power Switch 离线：显示 `Device Offline`。

## 代码事实

### AC Power Switch 身份判断

AC Power Switch 已有稳定身份判断：

- Company ID：`0x0A78`
- Product IDs：`0x2A11`、`0x2A12`
- 入口在 `PJEightKeyPowerSwitchKind`，`0x2A11` 和 `0x2A12` 会映射为 `.ac`。

因此不需要新增 CID/PID 判断，也不应在页面层重复写一套产品判断。

### 当前顶部状态来源

AC Power Switch monitor 页使用 `PJEightKeySwitchMonitorViewModel.headerState` 生成顶部状态。

当前逻辑：

- `switchData.powerSwitchKind == .ac` 时走 `acHeaderState()`。
- `acHeaderState()` 中只判断 `informationNode?.state == true`。
- true 显示 `online`。
- false 显示 `Offline`。

这说明当前 Offline 没有区分 Space Mesh 连接状态。

### Space Proxy 连接状态来源

项目已有全局 Mesh 连接状态：

- `MeshLibManager.manager.isMeshNetworkConnected`

该状态在 SDK 中是 KVO 可观察字段，项目中多个页面已经通过它判断当前 Space Mesh 是否连接，例如 Space、Devices、Group、Scene、Schedule、Device Parameter 等页面。

需求中的“当前 Space 已经连接了某个 Proxy”更贴近现有业务语义中的 `isMeshNetworkConnected`。`currentProxy` 可表示具体代理 bearer，但页面常用、稳定且可观察的 UI 状态源是 `isMeshNetworkConnected`。

## 推荐状态优先级

仅对 AC Power Switch monitor 顶部状态应用以下优先级：

1. 未 LINK 的虚拟 AC Power Switch：继续显示当前 `Unlinked` 文案。
2. 当前 Space 未连接 Proxy / Mesh 网络：显示 `Space Offline`。
3. 当前 Space 已连接 Proxy，且 AC Power Switch 节点在线：显示 `Online`。
4. 当前 Space 已连接 Proxy，但 AC Power Switch 节点离线：显示 `Device Offline`。

这样可以保留未 LINK 虚拟设备语义，同时细化真实 AC 设备离线原因。

## 开发方案

### 1. ViewModel 收口状态判断

修改 `PJEightKeySwitchMonitorViewModel`：

- 为 AC header 增加 Space 连接状态判断。
- 推荐在 ViewModel 内新增只读属性，例如 `isSpaceMeshConnected`，封装 `MeshLibManager.manager.isMeshNetworkConnected`。
- `acHeaderState()` 按“未 LINK -> Space Offline -> Online/Device Offline”的优先级生成 `HeaderState`。

预期文案：

- Online：继续复用现有 `online` key。
- Space Offline：新增国际化 key。
- Device Offline：可复用现有 `device_offline` key，因为 en/zh 已存在且含义匹配。

颜色建议：

- Online：保持当前绿色。
- Space Offline / Device Offline：保持当前灰色，避免引入额外视觉变化。

### 2. Controller 监听连接状态变化

修改 `PJEightKeySwitchMonitorVC`：

- 增加 `NSKeyValueObservation?` 保存 `MeshLibManager.manager.isMeshNetworkConnected` 观察。
- 在 `viewDidLoad()` 或单独 `addObservation()` 中注册。
- 连接状态变化时在主线程调用 `updateUI()`，刷新顶部文案。
- `deinit` 中置空 observation。

原因：当前页面只在进入、交互或局部刷新时调用 `updateUI()`；如果用户停留在 AC Power Switch 页面时 Proxy 断开/重连，顶部状态需要跟随变化。

### 3. 国际化

新增用户可见文案需要同步 English 和简体中文：

- `ac_power_switch_space_offline` 或更通用的 `space_offline`
  - English：`Space Offline`
  - 简体中文：`空间离线`

`Device Offline` 建议复用现有 key：

- `device_offline`
  - English：`Device Offline`
  - 简体中文：`设备离线`

如希望文案 key 更通用，建议使用 `space_offline`，后续其他页面可复用；如果担心影响范围，则用 `ac_power_switch_space_offline` 限定本功能。

### 4. 影响范围

本需求建议只修改：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`

不建议修改：

- Battery Power Switch 状态逻辑。
- Kinetic Switch 逻辑。
- AC Power Switch 列表图标逻辑。
- SDK 或 Mesh 连接状态底层逻辑。
- CID/PID 映射。

## 验收用例

1. AC Power Switch 未 LINK：
   - 顶部仍显示 `Unlinked`。

2. AC Power Switch 已 LINK，Space 未连接 Proxy：
   - 顶部显示 `Space Offline`。

3. AC Power Switch 已 LINK，Space 已连接 Proxy，AC 节点在线：
   - 顶部显示 `Online`。

4. AC Power Switch 已 LINK，Space 已连接 Proxy，AC 节点离线：
   - 顶部显示 `Device Offline`。

5. 停留在 AC Power Switch 页面时 Proxy 断开或重连：
   - 顶部文案自动刷新。

6. Battery Power Switch 页面：
   - 顶部电池/状态展示不变。

## 验证计划

实施后建议执行：

1. 静态检查 AC 状态判断只在 `.ac` 分支生效。
2. 检查 English / 简体中文 strings 均有新增 key。
3. 运行 `git diff --check`。
4. 运行 iPhoneOS 构建：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 待确认

建议确认以下两点后开始实现：

1. 文案 key 使用通用 `space_offline`，还是限定 `ac_power_switch_space_offline`。
2. `Device Offline` 是否复用现有 `device_offline`，我建议复用。
