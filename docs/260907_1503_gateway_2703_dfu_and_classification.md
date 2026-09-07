# PID 0x2703 的 4G DFU 接入与网关识别分析

- 日期：2026-09-07
- 工作区：`sun-smart-worktrees/fix`
- 基线提交：`fd520c93`
- 本文记录本次实现后的行为；此前 `260907_1457_gateway_4g_dfu_support_analysis.md` 是修改前的分析快照。

## 本次行为变化

在 Gateway 页面点击 `4G DFU` 时，PID `0x2703` 进入共享固件升级页面，标题为 `4G Firmware Update` / `4G 固件更新`。其他 4G PID 继续提示开发中；WiFi 网关原有入口保持不变。

实现范围：

- `GatewayMenuPolicy.supportsFourGDFU` 单独限制开放的 PID，避免将“进入 4G 页面”当作“支持 DFU”。此入口在非 WiFi Gateway 页面内使用，按本次要求判断 PID `0x2703`，未新增 CID 限制。
- `GatewayViewController.performGatewayDFUAction` 在允许升级时创建共享控制器，保护模态栈并跳转。
- `GatewayFirmwareDFUProfile` 区分固件类型、请求设备类型、客户标识、标题和会话命名空间。
- 4G 固件最新版本及历史查询使用设备类型 `2703`、客户标识 `4g`；厂商仍使用现有网络接口默认值 `0A78`。
- 4G Start 原样使用服务器最新固件响应的 `data.url`，不重建签名 URL，不降级 HTTPS；空 URL 报错。WiFi 继续根据当前区域和 `filename` 构造原有 HTTP 下载地址。
- 4G 与 WiFi 共用现有当前版本读取、Start、状态查询、取消、重连恢复及结果状态机；持久化会话分别使用 `4g` / `wifi` 命名空间，保留 WiFi 原有存储键及兼容处理。
- 新增标题的英文和简体中文本地化，未改动升级页面视图和约束，未新增设备配置、依赖或 target。

当前锁定 NordicSigMeshSDK 为远程 `release` 的 `86f5ec9e40148b9cd93e0512702337fcec41dd40`。已直接核对该提交的 `WiFiGatewayDFUStartRequest`，允许 `http://` 与 `https://`；此次无需修改本地 SDK 或 Package.resolved。SDK 仍会校验 URL/固件 ID 字节与长度。

## 除内置型号外，设备如何成为 4G 网关

当前不存在独立的 `is4GGateway` 能力探测。需要区分三个层次：设备分类、Gateway 业务记录、WiFi/4G 页面分流。

### 1. 服务器设备配置和本地缓存

`SitesViewController.loadMeshDeviceConfigRequest` 从 `devicesConfig` 响应读取设备信息，替换运行时 `supportDeviceInfos` 并保存数据库。只要服务器提供新 PID，且 `deviceCategory` 为 `Gateway`，它就不需要预先出现在内置 JSON 中。

App 启动时读取 `MeshDeviceConfigInfo.load()` 的数据库缓存；缓存非空时优先使用缓存。未设置运行时列表时，`MeshLibManager.supportDeviceInfos` 才加载 Bundle 内的 `devices_config.json`。这些来源是替换关系，不能假设服务器列表与内置列表自动合并。

来源：

- `SunSmart/Main/Site/Controller/SitesViewController.swift:473`
- `SunSmart/AppDelegate/AppDelegate.swift:41`
- `SunSmart/Common/Data/Database.swift:2722`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:495`
- `SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift:44`

### 2. 扫描添加阶段按 CID + PID 查配置

Site 添加页面使用广播设备的 CID 和 PID 匹配 `supportDeviceInfos`，再用配置的 `deviceCategory` 转换为 `Node.DeviceType`。其中字符串 `Gateway` 对应 `.gateway`，只有网关候选能通过 Site 页面过滤。

未匹配配置的扫描设备默认是 `.unknown`；这里没有按 PID 的 `0x17xx` / `0x27xx` 前缀自动判断网关的规则，也没有通过 SIM、APN、蜂窝信号或 DFU 响应探测 4G 类型。

来源：

- `SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift:144`
- `SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift:158`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1949`

### 3. 已入网 Node 按配置映射设备类型

`Node.deviceConfigInfo` 从运行时列表匹配 PID，并将结果缓存在 Node 关联对象中；`Node.deviceType` 将配置中的 `deviceCategory` 转换为枚举。如果没有配置，则默认返回 `.light`。

