# Edit Site Local time Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task with Inline Execution and review checkpoints. Steps use checkbox syntax for tracking.

**目标：** 将 Edit Site 的 Local time 从 Time Zone 白色选择行中移出，并按 Figma 作为透明背景的独立辅助文本展示。

**架构：** 保留现有 UIKit、SnapKit 和 Local time 生命周期，只调整 `SiteEditViewController` 的视图层级与垂直约束。使用现有源码 contract 锁定层级、尺寸和显示状态，不引入新组件或依赖。

**技术栈：** Swift、UIKit、SnapKit、Foundation-only 源码 contract、Xcode generic iPhoneOS build。

## 全局约束

- 仅修改 Edit Site Local time 的布局和对应 contract。
- 不修改用户可见文案、本地化文件、时区数据、刷新逻辑或同步行为。
- 保留当前 worktree 的全部既有改动。
- 不创建 Git commit。
- 四个品牌 target 使用相同共享源码，构建时逐一验证。

---

### Task 1：增加 Local time 视图层级回归契约

**Files:**

- Modify: `Tests/Site/SiteTimeZoneUIContractTests.swift`
- Test: `Tests/Site/SiteTimeZoneUIContractTests.swift`

**接口：**

- 输入：`SiteEditViewController.swift` 源码文本。
- 输出：可识别 Local time 已加入 `contentView`、Time Zone 行固定 44pt、Local time 与 Site Icon 顺序正确的 contract。

- [ ] 在 Edit Site contract 中增加断言：`contentView.addSubview(localTimeLabel)` 存在，`timeZoneContainer.addSubview(localTimeLabel)` 不存在。
- [ ] 增加断言：Local time 位于 Time Zone 容器之后，Site Icon 标题约束位于 Local time 之后。
- [ ] 增加断言：Time Zone 容器固定为 44pt，旧的 `timeZoneSeparator` 不再存在。
- [ ] 编译并运行 UI contract，确认它因当前旧布局失败。

运行：

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/SiteTimeZoneUIContractTests
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift
```

预期：contract 在 Local time 视图层级断言处失败。

### Task 2：实现 Figma Local time 独立布局

**Files:**

- Modify: `SunSmart/Main/Site/Controller/SiteEditViewController.swift`
- Test: `Tests/Site/SiteTimeZoneUIContractTests.swift`

**接口：**

- 保留：`refreshLocalTime()`、`startLocalTimeUpdates()`、`stopLocalTimeUpdates()` 和 `updateTimeZoneDisplay()` 的业务职责。
- 调整：`setupTimeZoneSection()` 与 `setupSiteIconSection()` 的视图层级和约束。

- [ ] 删除 `timeZoneSeparator` 属性、创建和约束。
- [ ] 将 Time Zone 容器高度固定为 44pt，并让点击按钮只覆盖该选择行。
- [ ] 将 `localTimeLabel` 添加到 `contentView`，设置为透明区域中的 20pt 辅助文本，距 Time Zone 行 8pt。
- [ ] 将 Site Icon 标题锚定到 Local time 下方；通过更新 Local time 高度和 Site Icon 间距，在未配置时收起空间并保留 20pt 区间。
- [ ] 保持 Local time 字体、颜色、本地化、格式和 timer 逻辑不变。
- [ ] 重新运行 UI contract，确认通过。

### Task 3：执行回归与构建验证

**Files:**

- Verify: `SunSmart/Main/Site/Controller/SiteEditViewController.swift`
- Verify: `Tests/Site/SiteTimeZoneUIContractTests.swift`
- Verify: `docs/260811_1535_edit_site_local_time_layout_design.md`
- Verify: `docs/260811_1535_edit_site_local_time_layout_plan.md`

- [ ] 运行完整 UI routing contract。
- [ ] 运行本地化、资源和四 target 归属 contract，确认本次未产生关联回归。
- [ ] 运行 `git diff --check`。
- [ ] 依次构建 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`，使用 Debug、generic iPhoneOS、关闭签名。
- [ ] 检查最终 diff，只包含已确认的 Local time 布局、contract 和文档记录。
- [ ] 在完成总结中区分静态/构建验证与四品牌真机视觉验收。

## 自检结果

- 需求覆盖：无背景、脱离 Time Zone 行、未配置时隐藏与收起均有对应任务。
- 范围检查：没有时区数据、文案、网络和同步逻辑改动。
- 占位符检查：无待定项。
- 类型与命名检查：继续使用现有 `localTimeLabel` 和 `updateTimeZoneDisplay()`，不引入新接口。
