# HTTP Diagnostics Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Per project preference, use Inline Execution unless the user explicitly requests subagents.

**Goal:** 在 DEBUG 环境下补全 HTTP 请求、响应、业务错误与创建 Space 同步上下文日志，并保留 unknown 错误的原始服务端信息。

**Architecture:** 保持现有 Moya 网络层结构不变，优先增强 `NetworkLoggerPlugin`、`NetworkRequest`、`NetworkApiError` 与 `CloudSynchronizationManager` 的诊断能力。日志只在 DEBUG 下输出，不改变 Release 行为；业务错误信息通过 `NetworkApiError` 保真传递，UI 仍使用本地化文案展示。

**Tech Stack:** Swift、UIKit、Moya、Alamofire、SwiftyJSON、现有 `CloudSynchronizationManager`。

---

## 文件边界

- Modify: `SunSmart/Common/Network/NetworkLoggerPlugin.swift`
  - 负责 DEBUG 下输出 request/response 层日志。
  - 增加 body 摘要、响应体摘要、gzip 标记、Moya/AFError 信息。

- Modify: `SunSmart/Common/Network/NetworkRequest.swift`
  - 负责解析业务 `code`、`message`、HTTP status、响应体。
  - 将未知错误保留为携带原始 code/message 的错误，而不是直接丢成无上下文 `.unknown`。

- Modify: `SunSmart/Common/Network/NetowrkReqeustApi.swift`
  - 负责暴露 target 诊断名称、path、headers、是否声明 gzip、是否实际 gzip 的判断入口。
  - 不在本计划中修正 gzip 行为，只增加诊断，避免把“查日志”与“改传输协议”混在一起。

- Modify: `SunSmart/Common/Cloud/CloudSynchronizationManager.swift`
  - 负责创建 Space 失败时输出同步上下文：operation、siteId、spaceId、spaceName、API path、错误 code/message。

- Optional Test/Debug Support: `SunSmartTests` 或现有测试 target
  - 如果项目当前测试 target 可用，则增加 `NetworkApiError` 映射测试。
  - 如果测试 target 不稳定，则用 `xcodebuild` 编译验证加 DEBUG 手动日志验证。

---

## Task 1: 补充 Network API 诊断元数据

**Files:**
- Modify: `SunSmart/Common/Network/NetowrkReqeustApi.swift`

- [ ] **Step 1: 增加 DEBUG 诊断属性**
  - 为 `NetowrkReqeustApi` 增加只读诊断信息：
    - target case 名称。
    - method。
    - full URL。
    - path。
    - headers。
    - parameters。
    - 是否声明 `Content-Encoding: gzip`。
    - 当前 task 是否实际发送 gzip body。
  - `siteUpload` 和 `spaceUpload` 日志必须能明确显示：`declaredContentEncodingGzip=true`、`actualBodyGzip=false`。

- [ ] **Step 2: 控制敏感字段输出**
  - 日志参数中对密码字段做脱敏：
    - `passwd`
    - `editorPasswd`
    - `visitorPasswd`
  - `userId` 可以保留；不新增任何 Auth 信息。

- [ ] **Step 3: 验证元数据编译**
  - Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
  - Expected: 编译通过。

---

## Task 2: 补全 DEBUG 请求与响应日志

**Files:**
- Modify: `SunSmart/Common/Network/NetworkLoggerPlugin.swift`
- Read: `SunSmart/Common/Network/NetworkRequest.swift`

- [ ] **Step 1: 恢复并规范 request 日志**
  - 在 `willSend` 中只对 DEBUG 输出：
    - target。
    - HTTP method。
    - full URL。
    - headers。
    - request body 摘要。
    - body byte count。
    - declared/actual gzip 状态。
  - body 摘要限制长度，避免 site/space 大 JSON 刷屏。

- [ ] **Step 2: 补充 success response 日志**
  - 在 `didReceive` 的 `.success` 分支输出：
    - target。
    - URL。
    - HTTP status。
    - response byte count。
    - response body 摘要。
  - 需要包含业务 `code` 和 `message`，如果没有字段则显示为空或 `<missing>`。

- [ ] **Step 3: 补充 failure 日志**
  - 在 `.failure` 分支输出：
    - target。
    - URL。
    - MoyaError 描述。
    - NSError code/domain。
    - AFError underlying code/domain，如果存在。
    - HTTP status，如果 response 存在。

- [ ] **Step 4: 验证日志不会影响 Release**
  - 确认所有新增 print 都在 `#if DEBUG` 内。
  - Run: `rg -n "print\\(" SunSmart/Common/Network`
  - Expected: 网络诊断 print 均处于 DEBUG 条件编译范围。

---

## Task 3: 保留 NetworkApiError 原始错误信息

**Files:**
- Modify: `SunSmart/Common/Network/NetworkRequest.swift`
- Modify as needed: `SunSmart/Common/Data/Database.swift`