这里发现一处现有差异：Node 查询只比较 PID，没有像扫描添加阶段一样同时比较 CID。不同厂商相同 PID 存在匹配到错误分类的可能。此外，非空的 Node 配置缓存不会在这个 getter 中随服务器列表变化自动刷新。这两点仅记录，本次未改动分类行为。

来源：`SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1995`、`:2013`。

### 4. 云端 gateways 与已保存的 GatewayModel 是另一条列表入口

Site 云端导入会处理响应中的 `gateways` 数组，导入 Node 和 `GatewayModel`。`GatewayModel.import` 需要节点 MAC，但不要求 PID 在内置 JSON 中，也不检查 `node.deviceType == .gateway`。

Site 列表从 `GatewayModel.load(siteId:)` 加载业务记录，再按记录地址解析当前 Site Mesh 中的 Node；成功后直接包装为 `Gateway(model:node:)`。这条列表链路同样没有再次检查 PID 白名单或 `node.deviceType`。

因此，有对应 GatewayModel 和可解析 Node 的设备，即使当前配置不能把 Node 分类为 `.gateway`，仍可能出现在 Gateway 列表。这也解释了为何“内置 JSON 没有 0x2703”与“能进入 0x2703 Gateway 页面”并不矛盾。能进入页面不代表其他依赖 `.gateway` 的同步逻辑也都具备一致的分类。

来源：

- `SunSmart/Common/Data/ImportData.swift:752`、`:890`、`:2628`
- `SunSmart/Main/Site/Controller/SiteViewController.swift:1434`
- `SunSmart/Main/Device/Gateway/Model/GatewayModel.swift:171`

### 5. 最终页面按 WiFi 白名单分流，剩余网关走 4G

`Node.isWiFiGateway` 目前只接受 CID `0x0A78` 且 PID `0x2721`。

在已有 Gateway 对象、权限满足的前提下，Site 页面仅判断 `isWiFiGateway`：符合时进入 `WiFiGatewayViewController`，否则进入 `GatewayViewController`。后者固定返回固件类型 `.fourG`，因此显示 `4G DFU` 和 4G 相关页面功能。

这是界面分流规则，不是硬件能力证明。新型 WiFi 网关若未加入 WiFi 白名单，也可能被分流到 4G 页面；插卡状态、APN、CSQ/在线状态不参与这条类型判断。

来源：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1905`、`:1923`
- `SunSmart/Main/Site/Controller/SiteViewController.swift:3195`
- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:137`

## 回归与验收

- `bash scripts/check_wifi_gateway_menu_icons.sh`：通过，含 PID `0x2703` 允许、内置旧 4G PID/WiFi PID/未知 PID/nil 拒绝及固件 Profile 检查。
- `bash scripts/check_wifi_gateway_firmware_update.sh <当前构建所用 SDK checkout>`：通过。覆盖状态恢复、取消、事务门、SDK 取消/状态/Start 契约、4G 签名 URL 原样传递、空 URL 拒绝、WiFi 区域地址和版本处理，以及 4G/WiFi 存储隔离。
- 脚本原有 target 数量断言仍是四个，已同步为工程实际的五个；未更改 target 成员关系。
- 已核查共享约束链：页面安全区域及底部按钮、滚动内容容器、版本卡片、当前版本区和动态状态视图。此次复用全部现有约束；静态核查不能替代真实布局测试。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 的 Debug / generic iPhoneOS / 禁用签名构建均通过。
- Lumineux 首次因缺少本地 Pods 生成配置而失败；执行 `pod install --deployment` 按锁定版本补齐后通过。撤回该工具附带的工程文件排序/格式变化，最终未保留 project.pbxproj 或依赖版本变更。
- 英文/中文 strings 的 `plutil -lint` 和 `git diff --check` 通过。
- 真机布局及实际 OTA 尚未验收：已检测到连接设备并询问本次使用的设备及 0x2703 网关所在 App，尚未获得选择；未安装、启动或操作任何实机 App。按项目要求，构建及静态检查不能视为 UI 验收完成。

真机验收路径：PID `0x2703` Gateway → 右上角菜单 → `4G DFU` → 标题、当前版本、云端版本、加载失败/无固件状态与返回；检查中文/英文、小屏及 iPad 横竖屏布局。实际升级另需验证网关下载、取消、断连恢复及重启后的版本结果。

本次不据自动化通过宣称服务器存在可用固件、网关实现完整协议或实际 OTA 成功。
