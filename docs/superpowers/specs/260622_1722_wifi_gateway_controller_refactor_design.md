# WiFi Gateway Controller 重构设计

## 背景

当前 Gateway 设备都通过 `DeviceType.gateway` 归类，无法仅依赖 Device Type 区分 4G Gateway 与 WiFi Gateway。业务上，`companyId = 0x0A78` 且 `productId = 0x2721` 的 Gateway 是 WiFi Gateway，需要支持配置网关 WiFi 信息；其他 CID/PID 的 Gateway 仍视为 4G Gateway，通过自身 4G 卡联网，不需要配置 WiFi 信息。

此前方案计划从 Site 入口把 WiFi Gateway 路由到 `PJNGatewayViewController`。需求已变更：后续不再使用 `PJNGatewayViewController`，也不再保留 `PJNGateway` 相关源码与资源。WiFi Gateway 应基于现有 `GatewayViewController` 增量实现，4G Gateway 继续直接使用 `GatewayViewController`。

## 目标

- 继续用 CID/PID 区分 WiFi Gateway 与 4G Gateway：
  - WiFi Gateway：`companyId = 0x0A78` 且 `productId = 0x2721`
  - 4G Gateway：其他 CID/PID 的 Gateway
- Site Gateway 入口按 Gateway 类型分流：
  - 4G Gateway：进入 `GatewayViewController`
  - WiFi Gateway：进入新增 `WiFiGatewayViewController`
- `WiFiGatewayViewController` 继承 `GatewayViewController`，只覆盖 WiFi Gateway 差异。
- WiFi Gateway 底部去掉 `DELETE`，让 `SAVE` 独占整行。
- WiFi Gateway 导航栏右侧增加菜单按钮，菜单项为：
  - `WiFi DFU`：使用 Information 图标，暂不实现功能
  - `Delete`：复用当前 4G Gateway 删除功能
  - `Information`：暂不实现功能
  - `Identify`：发送一次 SIG Mesh identify 给网关设备
  - `Diagnosis`：使用 Information 图标，暂不实现功能
- 删除全部 `PJNGateway` 相关源码、资源、工程引用和未使用本地化文案。

## 非目标

- 不改 `DeviceType.gateway` 的枚举或分类语义。
- 不在本轮实现 WiFi DFU、Information、Diagnosis 的真实功能。
- 不新增 Auth 信息。
- 不新增 SDK 公共 API。
- 不改 Add Device、Restore、Cloud Sync、Import/Export 的业务行为。
- 不改 4G Gateway 的 APN、服务器授权、关联 Space、删除确认、修复、保存等既有行为。

## 方案选择

采用方案 A：以 `GatewayViewController` 为父类，新增 `WiFiGatewayViewController` 承载 WiFi Gateway UI 与行为差异。

这个方案保留 4G Gateway 的现有页面与逻辑，同时避免继续维护 `PJNGatewayViewController` 这一套独立页面、资源和 ViewModel。由于 `GatewayViewController` 当前很多成员和动作是 `private`，实现时需要对父类做少量受控开放或增加可覆盖 hook，但不复制整份 Gateway 页面逻辑。

不采用复制 `GatewayViewController` 的方案。复制能绕开访问控制问题，但会带来删除、保存、关联 Space、网络状态、修复等逻辑的长期分叉，后续 4G 和 WiFi Gateway bugfix 容易漂移。

## 架构设计

### Gateway 类型判断

在 App 的 `Node` 扩展层保留单一事实源，用于判断当前 node 是否为 WiFi Gateway。判断只依赖 composition 中已有的 CID/PID：

- CID：`0x0A78`
- PID：`0x2721`

如果 CID 或 PID 缺失，结果为 false，默认按 4G Gateway 处理，避免未知 Gateway 被误判为 WiFi Gateway。

### Site 入口分流

Site Gateway 状态入口保留现有权限校验和无权限提示。拿到 `Gateway` 后，根据 `gateway.node` 的 WiFi Gateway 判断分流：

- WiFi Gateway：创建 `WiFiGatewayViewController(site: gateway:)`
- 4G Gateway：创建 `GatewayViewController(site: gateway:)`

旧的 `PJNGatewayViewController` 入口引用全部移除。

### 父类最小改造

`GatewayViewController` 需要保留 4G Gateway 默认行为，并向子类开放少量扩展点：

- 导航栏配置 hook：默认继续显示现有关闭按钮；WiFi 子类改为右侧菜单按钮，并保留关闭入口。
- 底部按钮配置 hook：默认继续使用当前双按钮编辑模式；WiFi 子类使用 Save-only 模式。
- 删除动作复用入口：把当前 `deleteBtnAction` 背后的删除流程开放给子类调用，避免复制 4G Gateway 删除逻辑。
- 关闭页面入口：把当前关闭逻辑开放给子类，用于 WiFi 页面导航栏布局调整后继续关闭页面。

这些改动只改变可见性或增加 hook，不改变 4G Gateway 的默认执行路径。

