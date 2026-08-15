# Time zone sync status 展示优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 当前会话不使用多代理。

**目标：** 让 Time zone sync status 结果弹层全宽、补齐底部白色 safe area，并让三种 Gateway 状态只通过左侧单一图标表达。

**架构：** Overlay 保持现有 safe-area 高度预算和 Footer 位置，通过独立底部背景 View 补齐 safe area；Gateway Cell 删除右侧图片组件，把状态资源和 loading 动画统一交给左侧 `gatewayImageView`。业务状态、接口和本地化不变。

**技术栈：** Swift 5、UIKit、SnapKit、UITableView、纯 Swift source contract tests、Xcode generic iPhoneOS build。

## 全局约束

- 方案以 `docs/260816_0917_time_zone_sync_status_ui_design.md` 为准。
- 不修改 Gateway 云同步 API、轮询、超时、权限过滤或终态规则。
- 不修改 `DONE` 的显隐条件、Footer 高度、按钮高度和点击逻辑。
- 不新增或修改 Auth 信息、用户可见文案、本地化、资源、target 配置或依赖。
- 保留 Dynamic Type、VoiceOver、列表滚动和 checking/loading 动画生命周期。
- 保留现有未跟踪文档，不执行 commit、push、merge 或无关格式化。

---

### Task 1：用契约锁定全宽弹层与底部白色 safe area

**文件：**

- 修改：`Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`
- 修改：`SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`

**接口：**

- `SiteEntryTimeZoneSyncOverlay.State`、`showChecking(in:)`、`showResult(_:gateways:)` 和 `onDone` 保持不变。
- 新增私有 `bottomSafeAreaBackgroundView: UIView`，不暴露新业务接口。

- [ ] **Step 1：写失败契约**

  将旧的 343pt 弹层约束断言改为以下结构断言：

  ```swift
  let resultSheetConfiguration = sourceSection(
      in: overlay,
      from: "private func setupResultSheet()",
      to: "private func configureResultShadows()"
  )
  require(
      resultSheetConfiguration.contains("make.left.right.equalToSuperview()") &&
          !resultSheetConfiguration.contains("make.width.equalTo(SCRXFrom(343))") &&
          !resultSheetConfiguration.contains("make.centerX.equalToSuperview()"),
      "The result sheet must match its ViewController container width"
  )
  require(
      overlay.contains("private let bottomSafeAreaBackgroundView = UIView()") &&
          resultSheetConfiguration.contains("make.top.equalTo(safeAreaLayoutGuide.snp.bottom)") &&
          resultSheetConfiguration.contains("make.left.right.bottom.equalToSuperview()") &&
          overlay.contains("bottomSafeAreaBackgroundView.isHidden = state == .checking"),
      "The bottom safe area must be white only for the result without moving the footer"
  )
  ```

- [ ] **Step 2：运行失败契约**

  Run：

  ```bash
  swiftc -parse-as-library Tests/Site/SiteEntryTimeZoneSyncContractTests.swift -o /tmp/SyncGatewaysEntryContractTests
  /tmp/SyncGatewaysEntryContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
  ```

  Expected：FAIL，指出结果弹层仍固定为 343pt，且没有底部白色背景 View。

- [ ] **Step 3：实现最小布局修改**

  - 在结果 Sheet 设置前添加白色 `bottomSafeAreaBackgroundView`。
  - 背景约束为 `top == safeArea.bottom`、`left/right/bottom == Overlay`。
  - `resultCardView` 改为 `left/right == Overlay`，保留 `bottom == safeArea.bottom`、top 上限与现有动态高度约束。
  - `update(state:)` 统一设置背景仅在 result 态可见。
  - 不修改 `configureDoneFooter()` 与高度计算方法。

- [ ] **Step 4：运行契约确认 GREEN**

  重复 Step 2 命令。

  Expected：PASS。

---

### Task 2：让 Gateway 行只在左侧显示状态图标

**文件：**

- 修改：`Tests/Site/SiteGatewayCloudTimeZoneUIContractTests.swift`
- 修改：`SunSmart/Main/Site/View/SiteEntryGatewayTimeZoneStatusView.swift`

**接口：**

