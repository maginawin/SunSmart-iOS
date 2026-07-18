# WiFi Gateway OTA 状态 `0x43/0x11` V1.9 实现总结

## 1. 结论

已按确认的方案 A 完成 WiFi Gateway OTA 状态 `0x43/0x11` V1.9 更新，覆盖严格 RET/EVENT 解析、OTA 身份与状态顺序归并、查询节奏、通信未知、断连后的权威查询恢复，以及 `Upgrade cancelled + UPGRADE AGAIN` UI。

本次没有实现、发送、模拟或预留可执行的 `0x43/0x15` 取消命令，也没有实现 `Failed to cancel + CANCEL AGAIN` UI。

## 2. 提交记录

### NordicSigMeshSDK

- `af7cfbf164b299cdc1fa6fdf719bf0dba0a589da` `feat: update wifi gateway ota status protocol`
- `fdb4ab6616a650754295099739882e406553d4ac` `feat: add wifi gateway ota status events`
- `60af165998014cbd172f3994e474aaea47a7cff3` `feat: observe mesh connection changes`

### App

- `d34df88ee31ea03fb651056de7b4bec5609e48b8` `docs: design wifi gateway ota status v1.9`
- `5d5c94e86042b8c0a86ef799bd86dbbd65e90ccb` `docs: plan wifi ota status v1.9`
- `df82fac99dae520882a9280cc57ccb62b4e7ed0a` `feat: add wifi ota status reducer`
- `57ea5a0e1f795435bb34d2bbeb6ff889a9776707` `feat: coordinate wifi ota status v1.9`
- `a484f4226c8f93aa693858fdf9ecfeea07629dd8` `feat: show wifi ota cancelled status`

## 3. 已实现行为

### 3.1 SDK 协议层

- 按固定偏移解析 `ota_id: U64_LE`、阶段、进度、错误码、固件标识和模组版本。
- 严格校验完整 payload 长度、字符串长度/字符、各阶段字段组合、终态错误码，以及成功版本比较；比较前两侧各允许去掉一个前导 `v` 或 `V`。
- 支持 `PREPARING`、`CANCELLED`、`METADATA`、未知错误码失败处理和 `RET 0x02` 暂忙。
- 失败 RET 只接受 3 字节；成功 RET 必须是完整合法状态。
- 在既有 Vendor Opcode `0xF50A78` 的 SDK 表示 `0xF5780A` 下，将 `43 11 00...` 分流为 OTA 状态 EVENT；普通在线状态上报保持原行为。
- 新增可并存的 Mesh 连接观察接口，只在有效连接状态变化时通知，不因代理替换重复上报。

### 3.2 App 状态与协调层

- 以 `ota_id + firmware_id` 绑定同一轮 OTA；拒绝外轮状态、倒退阶段、下载进度下降、重复状态和首个终态之后的状态。
- `0x10 00` 等待期间即可接收匹配 EVENT；若 ACK 到达前已有合法匹配状态，不追加即时 GET，否则立即查询一次 `0x43/0x11`。
- GET 等待上限为 3 秒；非终态连续 10 秒无新合法状态才查询；30 秒无合法状态进入通信未知，之后每 30 秒查询。
- RET 暂忙、参数错误、保留返回、传输超时、非法 payload 和身份不匹配均不清除已接受的 OTA 会话。
- 断连后设置权威查询门并忽略 EVENT；重连后必须通过本次完整、合法、身份匹配的 GET RET 重建 reducer 基线，不能用断连前缓存阶段直接判断结果。
- 同一轮只接受首个合法终态；查询取得的 `CANCELLED` 映射为取消成功。由于本次不实现取消事务，实时 `VERIFYING -> CANCELLED` EVENT 不直接作为合法取消结果。
- V1.9 会话使用独立持久化 Key，并移除旧格式缓存，避免旧阶段缓存绕过权威恢复流程。

### 3.3 UI

- `CANCELLED` 显示 `Upgrade cancelled`，复用既有失败图标和进度区域，主按钮为 `UPGRADE AGAIN`。
- 通信未知显示既有 `Connection failed / Communication timeout`，主按钮仍为禁用的 `CANCEL`。
- English 与简体中文本地化均已补充；没有新增资源或硬编码用户可见文案。
- 新 reducer 已加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。

## 4. 验证证据

验证时间：2026-07-18 17:51 至 17:54（+08）。

### 4.1 Focused contracts

- SDK 独立 parser contract：`WiFiGatewayDFUStatusV19Contract passed`。
- App reducer/session focused test：`WiFiFirmwareDFUStatusReducerTests passed`。
- App V1.9 静态契约：`PASS: WiFi Gateway firmware update static checks`。
- `plutil`：English、简体中文 `Localizable.strings` 与 `project.pbxproj` 均为 `OK`。
- App 与 SDK `git diff --check`：无输出。
- 范围扫描：没有发现 `wifiGatewayDFUCancel`、`wifiDFUCancel`、`CANCEL AGAIN` 或 `cancel_again`。

### 4.2 SwiftPM 测试状态

`swift test --filter WiFiGatewayVendorMessageTests` 未进入测试执行阶段。macOS SwiftPM 编译在既有文件 `MeshDeviceProvisioningManager.swift:8` 被 `import UIKit` 阻断，错误为 `no such module 'UIKit'`。因此不能宣称该 XCTest 套件已运行通过；本轮使用 Foundation-only parser contract 和 generic iPhoneOS 构建验证对应实现。

### 4.3 generic iPhoneOS 构建

以下构建均使用 `CODE_SIGNING_ALLOWED=NO` 并返回 `** BUILD SUCCEEDED **`：

- NordicSigMeshDemo
- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

## 5. 最终自审

- 协议解析、EVENT/RET 分流、连接观察、App reducer、协调器、UI 和四 target 集成之间没有发现 Critical 或 Important 问题。
- `SunSmart.xcodeproj/xcshareddata/xcschemes/SunSmart.xcscheme` 没有出现在任务 diff 中，最终 App 与 SDK 工作区均为干净状态。
- 静态契约中修正了历史 PBXBuildFile 重复声明导致的误报：按唯一对象 ID 检查 4 个 build file，同时继续检查 4 个真实 Sources phase membership；没有顺手清理既有工程对象。

## 6. 未覆盖项

- 未在真实 WiFi Gateway/nRF 上验证 EVENT 发送频率、Mesh 丢包、真实断连重连和 OTA 全阶段时序。
- 未验证任何 `0x43/0x15` 取消交互，因为该协议明确不在本次范围内。
- 未实现取消失败页面；待取消协议提供并单独确认后再设计其状态来源和重试动作。