### 底部 Save-only 模式

在 `DeviceBottomBtnView` 增加一个明确的 Save-only 展示方法：

- 隐藏 `deleteBtn`
- 隐藏 `createBtn`
- 显示 `saveBtn`
- 让 `saveBtn` 约束撑满底部按钮区域

`GatewayViewController` 默认仍调用现有编辑模式。`WiFiGatewayViewController` 在需要展示底部操作区时调用 Save-only 模式，避免每次刷新数据后又回到双按钮布局。

### WiFi Gateway 菜单

`WiFiGatewayViewController` 右上角使用菜单按钮展示固定菜单项，顺序为：

1. `WiFi DFU`
2. `Delete`
3. `Information`
4. `Identify`
5. `Diagnosis`

菜单行为：

- `WiFi DFU`：使用 Information 图标，占位不执行功能。
- `Delete`：调用父类开放的删除流程，与 4G Gateway 当前 DELETE 行为一致。
- `Information`：占位不执行功能。
- `Identify`：调用当前 node 的 SIG Mesh identify，只发送一次。
- `Diagnosis`：使用 Information 图标，占位不执行功能。

`WiFi DFU` 和 `Diagnosis` 不复用即将删除的 Gateway1.5 资源，统一使用项目已有 Information 图标。

### PJNGateway 清理

本轮实现需要移除 `PJNGateway` 相关内容：

- 删除 `SunSmart/Main/Device/Device1.5/NGateWay/` 下的源码、View、ViewModel、Model、Add/Restore 容器和说明文档。
- 删除 `SunSmart/Assets.xcassets/Gateway1.5/` 资源。
- 删除 Xcode project 中所有 `PJNGateway`、`NGateWay`、`Gateway1.5` 文件引用和 target source build phase 引用。
- 删除确认未使用的 `ngateway_*` 本地化文案。
- 更新 `Device1.5` 说明中关于 `NGateWay` 的残留引用。

由于会修改资源和工程配置，需要同步检查 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 等相关 target 是否仍有引用残留。

## 数据流

1. Site Gateway 状态入口读取当前选中的 `Gateway`。
2. 入口复用现有无权限判断。
3. 根据 `Gateway.node.companyIdentifier/productIdentifier` 判断页面类型。
4. WiFi Gateway 进入 `WiFiGatewayViewController`，渲染现有 Gateway 信息、WiFi Gateway 菜单和 Save-only 底部区域。
5. 4G Gateway 进入 `GatewayViewController`，保留 APN、4G 信号、旧底部按钮和当前删除流程。

当前未提交的 `devices_config.json` 中已有 `0x0A78 / 0x2721` Gateway 配置。本设计不覆盖该修改，只基于它让该设备继续被识别为 Gateway。

## 权限与错误处理

- Site 入口无权限判断保持现状。
- WiFi Gateway Delete 调用父类删除流程，沿用现有权限检查、确认弹窗、云端删除、mesh node 删除、失败提示和页面关闭逻辑。
- Identify 为 fire-and-forget，只发送一次，不新增成功或失败提示。
- WiFi DFU、Information、Diagnosis 不执行功能，因此不新增错误处理。
- CID/PID 缺失或无法识别时按 4G Gateway 处理。

## 测试与验收

### 静态检查

- 运行 `git diff --check`。
- 全仓搜索确认没有业务代码继续引用 `PJNGateway`、`NGateWay`、`Gateway1.5`。

### 构建验证

- 使用 iPhoneOS 构建验证 `SunSmart` scheme：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

如工程引用清理影响共享 target，再补充检查其他品牌 scheme 是否仍存在 project reference 或资源引用错误。

### 手工验证

- `0x0A78 / 0x2721` Gateway：从 Site Gateway 状态入口进入 WiFi Gateway 页面。
- 其他 Gateway：从 Site Gateway 状态入口仍进入 4G Gateway 页面。
- 4G Gateway 页面保持原底部按钮、导航栏和删除流程。
- WiFi Gateway 页面底部只显示整行 Save。
- WiFi Gateway 菜单显示五个选项，顺序为 WiFi DFU、Delete、Information、Identify、Diagnosis。
- 点击 WiFi DFU、Information、Diagnosis 后不跳转、不发送命令。
- 点击 Identify 后只发送一次 SIG Mesh identify。
- 点击 Delete 后沿用现有 Gateway 删除确认和删除流程。

## 风险与边界

- `GatewayViewController` 当前私有成员较多，父类 hook 需要控制在导航、底部布局、删除与关闭入口，不应顺手扩大其他业务逻辑访问范围。
- 删除 PJNGateway 资源会修改 project 文件和资源目录，必须做引用残留检查。
- 如果未来还有更多 WiFi Gateway PID，应只扩展同一个 App 侧判断，不在入口散落多个 PID 条件。
- 如果后续多个 App 或 SDK 消费方都需要 Gateway 类型区分，再评估是否把该判断下沉到 SDK。
