# Sync Gateways 底部分隔线移除实施计划

> **执行要求：** 使用 `superpowers:executing-plans` 在当前会话逐步执行；不启用 subagents。步骤使用复选框跟踪。

**目标：** 移除 `SyncGatewaysViewController` 的滚动区域与底部操作栏之间由 `bottomActionBar` 主动绘制的淡蓝色分隔线。

**架构：** 保留控制器现有的 `scrollView.bottom == bottomActionBar.top` 约束，只删除 `SyncGatewaysBottomActionBar` 内负责分隔线的子视图。通过现有源码契约测试锁定底部操作栏不再创建 divider，并使用 generic iPhoneOS 构建验证共享 target 编译不受影响。

**技术栈：** Swift、UIKit、SnapKit、现有 Swift source contract test、Xcode generic iPhoneOS build。

## 全局约束

- 只移除 `SyncGatewaysBottomActionBar` 顶部的淡蓝色 divider。
- 保留白色背景、Done 按钮尺寸、操作栏总高度和控制器约束。
- 不修改本地化、资源、target 配置或依赖。
- 保留工作区中现有未提交改动，不自动创建实现提交。

---

### Task 1：建立回归契约并实施最小修复

**文件：**

- 修改：`Tests/Site/SyncGatewaysUIContractTests.swift`
- 修改：`SunSmart/Main/Site/View/SyncGatewaysSupportingViews.swift`
- 验证：`scripts/check_site_sync_gateways.sh`

**接口：**

- 输入：`SyncGatewaysBottomActionBar.init(frame:)` 的视图初始化流程。
- 输出：底部操作栏只保留白色背景与 Done 按钮，不再创建或约束顶部 divider。

- [x] **Step 1：编写失败的源码契约**

在确认 `SyncGatewaysBottomActionBar` 类型存在后，截取该类型对应的源码，并断言其中不包含 `divider`：

```swift
let bottomActionBarSource = supportingViews.components(
    separatedBy: "final class SyncGatewaysBottomActionBar: UIView"
).last ?? ""
require(
    !bottomActionBarSource.contains("divider"),
    "Bottom action bar must not draw a top divider"
)
```

- [x] **Step 2：运行 focused test 并确认按预期失败**

运行 `scripts/check_site_sync_gateways.sh` 中 `SyncGatewaysUIContractTests` 对应的 `swiftc` 编译和可执行文件命令。预期失败信息为 `Bottom action bar must not draw a top divider`，证明契约能够捕获当前线条。

- [x] **Step 3：实施最小修复**

从 `SyncGatewaysBottomActionBar.init(frame:)` 删除以下完整逻辑，不调整其余代码：

```swift
let divider = UIView()
divider.backgroundColor = RGB(193, 207, 226)
addSubview(divider)
divider.snp.makeConstraints { make in
    make.top.left.right.equalToSuperview()
    make.height.equalTo(0.5)
}
```

- [x] **Step 4：重新运行 focused test 并确认通过**

重复 Step 2 的命令。预期输出：`SyncGatewaysUIContractTests passed`。

- [x] **Step 5：运行完整 Sync Gateways 检查**

运行 `scripts/check_site_sync_gateways.sh`。预期所有模型、状态、协调器、UI contract 和本地化检查通过。

- [x] **Step 6：检查补丁质量**

运行 `git diff --check` 并只读检查相关文件 diff，确认仅增加回归契约、删除 divider，且没有覆盖工作区中原有改动。

- [x] **Step 7：验证主 target 编译**

执行 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。预期 `BUILD SUCCEEDED`；该结果证明静态契约和编译通过，不替代真机视觉验收。