- [ ] **Step 1: 扩展错误结构**
  - 保留现有已知 case 的本地化行为。
  - 为 unknown 增加原始信息能力：
    - raw code。
    - server message。
    - HTTP status。
    - response body 摘要或原始 body string。
    - underlying NSError domain/code。
  - 注意：当前 `Database.swift` 只持久化 `syncCloudError?.code`，如果改成 associated value enum，需要确认保存/读取仍能编译。

- [ ] **Step 2: 修改业务失败解析**
  - `NetworkRequest.request(_:completion:)` 中，当 `code != 200` 且不是已知业务错误时，不再直接丢失为无上下文 `.unknown`。
  - 从响应 JSON 中提取 `message`、`msg` 或同类字段，附加到 `NetworkApiError`。
  - 对 JSON 解析失败也要保留 HTTP status 和 response body 摘要。

- [ ] **Step 3: 保持 UI 文案稳定**
  - `localizedDescription` 对用户仍显示既有本地化文案。
  - 新增一个 DEBUG 诊断描述属性，用于日志输出原始 code/message/body。
  - 不把服务端原始 body 直接展示给用户。

- [ ] **Step 4: 验证错误映射**
  - 如果测试 target 可用，增加或更新错误映射单元测试：
    - 已知 code 仍映射到既有 case。
    - 未知 code 保留 raw code/message。
    - NSError/MoyaError code 保留。
  - 如果测试 target 不可用，至少运行 iOS 编译验证。

---

## Task 4: 创建 Space 同步上下文日志

**Files:**
- Modify: `SunSmart/Common/Cloud/CloudSynchronizationManager.swift`
- Read: `SunSmart/Main/Site/Controller/SiteViewController.swift`

- [ ] **Step 1: 为 SyncOperation 增加诊断描述**
  - 输出 operation 类型：
    - `syncSite`
    - `syncSpace`
    - `addSpaces`
    - `syncGateway`
  - 对 `.addSpaces` 输出：
    - siteId。
    - space count。
    - 每个 space 的 `id` 与 `name`。
  - 对 `.syncSpace` 输出 spaceId、spaceName、siteId。

- [ ] **Step 2: 请求前输出同步上下文**
  - 在 `CloudSynchronizationHandle.syncOperation()` 生成 api 后，发送请求前输出：
    - operation 诊断描述。
    - api target/path。
    - level。
  - 仅 DEBUG 输出。

- [ ] **Step 3: 失败时输出完整上下文**
  - 在 request `.failure` 分支输出：
    - operation 类型。
    - siteId。
    - spaceId。
    - spaceName。
    - api path。
    - `NetworkApiError.code`。
    - `NetworkApiError` DEBUG 诊断描述。
  - 重点覆盖 `.addSpaces`，因为创建 Space 会走这个分支。

- [ ] **Step 4: 成功时输出简短上下文**
  - 在 request `.success` 分支输出 operation 与 api path，便于确认请求确实完成。

---

## Task 5: 验证与回归

**Files:**
- Verify: `SunSmart.xcworkspace`
- Verify: `docs/260526_1754_http_logging_and_space_creation_failure_analysis.md`
- Update if needed: `docs/260526_1758_http_diagnostics_logging_plan.md`

- [ ] **Step 1: 全量编译验证**
  - Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
  - Expected: 编译通过。

- [ ] **Step 2: 手动验证创建 Space 日志**
  - 在 DEBUG 运行 App。
  - 在已上传云端的 Site 中创建 Space。
  - Expected logs:
    - `addSpaces` operation 上下文。
    - `/sitespace/sync/siteprops`。
    - request headers/body 摘要。
    - `siteUpload` 的 declared/actual gzip 状态。
    - HTTP status。
    - business code/message。
    - 成功或失败结果。

- [ ] **Step 3: 手动验证业务错误保真**
  - 模拟或复现创建 Space 失败。
  - Expected:
    - UI 仍显示本地化错误。
    - Console 能看到原始 code/message/response 摘要。
    - unknown 不再丢失原始错误码。

- [ ] **Step 4: 检查 Release 无诊断输出**
  - 确认新增网络日志都被 DEBUG 条件包住。
  - 不新增 Release 持久化日志，不新增 Auth 相关输出。

---

## 风险与注意事项

- 不在本计划中直接修复 gzip 传输策略；本次先让日志证明 `Content-Encoding` 与 body 是否不一致。
- `NetworkApiError` 当前是 enum 并被数据库通过 `.code` 持久化。扩展 raw 信息时要避免破坏现有存储读取。
- `CloudSynchronizationManager.shared.delegate` 当前是单 delegate，日志不要依赖 delegate，否则不同页面切换会影响诊断。
- Space/site 上传 body 可能很大，日志必须摘要化，避免控制台不可读。
- 密码字段必须脱敏。

---

## 自检

- 需求 1 覆盖：Task 1、Task 2、Task 3。
- 需求 2 覆盖：Task 1、Task 2，明确输出 `siteUpload`/`spaceUpload` declared/actual gzip。
- 需求 4 覆盖：Task 3。
- 需求 5 覆盖：Task 4。
- 没有安排无关重构。
- 没有修改 target 配置、资源、本地化或依赖。

