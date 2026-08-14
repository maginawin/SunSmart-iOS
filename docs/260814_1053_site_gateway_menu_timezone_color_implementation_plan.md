# Site Gateway 菜单待同步名称颜色优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 将 `SiteGatewaysMenuView` 中待同步 Gateway 名称改为 `#FFD230`，同时保持横向 Gateway 列表及其他 UI 行为不变。

**Architecture:** 保留 `GatewayListView.swift` 中现有横向列表待同步颜色，新增菜单专用颜色常量；菜单仅根据现有 `needsTimeZoneSync` 展示字段选择颜色，不改变业务状态计算与数据流。

**Tech Stack:** Swift、UIKit、现有 Swift 源码契约测试、xcodebuild。

## 全局约束

- 不修改时区待同步 Gateway 的判定逻辑。
- 横向 `GatewayListView` 待同步名称继续使用 RGB `(187, 77, 0)`。
- `SiteGatewaysMenuView` 待同步名称使用 RGB `(255, 210, 48)`。
- 普通 Gateway、Add Gateway 和其他控件保持现状。
- 不修改本地化、资源、target 配置或依赖。
- 不执行 commit、push 或 merge。

---

### Task 1：拆分菜单待同步名称颜色

**Files:**

- Modify: `Tests/Site/SiteGatewayTimeZoneNameColorContractTests.swift`
- Modify: `SunSmart/Main/Site/View/GatewayListView.swift`
- Modify: `SunSmart/Main/Site/View/SiteGatewaysMenuView.swift`

**Interfaces:**

- Consumes: `GatewayMenuData.needsTimeZoneSync` 与 `SiteGatewayTimeZoneSyncAppearance`。
- Produces: 菜单专用待同步名称颜色常量，以及菜单 Gateway 行的独立颜色分支。

- [ ] **Step 1: 先更新失败契约**

  在现有名称颜色契约中增加以下要求：横向待同步颜色仍为 `RGB(187, 77, 0)`；新增菜单待同步颜色 `RGB(255, 210, 48)`；菜单待同步分支必须引用菜单专用颜色。

- [ ] **Step 2: 验证 RED**

  单独编译并运行 `SiteGatewayTimeZoneNameColorContractTests`。预期因生产代码尚无菜单专用颜色而失败，失败点应明确指向菜单颜色契约。

- [ ] **Step 3: 最小实现**

  在 `SiteGatewayTimeZoneSyncAppearance` 中新增菜单专用常量，值为 `RGB(255, 210, 48)`；将 `SiteGatewaysMenuView` 待同步名称分支从现有横向颜色改为菜单专用颜色。不得改变其他分支。

- [ ] **Step 4: 验证 GREEN**

  重新运行单项契约，预期通过；随后运行 `scripts/check_site_sync_gateways.sh`，预期全部 Site 时区同步契约通过。

- [ ] **Step 5: 构建与范围复核**

  依次以 generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO` 构建 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`；运行 `git diff --check`，并确认 `SyncGatewayCell`、本地化、资源和 target 配置无改动。

## 自检

- 计划覆盖两个场景的独立颜色、普通状态回退、范围限制与验证要求。
- 无待定项或模糊占位符。
- 类型与现有 `needsTimeZoneSync` 数据流一致，不新增业务模型字段。
