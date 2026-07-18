# Simulate Fault HTTP API 设计规格

## 1. 目标

在现有 Simulate Fault 弹窗中，将 9 个模拟故障按钮接入服务端 `simulate fault` POST 接口。请求发送期间展示覆盖当前弹窗的 `Sending...` HUD，阻止重复点击；请求结束后分别展示成功或失败提示，并保持 Simulate Fault 弹窗打开。

## 2. 范围

本次包含：

- 新增 `/temporary/device/alert/add` 网络接口。
- 新增类型化 Simulate Fault request/alert payload。
- 将现有 9 个 `SimulateFaultAction` 映射到服务端 alert。
- 在 `SimulateFaultViewController` 内直接发送请求和处理结果。
- 复用现有 `XWHUDManager` 展示发送中、成功和失败状态。
- 新增 `Sending...` 的英文及简体中文本地化。
- 增加纯模型测试、源码契约和四个品牌 target 的 iPhoneOS 构建验证。

本次不包含：

- 不发送 Mesh 命令。
- 不修改其他设备页面或其他菜单。
- 不新增独立 host、Auth、token 或 `userId`。
- 不消费成功响应中的 `data` 内容。
- 不在成功或失败后关闭 Simulate Fault 弹窗。

## 3. 网络接口

### 3.1 Host 与路径

继续使用 `UserData.currentServerRegion.baseURL`，保留当前 App 的多区域 host 选择。base URL 已包含 `/srv2`，因此最终请求形如：

`https://www.mericher.com/srv2/temporary/device/alert/add`

接口 path 为 `/temporary/device/alert/add`，method 为 POST，body 使用 `application/json`。

现有 Archipelago、SLG Sync Plus 等 target 的 OEM header 行为保持不变，不为该接口增加专用 header。

### 3.2 成功判定

继续通过 `NetworkRequest.shared.request` 发送。沿用当前网络层规则：返回 JSON 的 `code == 200`、`isSuccess == true` 或空 JSON 对象时视为成功，其他结果进入 `NetworkApiError` 失败路径。

OpenAPI response 中的 `data` 示例与本功能无直接关系，本次不解析和持久化该字段。

## 4. Request Payload

新增专用的类型化 request/alert payload，最终转换为现有 Moya 网络层使用的 JSON parameters。

字段来源固定如下：

| 字段 | 来源 |
| --- | --- |
| `siteId` | `space.siteId` |
| `spaceId` | `space.id` |
| `nodeId` | `node.uuid.uuidString` |
| `alert` | 当前点击的 `SimulateFaultAction` 映射结果 |
| `nodeAddress` | `node.primaryUnicastAddress.hex`，四位大写十六进制，不带 `0x` |
| `source` | 固定 `ios` |
| `desc` | 固定空字符串 |
| `location` | 固定空字符串 |
| `datetime` | 点击时的 `Date()` 转为 UTC 字符串 |

日期格式固定为 `yyyy-MM-dd HH:mm:ss`。formatter 使用 UTC 时区、Gregorian calendar 和 `en_US_POSIX` locale，避免用户地区、12/24 小时制或其他历法影响请求值。

## 5. Alert 映射

| 弹窗区域 | 按钮 | `type` | `status` | `level` |
| --- | --- | --- | --- | --- |
| Motion Sensor | Normal | `motion_sensor` | `normal` | `3` |
| Motion Sensor | Fault | `motion_sensor` | `fault` | `3` |
| Photocell Sensor | Normal | `photocell_sensor` | `normal` | `2` |
| Photocell Sensor | Fault | `photocell_sensor` | `fault` | `2` |
| Light Status | Normal | `light_status` | `normal` | `1` |
| Light Status | Dim | `light_status` | `dim` | `1` |
| Light Status | Flicker | `light_status` | `flicker` | `1` |
| Light Status | Dim Flicker | `light_status` | `dim_flicker` | `1` |
| Light Status | Off | `light_status` | `off` | `1` |

OpenAPI example 中的 `motion_sensor + dim` 与 schema 冲突，不作为实现依据；以上确认后的映射为唯一真值。

## 6. 组件职责

### 6.1 Simulate Fault 请求模型

新增独立网络请求模型文件，负责：

- alert 的 `type/status/level` 表达。
- 完整 body 字段的类型化保存。
- UTC 日期格式化。
- 转换为 `[String: Any]` JSON parameters。

