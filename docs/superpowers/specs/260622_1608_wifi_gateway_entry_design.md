# WiFi Gateway 入口与菜单调整设计

## 背景

当前 Gateway 设备都通过 `DeviceType.gateway` 归类，无法仅依赖 Device Type 区分 4G Gateway 与 WiFi Gateway。业务上，`companyId = 0x0A78` 且 `productId = 0x2721` 的 Gateway 是 WiFi Gateway，需要进入支持 WiFi 配置的新 Gateway 页面；其他 CID/PID 的 Gateway 仍按 4G Gateway 处理，保持现有页面和行为。

当前仓库中，Site 页点击 Gateway 状态入口时仍固定打开旧的 `GatewayViewController`。新的 `PJNGatewayViewController` 已存在，并已包含 WiFi 配置区域、底部单行 Save、右上角菜单和部分 Gateway 1.5 资源，但尚未接入正式入口。

## 目标

- WiFi Gateway：`0x0A78 / 0x2721` 从 Site 进入新 `PJNGatewayViewController`。
- 4G Gateway：除上述 CID/PID 外的 Gateway 继续进入旧 `GatewayViewController`，保持现状。
- WiFi Gateway 页面底部不展示 Delete 按钮，Save 独占整行。
- WiFi Gateway 右上角展示菜单项：WiFi DFU、Delete、Information、Identify、Diagnosis。
- WiFi DFU、Information、Diagnosis 暂时只作为占位菜单项，不跳转页面、不发送命令、不执行功能。
- Delete 复用当前 Gateway 删除行为。
- Identify 发送一次 SIG Mesh identify 到当前 Gateway node。

## 非目标

- 不改 `DeviceType.gateway` 的枚举或分类语义。
- 不在本轮实现 WiFi DFU、Information、Diagnosis 的真实功能。
- 不新增 SDK 公共 API。
- 不调整 4G Gateway 页面的 UI、删除流程、APN、服务器授权、关联 Space 等现有逻辑。
- 不扩大到 Add Device、Restore、Cloud Sync、Import/Export 的功能改造。

## 方案选择

采用方案 A：在 App 侧建立一个窄范围的 WiFi Gateway 判断，条件为 `companyIdentifier == 0x0A78 && productIdentifier == 0x2721`。Site 入口根据这个判断选择页面：

- WiFi Gateway 打开 `PJNGatewayViewController`。
- 其他 Gateway 打开 `GatewayViewController`。

这个方案改动面最小，能保留 4G Gateway 的现有行为，同时让 WiFi Gateway 复用已经存在的新页面结构。相比把类型下沉到 SDK 或扩展 `devices_config.json` schema，本方案不需要 SDK 切换、数据库迁移或跨 App 兼容设计。

## 架构设计

### Gateway 类型判断

在 App 的 `Node` 扩展层新增一个单一事实源，用于判断当前 node 是否为 WiFi Gateway。判断只依赖 composition 中已有的 CID/PID：

- CID：`0x0A78`
- PID：`0x2721`

如果 CID 或 PID 缺失，结果为 false，默认走 4G Gateway 旧页面，避免未知 Gateway 被误判为 WiFi Gateway。

### Site 入口分流

Site Gateway 状态点击入口保留现有权限校验和无权限提示。拿到 `Gateway` 后，根据 `gateway.node` 的 WiFi Gateway 判断分流：

- true：创建 `PJNGatewayViewController(site:gateway:)`
- false：创建 `GatewayViewController(site:gateway:)`

4G Gateway 的旧 controller 初始化失败处理保持不变。WiFi Gateway 页面不需要旧 controller 的可选初始化失败分支。

### WiFi Gateway 页面菜单

`PJNGatewayViewController` 的右上角菜单仅对 WiFi Gateway 入口使用，菜单顺序固定为：

1. WiFi DFU
2. Delete
3. Information
4. Identify
5. Diagnosis

菜单行为：

- WiFi DFU：使用 Information 图标，占位不执行功能。
- Delete：沿用当前 `PJNGatewayViewController` 内已有删除流程，包含确认弹窗、云端删除、权限检查、mesh node 删除和页面关闭。
- Information：使用 Information 图标，占位不执行功能。
- Identify：调用当前 node 的 SIG Mesh identify。
- Diagnosis：使用 Information 图标，占位不执行功能。

Delete 菜单项继续受现有 `site.deviceOperates.contains(.delete)` 显示条件约束；执行删除时继续检查 edit 权限，避免改变现有权限语义。

### 底部 Save

`PJNGatewayBottomSaveView` 当前已经只有 Save 按钮并占满整行。WiFi Gateway 接入新页面后即可满足“去掉底部 DELETE 按钮，让 SAVE 独占一整行”。本轮只确认该页面入口切换后不再进入旧双按钮底部的 4G 页面，不额外重构底部组件。

## 数据流

1. Site Gateway 状态入口读取当前选中的 `Gateway`。
2. 入口复用现有无权限判断。
3. 根据 `Gateway.node.companyIdentifier/productIdentifier` 判断页面类型。
4. WiFi Gateway 进入 `PJNGatewayViewController`，渲染 WiFi 配置、新菜单和单行 Save。
5. 4G Gateway 进入 `GatewayViewController`，保留 APN、4G 信号、旧底部按钮和当前删除流程。

当前未提交的 `devices_config.json` 中已加入 `0x0A78 / 0x2721` Gateway 配置。本设计不覆盖该修改，只基于它让该设备继续被识别为 Gateway。

## 权限与错误处理

- Site 入口无权限判断保持现状。
- Delete 的确认、云端注册删除、关联 Space 权限检查、失败 HUD、force delete 提示全部沿用现有 Gateway 删除流程。
- Identify 为 fire-and-forget，只发送一次，不新增成功或失败提示。
- WiFi DFU、Information、Diagnosis 不执行功能，因此不新增错误处理。
- CID/PID 缺失或无法识别时按 4G Gateway 处理。

## 测试与验收

### 静态检查

- 运行 `git diff --check`。

### 构建验证

- 使用 iPhoneOS 构建验证 `SunSmart` scheme：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

### 手工验证

- `0x0A78 / 0x2721` Gateway：从 Site Gateway 状态入口进入新 WiFi Gateway 页面。
- 其他 Gateway：从 Site Gateway 状态入口仍进入旧 4G Gateway 页面。
- WiFi Gateway 页面底部只显示整行 Save。
- WiFi Gateway 菜单显示五个选项，顺序为 WiFi DFU、Delete、Information、Identify、Diagnosis。
- 点击 WiFi DFU、Information、Diagnosis 后不跳转、不发送命令。
- 点击 Identify 后只发送一次 SIG Mesh identify。
- 点击 Delete 后沿用现有 Gateway 删除确认和删除流程。

## 风险与边界

- 新页面已有 WiFi 配置 UI，但真实 WiFi 配置命令不在本轮实现范围内。
- `PJNGatewayViewController` 当前已有部分菜单项真实跳转逻辑，本轮需要将占位项收口为空操作，避免提前开放未确认功能。
- 如果未来还有更多 WiFi Gateway PID，应只扩展同一个 App 侧判断，不在入口散落多个 PID 条件。
- 如果后续多个 App 或 SDK 消费方都需要 Gateway 类型区分，再评估是否把该判断下沉到 SDK。
