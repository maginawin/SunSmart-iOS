# WiFi Gateway WiFi Firmware Update 设计

## 1. 目标

为 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 实现 WiFi 固件查询页面壳层：从 Gateway 右上角 `WiFi DFU` 菜单进入 `WiFi Firmware Update`，查询正式或 Beta WiFi 固件、查看历史版本，并展示后续升级入口。

本阶段不实现固件下载、固件包解析、缓存、传输、进度、失败恢复或升级完成校验。

## 2. 已确认需求

- 页面标题英文精确显示为 `WiFi Firmware Update`。
- 最新固件只在进入页面后获取，不在 Gateway 页面预取。
- 最新版本请求使用 CID `0x0A78`、PID `0x2721`、`customerId=wifi`。
- 连续点击云图标后展示 `Beta Testing Environment`。
- 输入密码 `1314` 后查询 Beta 固件，请求额外增加 `profile=dev`，并保持 `customerId=wifi`。
- WiFi 页面的 Beta 弹窗隐藏 `Import from local`；普通 Firmware Version 页面继续保留。
- `Current target version` 固定显示 `1.0.0`。
- WiFi 页面隐藏本地固件删除按钮，不读取或修改 Mesh 固件缓存。
- 底部按钮英文精确显示为 `UPGRADE`。
- 仅服务器版本高于 `1.0.0` 时启用 `UPGRADE`；普通与 Beta 固件使用相同规则。
- 点击已启用的 `UPGRADE` 只显示现有 `under_development` 提示，不执行其他动作。
- Firmware version history 使用现有历史 API，并传递 `customerId=wifi`；Beta 状态下额外传递 `profile=dev`。
- 后续提供 WiFi 当前固件版本获取方式后，只替换 `Current target version` 的来源，不改变页面结构。

## 3. 现有代码事实

### 3.1 真实入口

`SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift` 中的 `moreClick()` 是 WiFi Gateway 右上角菜单的真实组装点。`WiFi DFU` 当前只显示 `under_development`，因此本次直接把该回调改为进入新页面，不修改 Site 到 Gateway 的既有路由。

### 3.2 共享页面

`SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift` 已包含目标 UI、最新版本查询、Beta 切换、历史页面入口、网络错误和 Retry 状态。

该类虽然可以继承，但页面标题、请求方法、Beta 状态、历史入口、按钮动作、UI 更新等关键实现为 `private`，当前无法由子类安全定制。设计需要把差异收敛为少量可覆写 hook，而不是复制整个控制器。

### 3.3 API

网络枚举已提供两个接口：

- 最新版本：`/sitespace/ota/latest`
- 历史版本：`/sitespace/ota/history`

两个接口都已支持字符串 `customerId` 参数；测试环境通过 `profile=dev` 区分。因此历史查询不需要服务器新增 API。

## 4. 方案选择

### 4.1 采用方案：父类窄扩展点 + WiFi 专用子类

保留 `FirmwareVersionViewController` 的共享布局和状态机，只开放当前差异需要的配置与动作。新增 `WiFiFirmwareUpdateViewController` 继承父类并固定 WiFi 请求身份与页面行为。

该结构让当前页面最大限度复用旧 UI，同时为后续完全不同的 WiFi `UPGRADE` 流程保留独立控制器边界。

### 4.2 不采用单控制器配置分支

把全部差异作为一个配置对象注入旧页面，短期文件较少，但后续 Mesh Download 与 WiFi Upgrade 会在同一控制器内形成越来越多的条件分支，不符合后续流程独立发展的方向。

### 4.3 不采用页面复制

复制现有控制器会同时复制布局、网络状态、Beta、历史导航、Mesh ZIP 和缓存逻辑，后续共同 UI 修复容易漂移，因此不采用。

## 5. 组件设计

### 5.1 `FirmwareVersionViewController`

父类继续保留现有默认行为：

- 标题 `Firmware Version`；
- 请求 `customerId=00`；
- 当前目标版本来自本地 Mesh 固件缓存；
- 显示缓存删除按钮；
- Beta 弹窗显示本地导入；
- 底部显示 `DOWNLOAD`；
- 点击后下载、解析并缓存 Mesh DFU ZIP。