该模型不依赖 View Controller，也不直接执行网络请求，便于纯 Swift 测试。

### 6.2 SimulateFaultAction

保留现有强类型 action，增加到 alert payload 的单向映射。映射逻辑集中在模型层，不在 View Controller 中散落字符串判断。

### 6.3 NetowrkReqeustApi

新增 `.simulateFault` case，并同步维护：

- `diagnosticName`
- `path`
- `parameters`

method 继续使用现有统一 POST；base URL 和默认 header 逻辑保持不变。

### 6.4 DeviceLightViewController

创建 `SimulateFaultViewController` 时，除现有 `SpaceData` 外，同时传入当前 `Node`。设备页只负责创建和 present，不接收按钮事件、不构造 payload、不发送请求。

### 6.5 SimulateFaultViewController

控制器直接处理按钮 action：

1. 检查当前仍具备 `.edit` 能力。
2. 检查没有正在发送的请求。
3. 立即设置内部 `isSending = true`。
4. 使用点击时的 `Date()` 构造完整 payload。
5. 展示 window 层 `Sending...` HUD。
6. 调用 `NetworkRequest.shared.request(.simulateFault(...))`。
7. completion 首先隐藏 loading，并恢复 `isSending = false`。
8. 成功时展示成功 HUD；失败时展示失败 HUD。

请求期间 window HUD 覆盖 Simulate Fault 内容与外部背景，阻止按钮、外部关闭区域和其他页面控件继续接收触摸。`isSending` 作为第二层保护，避免极短时间内的重复触发。

请求完成后不关闭 Simulate Fault。成功或失败 HUD 自动消失后，用户可以继续点击其他模拟故障按钮。

若发送前权限已经失效，控制器不发送请求并按现有权限变化行为关闭。若请求已经发出后权限发生变化，请求不主动取消；loading 会在 completion 中正常隐藏并展示最终结果，底层 Simulate Fault 控制器仍可按现有通知逻辑关闭。

## 7. HUD 与本地化

复用现有 `XWHUDManager`：

- 发送中：window 层 custom HUD，文案 key 为 `simulate_fault_sending`。
- 成功：`showSuccessTipHUD`，复用现有 `successful` 文案。
- 失败：`showErrorTipHUD`，复用现有 `failed` 文案。

新增文案：

| Key | English | 简体中文 |
| --- | --- | --- |
| `simulate_fault_sending` | `Sending...` | `发送中...` |

失败 HUD 只展示通用失败文案；HTTP 状态、服务端 message 和 response body 继续由现有网络日志记录，不直接暴露给用户。

## 8. 生命周期与错误处理

- completion 使用弱引用控制器，避免请求闭包不必要地延长页面生命周期。
- 无论控制器是否仍存在，completion 都必须先移除 window loading HUD，避免 HUD 残留。
- 成功和失败提示均使用现有自动消失时长。
- 网络断开、超时、非 200 业务 code、非 JSON response 等统一进入现有 `NetworkApiError` 失败路径。
- 不为本接口增加自动重试，避免用户未感知的重复故障记录。

## 9. 测试与验证

### 9.1 纯模型测试

- 逐一验证 9 个 `SimulateFaultAction` 的 `type/status/level`。
- 固定输入 Date，验证输出为 UTC `yyyy-MM-dd HH:mm:ss`。
- 验证完整 parameters 包含全部 9 个 required 字段。
- 验证 `source = ios`、`desc = ""`、`location = ""`。
- 验证 node address 保持四位大写十六进制字符串。

### 9.2 源码契约

- API path 为 `/temporary/device/alert/add`。
- 使用现有 region base URL 和 JSON POST。
- Device Light 创建 Simulate Fault 控制器时传入 node。
- 按钮 action 在 Simulate Fault 控制器内部发起请求。
- 请求期间使用 window loading HUD 和 `isSending` guard。
- 不包含 Mesh send 调用。
- 英文和简体中文均包含 `simulate_fault_sending`。

### 9.3 构建

使用 iPhoneOS generic destination，分别构建：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

### 9.4 人工验证

- 逐个点击 9 个按钮，核对服务器收到的 alert。
- 快速连续点击，确认只产生一个请求。
- 请求期间确认 HUD 覆盖当前 Simulate Fault 并阻止外部点击关闭。
- 成功时展示成功提示，失败时展示失败提示。
- 结果提示消失后 Simulate Fault 仍保持打开，并可继续发送其他 action。
