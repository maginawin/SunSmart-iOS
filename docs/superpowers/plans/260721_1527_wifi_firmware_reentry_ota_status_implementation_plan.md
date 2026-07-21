# WiFi Firmware Re-entry OTA Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` for Inline Execution. Follow each RED/GREEN checkpoint in order and do not overwrite pre-existing worktree changes.

**Goal:** 修复 WiFi Firmware Update 页面重新进入后直接回放 stale `Upgrade failed`、不发送 `0x43/0x11` 获取 Gateway 当前 OTA 状态的问题。

**Architecture:** 保留当前 coordinator、session store 和 reducer 边界。在 Foundation-only session 模型中增加可测试的页面恢复/query eligibility/authoritative response policy；coordinator 只负责执行该策略、发送 Mesh 请求和发出 UI event。同一页面周期内的首终态锁定保持不变，新的页面可见周期必须先经过权威 GET。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Foundation-only focused tests、shell static contract、Xcode iPhoneOS builds。

## Global Constraints

- 使用简体中文文档；UI 文案保持现有英文及本地化实现。
- 只修改 WiFi DFU App 恢复链路，不修改 NordicSigMeshSDK、BLE OTA 或 Mesh OTA。
- 不新增或修改用户可见文案、本地化、资源、依赖或 target 配置。
- 保留 `WiFiFirmwareUpdateViewController.swift` 中用户已有的“相同版本允许升级”未提交改动。
- 不顺手重构 coordinator 或 shared firmware page。
- 先写失败测试并确认 RED，再写最小实现。
- 验证使用 generic iPhoneOS，不使用 Simulator，不使用 shell 包装或日志重定向。

---

### Task 1: Foundation-only 恢复策略 RED/GREEN

**Files:**

- Modify: `Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift`
- Modify: `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift`

**Interfaces:**

- Produces: `WiFiFirmwareDFUSession.prepareForPageRecovery()`。
- Produces: `WiFiFirmwareDFUSession.isStatusQueryEligible`。
- Produces: `WiFiFirmwareDFUAuthoritativeRecoveryPolicy.decision(session:candidate:)`。
- Produces: `WiFiFirmwareDFUAuthoritativeRecoveryDecision.acceptStatus / clearStaleTerminal / retainSession`。

- [ ] **Step 1: 写页面恢复失败测试**

在 focused test 增加 `testPageRecoveryRequiresAuthoritativeQuery()`，构造非终态、失败终态、成功终态和已消费 session，断言：

- 三种未消费 session 调用 `prepareForPageRecovery()` 后都设置 `requiresAuthoritativeQuery=true`。
- 三种未消费 session 的 `isStatusQueryEligible=true`。
- 已消费 session 不打开权威门且不可查询。

- [ ] **Step 2: 写权威响应决策失败测试**

增加 `testAuthoritativeRecoveryPolicy()`，断言：

- 身份匹配的非终态或终态 candidate 返回 `acceptStatus`。
- 缓存终态遇到 IDLE、其它 `ota_id` 或其它 `firmware_id` 返回 `clearStaleTerminal`。
- 缓存非终态遇到相同不匹配状态返回 `retainSession`。
- 已消费 session 不接受 candidate。

- [ ] **Step 3: 运行 focused test 并确认 RED**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift -o /tmp/WiFiFirmwareDFUStatusReducerTests
```

Expected: 编译失败，明确缺少新的恢复策略 API；不能因拼写或测试夹具错误失败。

- [ ] **Step 4: 实现最小 session 恢复策略**

在 `WiFiFirmwareDFUState.swift` 为 session 增加：

```swift
mutating func prepareForPageRecovery() {
    guard !terminalConsumed else { return }
    requiresAuthoritativeQuery = true
}

var isStatusQueryEligible: Bool {
    !terminalConsumed && (
        requiresAuthoritativeQuery || lastStatus?.stage.isTerminal != true
    )
}
```

增加 Foundation-only authoritative decision：先校验 session 未消费、candidate 非 IDLE、`firmware_id` 匹配、`ota_id` 匹配或尚未绑定；匹配返回 `acceptStatus`。不匹配时，仅缓存终态返回 `clearStaleTerminal`，其余返回 `retainSession`。

- [ ] **Step 5: 运行 focused test 并确认 GREEN**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift -o /tmp/WiFiFirmwareDFUStatusReducerTests
/tmp/WiFiFirmwareDFUStatusReducerTests
```

Expected: `WiFiFirmwareDFUStatusReducerTests passed`。

---

