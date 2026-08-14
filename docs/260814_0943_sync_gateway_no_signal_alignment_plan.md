# SyncGatewayCell 无信号文案对齐实施计划

> **执行要求：** 使用 `superpowers:executing-plans` 在当前会话按任务执行；不启用 subagents。步骤使用复选框跟踪。

**目标：** 保持有信号状态的现有布局，并让无信号状态下的 `No signal` 文案左边与 `nameLabel` 左边对齐。

**架构：** 信号状态仍由 `SyncGatewayItemState.rssi` 与 `isNoSignal` 决定。`SyncGatewayCell` 在每次 `update(item:action:)` 时同步更新信号内容和 `signalLabel` 的左约束，确保状态切换和视图复用不会遗留旧布局。

**技术栈：** Swift、UIKit、SnapKit、现有 Swift source contract test、Xcode generic iPhoneOS build。

## 全局约束

- 仅调整 `SyncGatewayCell` 的信号文案横向约束及对应测试。
- 保留用户现有的 `gateway_sync_tz_fail` 资源和图标引用改动。
- 不修改 RSSI/No signal 判定、本地化、字体、颜色、尺寸、按钮或同步状态。
- `SyncGatewayCell.swift` 由 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target 共享。
- 不自动创建 Git commit。

---

### Task 1：为两种信号布局建立回归保护并实施最小修复

**文件：**

- 修改：`Tests/Site/SyncGatewaysUIContractTests.swift`
- 修改：`SunSmart/Main/Site/View/SyncGatewayCell.swift`
- 验证：`scripts/check_site_sync_gateways.sh`

**接口：**

- 输入：`SyncGatewayCell.update(item:action:)` 接收的 `SyncGatewayItemState.rssi` 与 `isNoSignal`。
- 输出：新增私有布局方法 `updateSignalLabelConstraints(showsSignal: Bool)`，只负责选择 `signalLabel` 的左锚点并保留公共的垂直和右侧约束。

- [x] **Step 1：编写失败的布局 contract test**

在 `SyncGatewaysUIContractTests` 中把 Gateway 失败图标断言同步为用户当前使用的 `gateway_sync_tz_fail`，然后新增以下布局契约：

```swift
require(gatewayCell.contains("updateSignalLabelConstraints(showsSignal: true)"))
require(gatewayCell.contains("updateSignalLabelConstraints(showsSignal: false)"))
require(gatewayCell.contains("make.left.equalTo(signalView.snp.right).offset(SCRXFrom(6))"))
require(gatewayCell.contains("make.left.equalTo(nameLabel)"))
```

- [x] **Step 2：运行测试并确认按预期失败**

编译并运行现有 `SyncGatewaysUIContractTests`。预期：因生产代码尚不存在 `updateSignalLabelConstraints(showsSignal:)` 或无信号左对齐约束而失败；不能因旧图标名称断言失败。

- [x] **Step 3：实施最小布局修复**

在有信号和无信号分支中分别调用：

```swift
updateSignalLabelConstraints(showsSignal: true)
updateSignalLabelConstraints(showsSignal: false)
```

将 `setupUI()` 中 `signalLabel` 的初始约束改为调用私有方法，并实现：

```swift
private func updateSignalLabelConstraints(showsSignal: Bool) {
    signalLabel.snp.remakeConstraints { make in
        if showsSignal {
            make.left.equalTo(signalView.snp.right).offset(SCRXFrom(6))
        } else {
            make.left.equalTo(nameLabel)
        }
        make.centerY.equalTo(signalView)
        make.right.lessThanOrEqualTo(actionButton.snp.left).offset(SCRXFrom(-8))
    }
}
```

- [x] **Step 4：运行 focused test 并确认通过**

重新编译并运行 `SyncGatewaysUIContractTests`。预期输出：`SyncGatewaysUIContractTests passed`。

- [x] **Step 5：运行完整 Sync Gateways 检查**

运行 `scripts/check_site_sync_gateways.sh`。预期所有模型、状态、协调器、UI contract 和本地化检查通过。

- [x] **Step 6：检查补丁质量**

运行 `git diff --check`，并只读检查 `git diff`，确认没有覆盖 `gateway_sync_tz_fail` 改动、没有新增 Auth 信息、没有无关格式化。

- [x] **Step 7：验证四个共享 target**

依次执行以下 generic iPhoneOS Debug 构建，均使用 `CODE_SIGNING_ALLOWED=NO`：

1. SunSmart
2. Archipelago
3. SLG Sync Plus
4. SylSmart

预期四次构建均以 `BUILD SUCCEEDED` 结束。该结果只证明静态契约和编译，不替代真机对有信号/无信号状态切换的视觉验收。
