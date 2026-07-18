# WiFi Gateway RSSI 10 秒轮询 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 WiFi Gateway 页面中每次 RSSI 请求 completion 后的下一次请求等待时间从 5 秒延长到 10 秒。

**Architecture:** 保留 `WiFiGatewayViewController` 当前 completion-driven one-shot scheduling：首次立即请求、单次请求 2 秒 timeout、完成后调度下一次。只更新 polling delay 常量及其 focused source contract，不修改 SDK、协议、UI 或其他 Gateway polling。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Bash source contract、Xcode workspace generic iPhoneOS build。

## Global Constraints

- 当前年份按 2026 年处理。
- 所有回复和 Markdown 文档使用简体中文；现有英文 contract failure message 保持英文风格。
- 保持改动聚焦，不重构无关模块，不格式化无关文件。
- 不新增或修改 Auth 信息。
- 不修改本地化、资源、target 配置或依赖。
- 不修改 `wifiRSSIStatusRequestTimeout = 2`。
- 不修改首次立即请求、completion-driven one-shot scheduling 或现有启动/停止门槛。
- 不修改 SDK、`43 0F` wire format、response parsing、RSSI/Internet status UI 映射、`connectionPollInterval`、通用 Gateway signal timer 或 Mesh heartbeat。
- iOS 验证直接使用 `xcodebuild` 和 generic iPhoneOS destination，不使用 shell 包装、日志重定向或 Simulator。
- 实施使用 Inline Execution，不使用 subagents。

---

### Task 1: 将 RSSI completion 后等待时间收紧为 10 秒

**Files:**
- Modify: `scripts/check_wifi_gateway_wifi_status_header.sh:48`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:64`
- Reference: `docs/superpowers/specs/260720_0936_wifi_gateway_rssi_polling_10_second_design.md`

**Interfaces:**
- Consumes: `wifiRSSIStatusPollDelay: TimeInterval`、`scheduleNextWiFiRSSIStatusRefresh()`、`wifiRSSIStatusRequestTimeout: TimeInterval`。
- Produces: `wifiRSSIStatusPollDelay == 10` 的源码契约；现有 one-shot Timer 继续读取该常量。

- [ ] **Step 1: 先更新 focused contract**

将 `scripts/check_wifi_gateway_wifi_status_header.sh` 中的 delay 断言更新为：

```bash
rg -n "private let wifiRSSIStatusPollDelay: TimeInterval = 10" "$wifi_controller" >/dev/null \
  || fail "The next Wi-Fi RSSI query must wait 10 seconds after completion."
```

将 one-shot Timer 的 failure message 更新为：

```bash
rg -U -n "wifiRSSIStatusTimer = LCWeakTimer\.scheduledTimer\([[:space:][:print:]]*timeInterval: wifiRSSIStatusPollDelay,[[:space:][:print:]]*repeats: false" "$wifi_controller" >/dev/null \
  || fail "Wi-Fi RSSI polling must use a one-shot 10-second timer."
```

- [ ] **Step 2: 运行 contract，证明旧实现失败**

Run:

```bash
bash scripts/check_wifi_gateway_wifi_status_header.sh
```

Expected: FAIL，并输出 `The next Wi-Fi RSSI query must wait 10 seconds after completion.`；证明旧的 5 秒常量不能满足新契约。

- [ ] **Step 3: 实现最小业务改动**

在 `WiFiGatewayViewController` 中将唯一 polling delay 常量更新为：

```swift
private let wifiRSSIStatusPollDelay: TimeInterval = 10
```

不得修改相邻的以下 timeout：

```swift
private let wifiRSSIStatusRequestTimeout: TimeInterval = 2
```

- [ ] **Step 4: 运行 focused contract，证明新实现通过**

Run:

```bash
bash scripts/check_wifi_gateway_wifi_status_header.sh
```

Expected: PASS，exit code 0，无 `FAIL:` 输出。

- [ ] **Step 5: 运行相邻 WiFi Gateway contract**

Run:

```bash
bash scripts/check_wifi_gateway_network_connectivity.sh
bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh
bash scripts/check_wifi_gateway_sig_mesh_status_header.sh
bash scripts/check_wifi_gateway_repair_recovery.sh
bash scripts/check_wifi_gateway_server_information_recovery.sh
```

Expected: 每个脚本 exit code 0，无 `FAIL:` 输出；证明连接、断开、header、repair 和 server recovery 生命周期契约未被破坏。

- [ ] **Step 6: 检查 diff 范围和格式**

Run:

```bash
git diff --check
git diff -- SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift scripts/check_wifi_gateway_wifi_status_header.sh
```

Expected:

- `git diff --check` exit code 0。
- 业务代码 diff 只有 `wifiRSSIStatusPollDelay` 从 5 改为 10。
- contract diff 只有 5 秒断言和相关 failure message 改为 10 秒。
- 不出现 SDK、localization、resource、target 或 dependency 改动。

- [ ] **Step 7: 构建 SunSmart target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit code 0，输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 8: 构建 Archipelago target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit code 0，输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 9: 构建 SLG Sync Plus target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit code 0，输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 10: 构建 SylSmart target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: exit code 0，输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 11: 最终验证并提交实现**

Run:

```bash
git diff --check
git status --short
```

Expected: 仅显示以下已计划文件的改动：

- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- `scripts/check_wifi_gateway_wifi_status_header.sh`

Stage and commit:

```bash
git add SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift scripts/check_wifi_gateway_wifi_status_header.sh
git commit -m "fix: extend wifi rssi polling delay"
```

Expected: commit 成功，commit 不包含其他文件。