### Task 2: Coordinator 权威恢复 RED/GREEN

**Files:**

- Modify: `scripts/check_wifi_gateway_firmware_update.sh`
- Modify: `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift`

**Interfaces:**

- Consumes: Task 1 的 session 与 authoritative recovery policy。
- Preserves: 当前页面周期的 reducer 首终态锁定、3 秒 GET timeout、10/30 秒查询节奏、`ota_id + firmware_id` 身份门。

- [ ] **Step 1: 增加 coordinator 静态失败 contract**

contract 必须检查：

- 磁盘恢复调用 `prepareForPageRecovery()`。
- `refresh()` 在终态回放之前优先处理 `requiresAuthoritativeQuery`。
- coordinator 使用 `isStatusQueryEligible`，不再由 `isActiveNonterminalSession` 独占查询资格。
- authoritative response 通过 `WiFiFirmwareDFUAuthoritativeRecoveryPolicy` 分流。
- `clearStaleTerminal` 分支清理 session、发出 `.idle` 并查询 Current version。

- [ ] **Step 2: 运行 static contract 并确认 RED**

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: 在新增恢复策略断言处失败；如果先被工作区现有版本比较实验拦截，单独运行新增恢复断言并记录该既有差异，不修改用户实验代码。

- [ ] **Step 3: 修正 session 初始化与页面退出**

- 磁盘 load 后调用 `prepareForPageRecovery()`，不再只处理非终态。
- `deactivate()` 对所有未消费 session 打开权威门并保存；没有 session 或已消费 session 不处理。

- [ ] **Step 4: 修正 refresh 优先级**

顺序固定为：

1. 无 session：查询 Current version。
2. 未消费且 `requiresAuthoritativeQuery`：显示 communication unknown，立即发 authoritative `43 11`。
3. 同一页面周期已确认终态：回放当前内存终态，不重新查询。
4. 活动非终态：执行普通 status query。

- [ ] **Step 5: 修正查询/重试/连接恢复资格**

将 `handleConnectionChange`、`handleNoValidStatus` 和 `scheduleQuery` 的 guard 统一改为 session 的 `isStatusQueryEligible`。这样恢复终态首次查询失败后仍可调度，代理重连后也能立即查询。

- [ ] **Step 6: 执行 authoritative response policy**

- `acceptStatus`：用 fresh reducer 接受 query candidate，关闭权威门并更新 session/UI。
- `clearStaleTerminal`：清理旧 session/reducer/计时状态，发出 `.idle`，然后查询 `43 14` Current version。
- `retainSession`：保持 communication unknown，按 30 秒恢复节奏重试。

- [ ] **Step 7: 运行 focused test 与 static contract 并确认 GREEN**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift -o /tmp/WiFiFirmwareDFUStatusReducerTests
/tmp/WiFiFirmwareDFUStatusReducerTests
bash scripts/check_wifi_gateway_firmware_update.sh
```

Expected: focused test 输出 passed；static contract 除用户现有版本比较实验外全部通过。若实验导致 contract 失败，需保持该差异并在最终结果中准确说明。

---

### Task 3: Scope Review and Verification

**Files:**

- Create: `docs/260721_1532_wifi_firmware_reentry_ota_status_implementation_summary.md`
- Verify only: `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- Verify only: localization、project file、SDK worktree。

- [ ] **Step 1: 审核 diff 范围**

确认业务改动只包含：session 恢复策略、coordinator、focused test、static contract。确认用户原有版本比较 diff 完整保留；不混入 `docs/260721_1036_timed_datetime_timezone_sync_analysis.md`。

- [ ] **Step 2: 运行完整 focused verification**

Run:

```bash
bash scripts/check_wifi_gateway_firmware_update.sh
git diff --check
```

Expected: contract 通过；若只因用户预存版本比较实验失败，单独列明唯一失败断言并证明本任务新增断言通过。`git diff --check` 无输出。

- [ ] **Step 3: 四 target generic iPhoneOS build**

依次直接运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 四次均以 `** BUILD SUCCEEDED **` 结束。

- [ ] **Step 4: 写实现总结**

记录根因、实际修改、RED/GREEN 证据、contract、四 target build、未完成的实机验证和现有用户 diff。

- [ ] **Step 5: 最终自审**

- 对照已确认分析文档逐项核查方案 A。
- 扫描计划/总结中的占位符和冲突。
- 检查没有 SDK、本地化、资源、依赖、target 或 sibling OTA 改动。
- 不提交、不 push，除非用户另行要求。
