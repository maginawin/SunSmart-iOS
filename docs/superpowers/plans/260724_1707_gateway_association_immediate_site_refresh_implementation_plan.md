# Gateway 关联变化后立即刷新 Site 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gateway 关联 Spaces 的服务器拓扑发生变化后立即请求一次 `siteInfo`，确保关闭 Gateway 页面返回 Site 时无需下拉刷新即可显示正确的关联和 online 状态。

**Architecture:** 保留现有 Gateway 拓扑通知生产端，在 `SiteViewController` 中把通知消费收敛到一个私有刷新入口。Site 仍在 window 且手机网络可用时立即执行现有 `loadSiteRequest()`；否则保留 `reloadData`，由现有生命周期路径补充刷新。

**Tech Stack:** Swift、UIKit、NotificationCenter、Foundation 命令行契约测试、Bash、Xcode generic iPhoneOS build。

## Global Constraints

- 所有回复、计划和总结使用简体中文；不新增或修改用户可见文案。
- 采用已确认的方案 A，只修改 Site 对关联拓扑通知的消费逻辑。
- 服务器 `siteInfo` 继续作为 Space 关联与 Internet online/offline 的唯一权威来源。
- 不直接修改 `SpaceData.gatewayStatus`，不根据 bind/unbind 结果猜测 online/offline。
- 保留 Gateway 关联完整成功与部分成功的现有通知生产逻辑。
- 普通 Gateway 名称、APN、服务器信息、修复和设备同步不新增 `siteInfo` 请求。
- 不修改 Wi‑Fi、4G、NordicSigMeshSDK、Auth、资源、本地化、依赖或 target 配置。
- 保持改动聚焦，不重构或格式化无关代码。
- 执行方式使用 Inline Execution，不使用 subagents。
- iOS 构建直接运行 `xcodebuild`，使用 generic iPhoneOS，不使用 shell 包装、日志重定向或 Simulator。

---

## 文件结构

- Modify: `Tests/Site/SiteGatewayOnlineStateContractTests.swift`
  - 扩展现有源码契约，覆盖立即请求与生命周期回退。
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - 增加专用刷新入口，并让拓扑通知调用它。
- Create: `docs/260724_1707_gateway_association_immediate_site_refresh_summary.md`
  - 保存实施结果、验证证据和真实环境待验收项。

---

### Task 1: 用失败契约复现拓扑通知只设置标记的问题

**Files:**

- Modify: `Tests/Site/SiteGatewayOnlineStateContractTests.swift`
- Test: `scripts/check_site_gateway_online_state.sh`

**Interfaces:**

- Consumes: `SiteViewController.swift` 中现有 Gateway 通知监听区块。
- Produces: 对 `refreshSiteAfterGatewayAssociationChange()` 的源码契约。

- [ ] **Step 1: 扩展关联拓扑刷新契约**

在现有 `gatewayObservers` 的断言后加入：

```swift
require(
    gatewayObservers.contains("self?.refreshSiteAfterGatewayAssociationChange()"),
    "Gateway association topology changes must trigger the Site refresh policy"
)

require(
    source.contains("private func refreshSiteAfterGatewayAssociationChange()"),
    "Site must expose a dedicated gateway-association refresh policy"
)
let associationRefresh = section(
    in: source,
    from: "private func refreshSiteAfterGatewayAssociationChange()",
    to: "// MARK: - Request"
)
require(
    associationRefresh.contains("viewIfLoaded?.window != nil"),
    "Visible Site pages must support immediate authoritative refresh"
)
require(
    associationRefresh.contains("NetworkRequest.shared.networkable"),
    "Immediate Site refresh must require phone network availability"
)
require(
    associationRefresh.contains("loadSiteRequest()"),
    "Visible and networkable Site pages must immediately request siteInfo"
)
require(
    associationRefresh.contains("reloadData = true"),
    "Unavailable Site pages must retain the lifecycle refresh fallback"
)
```

- [ ] **Step 2: 运行契约并确认旧实现失败**

Run:

```bash
./scripts/check_site_gateway_online_state.sh
```

Expected: FAIL，首个新失败原因是：

```text
Gateway association topology changes must trigger the Site refresh policy
```

- [ ] **Step 3: 检查失败来自缺失行为**

确认测试已经成功编译，且失败位置是新增的 `require`，不是路径、源码 marker 或 Swift 编译错误。

---

### Task 2: 在拓扑通知后立即请求 Site 权威状态

**Files:**

- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift:349-372`
- Test: `Tests/Site/SiteGatewayOnlineStateContractTests.swift`

**Interfaces:**

- Consumes: `viewIfLoaded?.window`、`NetworkRequest.shared.networkable`、现有 `reloadData` 和 `loadSiteRequest()`。
- Produces: `private func refreshSiteAfterGatewayAssociationChange()`。

- [ ] **Step 1: 让拓扑通知调用专用刷新入口**

把现有监听闭包：

```swift
) { [weak self] _ in
    self?.reloadData = true
}
```

替换为：

```swift
) { [weak self] _ in
    self?.refreshSiteAfterGatewayAssociationChange()
}
```

- [ ] **Step 2: 增加立即请求与生命周期回退**

在 `addNotificationObserver()` 结束后、`// MARK: - Request` 前加入：

```swift
private func refreshSiteAfterGatewayAssociationChange() {
    guard viewIfLoaded?.window != nil,
          NetworkRequest.shared.networkable else {
        reloadData = true
        return
    }

    reloadData = false
    loadSiteRequest()
}
```

满足立即请求条件时清除 `reloadData`，避免 modal 关闭后如果生命周期再次触发而重复请求；不满足条件时保留原有回退路径。

- [ ] **Step 3: 运行契约并确认通过**

Run:

```bash
./scripts/check_site_gateway_online_state.sh
```

Expected:

```text
SiteGatewayOnlineStateContractTests passed
PASS: Site Gateway online-state source ownership checks passed.
```

- [ ] **Step 4: 检查补丁格式**

Run:

```bash
git diff --check
```

Expected: 无输出并返回 0。

- [ ] **Step 5: 提交实现**

```bash
git add Tests/Site/SiteGatewayOnlineStateContractTests.swift SunSmart/Main/Site/Controller/SiteViewController.swift
git commit -m "fix: refresh site after gateway association update"
```

---

### Task 3: 完成自动化、四品牌构建与总结

**Files:**

- Verify: `Tests/Site/SiteGatewayOnlineStateContractTests.swift`
- Verify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Create: `docs/260724_1707_gateway_association_immediate_site_refresh_summary.md`

**Interfaces:**

- Consumes: Task 2 的最终实现。
- Produces: 自动化、四品牌构建结果和真实环境验收清单。

- [ ] **Step 1: 重新运行契约与格式检查**

Run:

```bash
./scripts/check_site_gateway_online_state.sh
git diff --check HEAD~1 HEAD
```

Expected: 契约通过，格式检查无输出且返回 0。

- [ ] **Step 2: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 3: 构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: 构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 创建实施总结**

创建 `docs/260724_1707_gateway_association_immediate_site_refresh_summary.md`：

```markdown
# Gateway 关联变化后立即刷新 Site 实施总结

## 结果

- Gateway 关联拓扑发生服务器确认的完整或部分变化后，Site 会立即请求一次 `siteInfo`。
- 如果 Site 不在 window 或手机无网络，保留生命周期刷新标记。
- 返回 All Spaces 与 Favourites 后，不再依赖下拉刷新才能显示最新关联和 online 状态。
- Space 关联及 Internet online/offline 仍完全使用服务器状态，不增加本地推断。

## 验证

- Site Gateway 状态契约测试：通过。
- `git diff --check`：通过。
- SunSmart generic iPhoneOS Debug：构建成功。
- Archipelago generic iPhoneOS Debug：构建成功。
- SLG Sync Plus generic iPhoneOS Debug：构建成功。
- SylSmart generic iPhoneOS Debug：构建成功。

## 待真实环境验收

- Wi‑Fi Gateway 修改 Spaces 关联并保存，关闭 Gateway 页面后确认 All Spaces 与 Favourites 无需下拉刷新。
- 4G Gateway 执行相同流程。
- bind/unbind 部分成功时，确认 Site 展示服务器最终拓扑。
- 手机无网络时保存失败或无法刷新，恢复网络后通过现有生命周期或下拉刷新取得权威状态。

构建成功不代表 modal 生命周期、真实服务器数据传播或真机 Gateway 行为已经验收。
```

- [ ] **Step 7: 提交总结**

```bash
git add docs/260724_1707_gateway_association_immediate_site_refresh_summary.md
git commit -m "docs: summarize immediate site refresh fix"
```

- [ ] **Step 8: 核对最终工作区**

Run:

```bash
git status --short
git log -n 4 --oneline
```

Expected: 工作区无未提交文件；最新历史包含总结、实现、实现计划和设计 spec。

---

## 完成判定

只有同时满足以下条件才可声称代码修复完成：

- 新契约先在当前代码失败，再在修复后通过。
- 拓扑通知不再只设置 `reloadData`。
- Site 在 window 且手机有网络时立即调用 `loadSiteRequest()`。
- Site 不在 window 或手机无网络时仍保留 `reloadData = true` 回退。
- 普通 Gateway 数据更新不会新增 `siteInfo` 请求。
- `git diff --check` 通过。
- 四个品牌 generic iPhoneOS 构建全部成功。

真机与真实服务器验收必须单独报告，不能由契约测试或构建结果代替。