只增加以下职责明确的扩展点：

- 页面标题；
- 固件请求使用的字符串 `customerId`；
- 当前目标版本展示值；
- 是否展示缓存删除按钮；
- 是否展示 Beta 本地导入；
- 底部主按钮标题；
- 底部主按钮动作。

请求、UI 状态和 Retry 仍由父类统一管理。默认值必须保持现有 BLE/Mesh 行为，现有调用方不需要修改初始化方式。

### 5.2 `WiFiFirmwareUpdateViewController`

新增子类固定以下行为：

- PID 为 `0x2721`；
- 页面标题为本地化后的 `WiFi Firmware Update`；
- 请求 `customerId=wifi`；
- 当前目标版本为 `1.0.0`；
- 不显示删除按钮；
- Beta 弹窗不显示本地导入；
- 主按钮标题为本地化后的 `UPGRADE`；
- 主按钮动作只显示 `under_development`。

子类不调用 `FirmwareData.load`、`FirmwareData.save`、`FirmwareData.delete`、`ZipHandler` 或文档选择器。

### 5.3 `BetaTestingAlertView`

增加“是否显示本地导入”的初始化配置，默认值保持显示。WiFi 页面传入隐藏，普通 Firmware Version 页面继续使用默认值。

隐藏导入入口时，仅改变 import button 的可见性，不改变密码输入、错误提示、关闭和键盘行为。

### 5.4 `FirmwareVersionHistoryController`

初始化参数增加字符串 `customerId`，默认值为 `00`。历史请求使用该值：

- 普通 Firmware Version：`customerId=00`；
- WiFi Firmware Update：`customerId=wifi`；
- Beta 状态：在对应 `customerId` 基础上增加 `profile=dev`。

历史列表布局、空态、展开行为和错误提示保持不变。

### 5.5 `WiFiGatewayViewController`

将 `WiFi DFU` 菜单回调从提示 `under_development` 改为 push `WiFiFirmwareUpdateViewController`。入口只适用于当前 WiFi Gateway 页面，不改变其他 Gateway 的菜单和 Firmware update via BLE 入口。

## 6. 数据流

### 6.1 正式版本

1. 用户点击 `WiFi DFU`。
2. App push `WiFi Firmware Update`。
3. 新页面在 `viewDidLoad` 后请求 `/sitespace/ota/latest`。
4. 请求参数为 `manufacturerId=0A78`、`deviceType=2721`、`customerId=wifi`。
5. 页面解析并展示版本、大小、发布日期和描述。
6. 使用数值版本比较判断服务器版本是否高于固定版本 `1.0.0`。
7. 仅高于时启用 `UPGRADE`。

### 6.2 Beta 版本

1. 用户连续点击云图标。
2. App 显示不含本地导入入口的 `Beta Testing Environment`。
3. 密码不是 `1314` 时沿用现有错误提示。
4. 密码为 `1314` 时清除当前服务器展示数据并重新请求最新版本。
5. 请求保持 `customerId=wifi`，额外增加 `profile=dev`。
6. 页面继续使用固定版本 `1.0.0` 做启用判断。

### 6.3 历史版本

1. 用户点击右上角 Firmware version history。
2. 页面把 PID `0x2721`、`customerId=wifi` 和当前测试状态传给历史控制器。
3. 历史控制器请求 `/sitespace/ota/history`。
4. 普通状态不传 `profile`，Beta 状态传 `profile=dev`。

## 7. 字符串 `customerId` 的模型边界

请求层已经支持字符串 `customerId`，但现有 `FirmwareServerData.customId` 和 `FirmwareData.customId` 是 `UInt16`。`wifi` 不能无损转换成该数值类型。

本阶段采用以下边界：

- `wifi` 只作为最新和历史 API 的请求身份；
- WiFi 页面不把响应保存为 `FirmwareData`；
- WiFi 页面不使用响应模型中的数值 `customId` 进行下载、缓存或删除；
- 不修改现有数据库字段和 Mesh 固件缓存 schema；
- 后续真实升级设计根据 WiFi 固件包格式决定是否增加独立的字符串身份模型。

该边界避免为了只读页面提前扩大数据库迁移范围，也不会把 WiFi 固件误存为 Mesh `customId=0` 固件。

