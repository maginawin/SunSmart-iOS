# WiFi Firmware Current Version 需求分析与待确认方案

## 1. 结论

需求方向正确，但原始描述不足以直接进入开发。结合现有实现与本轮确认，已补齐以下关键规则：

- 当前版本来自网关实时执行的 `43 14` 查询，不使用 `Node.firmwareVersion`、云端固件版本或 App 缓存代替。
- 版本比较前只移除首字符的 `v` 或 `V`，之后沿用项目现有 `.numeric` 比较。
- 只有 New version 与 Current version 都有效，且 New version 严格大于 Current version 时，`UPGRADE` 才可用。
- 两个版本相等、New version 更低、任一版本缺失、格式非法或请求失败时，`UPGRADE` 均不可用。
- Current version 初始显示 `Loading...`；设备版本查询失败后显示本地化 `Failed`。
- 页面现有 Refresh 同时重试云端 New version 和设备 Current version 查询。

现有 `WiFi Firmware Update` 页面与菜单入口已经存在。本次不是新建页面，而是在现有页面中引入设备实时版本数据源，并修正当前“只要云端返回固件就允许升级”的临时逻辑。

## 2. 当前代码事实

### 2.1 App 页面

- `WiFiGatewayViewController.moreClick()` 已从 `WiFi DFU` 菜单进入 `WiFiFirmwareUpdateViewController`。
- `WiFiFirmwareUpdateViewController` 当前无 `Node` 参数，因此无法定位目标网关的 Vendor Model。
- 页面目前把云端 `FirmwareServerData.version` 展示为 `Current target version`。
- WiFi 子类当前无条件把有效云端固件判定为可升级，尚未与设备实际版本比较。
- 共享 `FirmwareVersionViewController` 的 UI 直到云端请求完成后才创建，无法保证进入页面时立即显示 `Loading...`。
- 页面 Refresh 当前只重试云端请求，无法重试设备版本查询。

### 2.2 SDK

- App 已使用本地 `NordicSigMeshSDK` Swift Package。
- SDK 已有 `SunricherVendorGet`、`SunricherVendorStatus`、`VendorGatewayCode`、`ResponseCode` 与 WiFi typed result 的完整扩展模式。
- `43 0D`、`43 0E`、`43 0F`、`43 12`、`43 13` 已沿同一 Gateway vendor pipeline 实现，因此 `43 14` 不需要新增 vendor 基础层。
- Vendor response matching 已包含 `ResponseCode`，新增独立 response code 后可避免 `43 14` 与其它 Gateway 查询互相误配。

## 3. 协议实现边界

### 3.1 请求

SDK 新增 WiFi firmware version GET，编码必须始终为精确的 `43 14` 两字节，不接受调用方追加参数。

### 3.2 应答结果模型

SDK 应保留协议语义，提供 typed result：

- success(version)
- invalidParameters
- busy
- queryFailed
- deadlineExceeded
- reserved(rawValue)

App 页面可以把所有非 success 结果统一显示为 `Failed`，但 SDK 不应把不同 ret 压扁，以便诊断、日志和后续产品行为扩展。

### 3.3 严格解析

- `ret=0x00` 时，payload 必须精确符合 `43 14 00 version_len version`。
- `version_len` 必须为 `1...32`，且必须与剩余字节数完全一致。
- 版本必须能解析为可展示的 ASCII；控制字符、非 ASCII、长度不符或 trailing bytes 均视为非法响应。
- `ret!=0x00` 时，payload 必须精确为 3 字节；存在附加字段时视为非法响应。
- 未知 ret 保留原始值并按失败处理。
- `status.isSuccessful` 仅在 typed result 为 success 时为 true；其它 ret 保留 `errorCode`。

### 3.4 App 等待时间

网关内部 5 秒总截止与 App 的 Mesh 等待时间不是同一个计时层。App 建议使用现有 10 秒 Mesh response timeout，为网关 5 秒处理和 Mesh 传输留出余量；不应把 App timeout 也强制设成 5 秒，否则可能与网关发出的 `ret=0x04` 同时到期而丢失可诊断结果。

## 4. 需求完整性分析

### 4.1 已完整的部分