- `SiteEntryGatewayTimeZoneStatusView.update(_:)`、高度接口和回调保持不变。
- 私有 `GatewayTimeZoneStatusCell` 删除 `statusImageView`；`gatewayImageView` 同时承担状态图标与 pushing 动画。

- [ ] **Step 1：写失败契约**

  在 `GatewayTimeZoneStatusCell` 源码区间内断言：

  ```swift
  require(
      !cell.contains("statusImageView") &&
          cell.contains("gatewayImageView.image = UIImage(named: \"site_entry_sync_loading\")") &&
          cell.contains("gatewayImageView.image = UIImage(named: \"site_entry_sync_success\")") &&
          cell.contains("gatewayImageView.image = UIImage(named: \"gateway_sync_tz_fail\")"),
      "Gateway rows must render one state icon on the left and text only on the right"
  )
  require(
      view.contains("gatewayImageView.layer.add(animation, forKey: \"siteEntrySyncLoading\")") &&
          view.contains("gatewayImageView.layer.removeAnimation(forKey: \"siteEntrySyncLoading\")"),
      "The left pushing icon must retain its rotation lifecycle"
  )
  ```

- [ ] **Step 2：运行失败契约**

  Run：

  ```bash
  swiftc -parse-as-library Tests/Site/SiteGatewayCloudTimeZoneUIContractTests.swift -o /tmp/SiteGatewayCloudTimeZoneUIContractTests
  /tmp/SiteGatewayCloudTimeZoneUIContractTests SunSmart/Main/Site/View/SiteEntryGatewayTimeZoneStatusView.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
  ```

  Expected：FAIL，指出旧实现仍保留右侧 `statusImageView`，并且 loading 动画仍在右侧图层。

- [ ] **Step 3：实现三态单图标渲染**

  - 删除 `statusImageView` 属性、初始化、复用处理和 SnapKit 约束。
  - `Pushing…`：左侧使用 `site_entry_sync_loading`，调用 `startLoadingAnimation()`。
  - `Synced`：左侧使用 `site_entry_sync_success`，不启动动画。
  - `Failed`：左侧使用 `gateway_sync_tz_fail`，不启动动画。
  - 状态文字继续靠右，并增加与名称标签之间的最小间距，避免删除右侧图标后产生歧义约束。
  - `startLoadingAnimation()` 与 `stopLoadingAnimation()` 改为操作 `gatewayImageView.layer`。

- [ ] **Step 4：运行契约确认 GREEN**

  重复 Step 2 命令。

  Expected：PASS，并保留既有 Dynamic Type、44pt minimum row baseline 与 VoiceOver 断言。

---

### Task 3：组合回归与构建验证

**文件：**

- 不新增生产文件。
- 只在验证发现本次改动导致的问题时修改 Task 1/2 所列文件。

- [ ] **Step 1：运行完整 Gateway timezone focused suite**

  Run：`./scripts/check_site_sync_gateways.sh`

  Expected：退出码 0，输出 `SiteSyncGateways checks passed`。

- [ ] **Step 2：检查 diff 与格式问题**

  Run：

  ```bash
  git diff --check
  git status --short
  ```

  Expected：`git diff --check` 退出码 0；改动仅包含本计划列出的测试、View 和两份新文档，原有四份未跟踪文档保持不变。

- [ ] **Step 3：检查共享 target membership**

  检查 `SiteEntryTimeZoneSyncOverlay.swift` 与 `SiteEntryGatewayTimeZoneStatusView.swift` 在 `SunSmart.xcodeproj/project.pbxproj` 中的 Sources membership，确定受影响品牌 target。

- [ ] **Step 4：执行 generic iPhoneOS 构建**

  Run：

  ```bash
  xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
  ```

  Expected：退出码 0。若 Sources membership 表明其他品牌 target 独立编译相同文件，再串行验证对应 scheme，避免并行 Xcode build 锁冲突。

- [ ] **Step 5：记录未覆盖的视觉验收**

  自动化不能证明真机视觉结果。交付时明确保留以下人工验收：375pt 与更宽设备上的外层全宽、Home Indicator 区域白色、`DONE` 位置不变，以及三种 Gateway 状态切换时左侧图标与 pushing 旋转动画。