## 8. UI 状态与错误处理

### 8.1 成功且有更高版本

- 展示 `New version found` 状态和服务器固件详情；
- `Current target version` 显示 `1.0.0`；
- `UPGRADE` 启用；
- 点击后显示 `under_development`。

### 8.2 成功但版本不高于 `1.0.0`

- 沿用现有“已是最新版本”状态；
- 隐藏新版本详情；
- `UPGRADE` 禁用。

### 8.3 服务器无对应固件

- 沿用现有 resource-not-found 展示规则；
- `UPGRADE` 禁用。

### 8.4 网络或解析失败

- 沿用现有网络错误展示和 Retry 按钮；
- `UPGRADE` 禁用；
- Retry 继续使用当前正式/Beta 请求身份，不回退为 `customerId=00`。

### 8.5 历史列表

- 空数组沿用 `No record` 空态；
- 请求失败沿用现有错误提示；
- 正式/Beta 状态不在历史页面内切换，只继承来源页面的状态。

## 9. 国际化与 target 边界

所有新增或修改的用户可见文案必须覆盖 English 和简体中文：

- `WiFi Firmware Update`；
- `UPGRADE`；
- `WiFi DFU` 菜单若从硬编码调整为本地化，也必须同时补齐两种语言。

`under_development`、Firmware version history、Beta Testing Environment 和既有错误文案优先复用现有 key。

新增控制器、共享 UI 修改、本地化和工程引用需要同步检查 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。不得修改其他品牌的默认 Firmware Version 行为。

## 10. 验证设计

### 10.1 静态契约

增加聚焦的 WiFi Firmware Update 检查，至少覆盖：

- WiFi 菜单 push 新控制器；
- WiFi 最新请求使用 `customerId=wifi`；
- WiFi 历史请求使用 `customerId=wifi`；
- Beta 请求继续使用 `wifi` 并追加测试环境；
- 固定版本为 `1.0.0`；
- WiFi 页面隐藏删除和本地导入；
- `UPGRADE` 点击只显示 `under_development`；
- 普通 Firmware Version 的默认 `customerId=00`、`DOWNLOAD` 和导入能力仍存在。

### 10.2 手工 UI 验收

- 从正确 WiFi Gateway 进入页面，确认标题、固定版本和按钮文案；
- 验证高于、等于、低于 `1.0.0` 的按钮状态；
- 验证无固件、网络失败和 Retry；
- 验证连续点击、错误密码、密码 `1314` 和隐藏本地导入；
- 验证正式与 Beta 历史列表请求身份；
- 验证普通 Firmware Version 的下载、缓存删除和本地导入不变。

### 10.3 构建

先运行聚焦静态检查和 `git diff --check`，再依次执行四个品牌 scheme 的 Debug iPhoneOS 构建，使用 generic iOS destination 并禁用代码签名。多个 scheme 串行执行，避免共享 DerivedData 的 `build.db` 锁冲突。

## 11. 明确不在本阶段实现

- WiFi 当前固件版本的设备侧查询；
- WiFi 固件下载、签名、校验、解压或缓存；
- App 到 Gateway 的固件传输协议；
- 升级进度、取消、超时、失败重试和断点恢复；
- Gateway 掉电、断网、离开页面或 App 进入后台的升级策略；
- 升级完成后的版本读取与结果确认；
- Mesh Firmware 数据库 schema 调整。

这些能力在后续 `UPGRADE` 流程需求明确后单独设计。

## 12. 验收标准

满足以下条件即视为本阶段完成：

1. 只有 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 菜单进入新页面。
2. 页面进入后才查询 `0A78/2721/wifi` 最新固件。
3. 普通与 Beta 最新/历史请求的 `customerId` 均正确，Beta 额外使用测试 profile。
4. 页面固定显示当前目标版本 `1.0.0`，无删除和本地导入入口。
5. `UPGRADE` 按版本比较结果启用，点击只显示 `under_development`。
6. 普通 Firmware Version 的 `00` 请求、DOWNLOAD、缓存删除和本地导入行为不变。
7. 四个品牌 target 均通过 Debug iPhoneOS 构建。