- 请求方向、Vendor Opcode、payload 和 response 格式明确。
- 网关 busy、失败与 5 秒截止语义明确。
- 页面入口、标题语义、初始 Loading 状态和升级按钮目标行为明确。
- 已确认版本规范化和比较规则。
- 已确认失败展示与 Refresh 重试规则。

### 4.2 原需求缺少、现已补齐的部分

- Current version 查询失败后的最终展示。
- Refresh 是否同时重试两个数据源。
- New version 与 Current version 的规范化和比较规则。
- 当前版本未知时不得启用升级。
- SDK 是否保留各 ret 的 typed result。
- App timeout 不应与网关内部 5 秒截止机械等同。

### 4.3 本次明确不包含

- WiFi 固件文件下载、校验、传输、升级进度、重启恢复与结果确认。
- `UPGRADE` 点击后的真实 DFU 行为；继续沿用现有 `under_development` 提示。
- 自动轮询 Current version。
- 将查询结果写入 Node、数据库或云端。
- 改动 4G Gateway 或其它 Firmware Update 页面行为。

如果产品期望本次点击 `UPGRADE` 后真正完成 WiFi DFU，需要另行提供升级协议和状态协议，并作为独立需求规划。

## 5. 方案比较

### 方案 A：共享页面增加窄扩展点，WiFi 子类维护设备版本状态（推荐）

保留 `FirmwareVersionViewController` 的布局和云端固件请求；只增加 Current version 标题、展示状态、附加数据加载、Refresh 联动及触发 UI 刷新的窄扩展点。WiFi 子类持有目标 `Node` 和设备版本查询状态。

优点：复用现有 UI、历史列表、dev 查询和云端错误处理；改动聚焦；BLE/Mesh 页面可保持默认行为。缺点：需要谨慎调整共享 controller 的 private 边界，并用回归测试守住默认行为。

### 方案 B：WiFi 页面复制完整固件页面

将共享页面 UI、云端请求和状态处理复制到 WiFi controller，再加入设备查询。

优点：WiFi 行为完全隔离。缺点：重复约 500 行页面逻辑，后续两个页面容易漂移；不符合当前继承设计，也扩大多 target 回归面。不推荐。

### 方案 C：把双数据源状态整体下沉到共享页面

为共享 controller 引入通用的 cloud/device 联合状态模型，所有固件页面统一迁移。

优点：长期模型最完整。缺点：本次只有 WiFi 页面需要实时设备版本，会把 BLE/Mesh 页面一起卷入重构，超出当前需求。不推荐本轮采用。

## 6. 推荐设计

### 6.1 SDK 层

沿现有 Gateway vendor pipeline 增加 `0x14`：

- `VendorGatewayCode` 增加 WiFi firmware version code。
- `VendorFunctionGet` 增加对应查询，生成精确 `43 14`。
- `ResponseCode` 增加独立匹配项并映射到 `43 14`。
- `SunricherVendorStatus` 增加严格解析函数和 typed result。
- `FunctionParameters` 增加 WiFi firmware version result。
- `VendorServerDelegate` 对此只读查询结果保持 no-op，不缓存到 Node。

### 6.2 App 入口与目标设备

- `WiFiFirmwareUpdateViewController` 改为使用当前 `Node` 初始化。
- `WiFiGatewayViewController` 在 `WiFi DFU` 回调中传入当前网关 node。
- 子类通过 `node.sunricherVendorModel` 定位目标；没有 Vendor Model 时直接进入失败态，不发送请求。

### 6.3 页面状态

Current version 使用三个明确状态：

| 状态 | 展示 | UPGRADE |
| --- | --- | --- |
| loading | `Loading...` | 禁用 |
| loaded(version) | 实时版本 | 按比较结果决定 |
| failed | `Failed` | 禁用 |

New version 继续来自当前云端请求。页面升级资格是两个数据源的联合派生值，不单独缓存布尔值：

- 云端 New version 有效；
- 设备 Current version 有效；
- 两者规范化后格式可比较；
- New version 严格大于 Current version。

任何一项不满足，按钮立即禁用。

### 6.4 加载与 Refresh

- 页面创建后立即显示完整 UI，Current version 初始为 `Loading...`。
- 首次进入时并行发起云端 New version 请求和 Mesh `43 14` 查询，二者互不阻塞。
- 任一请求返回后只更新对应状态，再统一重算页面和按钮状态。
- Refresh 开始时清除旧云端结果，并把 Current version 重置为 `Loading...`；随后同时重试两个请求。
- 如果设备查询失败，即使云端已有新版本也显示失败态并保持按钮禁用。
- 页面销毁后忽略延迟回调，不写缓存、不弹额外 HUD。

### 6.5 版本规范化

- 仅移除开头一个 `v` 或 `V`。
- 移除后为空视为不可比较。
- 使用项目现有 `.numeric` 比较。
- 仅 `.orderedDescending` 表示可升级；`.orderedSame` 和 `.orderedAscending` 均不可升级。
- 不自行补齐版本段、不解析 prerelease 权重、不把格式异常版本猜测成可升级。

### 6.6 UI 与国际化

- WiFi 页面标题行从 `Current target version` 改为 `Current version`。
- 只对 WiFi 页面覆盖标题；其它固件页面继续显示 `Current target version`。
- 复用现有 `Loading...` 和 `failed` 国际化 key；如实际大小写不符合设计稿，再新增 WiFi 专用 key，并同步 English 与简体中文。
- New version 文案和页面标题保持现状。

## 7. 计划影响文件

### SDK 仓库

- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- `Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift`
- `Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`

### App 仓库

- `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`
- `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- `SunSmart/en.lproj/Localizable.strings`，仅在需要新增 key 时修改
- `SunSmart/zh-Hans.lproj/Localizable.strings`，仅在需要新增 key 时修改
- `scripts/check_wifi_gateway_firmware_update.sh`

## 8. 测试与验收规划

### 8.1 SDK 测试

- GET 编码精确等于 `43 14`。
- success：长度 1、长度 32、含数字与点号的 ASCII 版本。
- failure：`0x01...0x04` 与未知 ret 的 typed result。
- 非 success 带 trailing bytes 必须拒绝。
- success 缺少 length、length 为 0、length 大于 32、声明长度与实际不符、非 ASCII、控制字符、success trailing bytes 必须拒绝。
- response matching 只接受同一 source 的 `43 14`，拒绝其它 Gateway subcode。

### 8.2 App 聚焦测试

- 菜单把当前 node 传给 WiFi Firmware Update 页面。
- Current version 标题只在 WiFi 页面变为 `Current version`。
- 初始值是 `Loading...`。
- success 后展示设备版本，不展示云端版本代替它。
- ret failure、非法响应、无 model、设备离线和 App timeout 后展示 `Failed`。
- Refresh 同时重新触发云端和设备查询，并先禁用按钮。
- New > Current 启用；New = Current、New < Current、任一缺失或格式非法均禁用。
- `v/V` 前缀规范化符合确认规则。
- `UPGRADE` 动作仍为现有占位提示。

### 8.3 构建验证

- SDK focused tests 若仍受现有 macOS `UIKit` 限制，则以测试源码覆盖加 iPhoneOS 编译验证为准。
- 直接运行主 App `SunSmart` Debug iPhoneOS build。
- 检查 `Archipelago`、`SLG Sync Plus`、`SylSmart` 三个共享 target 的 Debug iPhoneOS build。
- 构建本地 SDK 的 `NordicSigMeshDemo` iPhoneOS target。
- 运行 WiFi Gateway 专项脚本与 `git diff --check`。

## 9. 验收标准

- 进入页面即可看到 `Current version: Loading...`，而不是先等待云端请求完成才出现页面内容。
- App 发出的 Vendor GET payload 精确为 `43 14`。
- 合法成功响应显示真实 WiFi firmware version。
- 所有协议失败、解析失败和 App timeout 都显示 `Failed`，且不遗留上一次版本。
- Refresh 同时刷新 Current version 与 New version。
- 只有 New version 严格高于 Current version 时 `UPGRADE` 可用。
- 其它 Gateway、BLE/Mesh 固件页面及四个品牌 target 行为不变。

## 10. 待确认

建议采用方案 A，并按本文范围实施。正式实现前还需确认：本次只负责查询、展示和按钮 enablement，`UPGRADE` 点击继续保留 `under_development`，不实现真实 WiFi DFU。
