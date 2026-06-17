# Site Space Others EFC Long Press Edit Plan

## 背景与事实链路

- 入口为 `Site - Space - Main - Others`，真实控制器是 `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`。
- Others 列表数据由 Dongle 与 `DeviceEmerFireStore.shared.devices(in: space)` 的 EFC 设备合并组成。
- 当前 EFC 单击逻辑：
  - `unboundDevice` 或 `syncIssueDevice`：直接打开 `LinkedEmerFireEditVC`。
  - 其他状态：打开 `EmerFireAlarmMonitorVC` 设备页。
- 当前 Others 页面已经在 `collectionView` 上挂了 `UILongPressGestureRecognizer`，但 `collectionLongPressAction` 只处理 Dongle，EFC 会被 `guard case .dongle` 过滤掉。
- EFC 设备页右上角菜单已有 Edit 入口，最终通过 `LinkedEmerFireEditVC(config:space:)` 打开编辑页，并检查 `space.deviceOperates.contains(.edit)`。

## 目标

在 `Site - Space - Main - Others` 的 EFC 设备控件上：

- 单击保持现有行为：进入 EFC 设备页，特殊未绑定/同步异常状态仍按现有逻辑进入 Edit。
- 长按 EFC 设备：直接进入该 EFC 的 Edit 页面。
- Visitor 或无 Edit 权限时不允许通过长按绕过权限，应提示 `no_permission`。
- 不改变 EFC Edit 页面内容范围，不新增字段、不改同步协议、不改 cell 视觉样式。

## 方案对比

### 方案 A：复用 Others 页面现有 collection long press

在 `DeviceOthersViewController.collectionLongPressAction` 中扩展 `DeviceOthersListItem.emergencyFireController` 分支：

- 保留 `sender.state == .began` 和 `!isEdit` 保护。
- 命中 Dongle 时保持现有跳转。
- 命中 EFC 时检查 `space.deviceOperates.contains(.edit)`。
- 通过 `makeLinkedEmerFireConfig(from:)` 构造 config，打开 `LinkedEmerFireEditVC(config:space:)`。
- iPad 继续设置 `preferredContentSize`，与现有 present 风格一致。

优点：改动最小，沿用现有列表手势；不会把手势逻辑下沉到 cell；单击与长按分支集中在同一个控制器里，便于维护。

风险：`collectionLongPressAction` 当前注释写着“跳转到开关详情”，实现时顺手改成更准确的 Others 描述即可。

### 方案 B：给 `EmerFireAlarmDeviceCell` 单独加长按回调

在 cell 中新增长按手势和 callback，由 `DeviceOthersViewController.cellForItemAt` 注入打开 Edit 的行为。

优点：EFC cell 自己拥有交互回调，看起来局部。

风险：cell 会开始感知业务动作，且与 collectionView 已有长按手势重复；复用/重用时更容易出现 callback 清理或手势叠加问题。

### 推荐

采用方案 A。当前页面已经有集合视图级长按入口，EFC 只是缺少分支；最小改动即可满足需求，并且权限、iPad 展示、config 构造都能复用页面现有逻辑。

## 实施步骤

1. 修改 `DeviceOthersViewController.swift`
   - 将 EFC 打开 Edit 的逻辑抽成一个私有方法，例如 `openEmergencyFireEdit(for:)`。
   - 方法内先检查 `space.deviceOperates.contains(.edit)`，无权限时显示 `no_permission` 并返回。
   - 构造 `LinkedEmerFireConfig`，创建 `LinkedEmerFireEditVC(config:space:)`。
   - iPad 设置 `preferredContentSize`。
   - 使用 `present(NavigationViewController(rootViewController: vc), animated: true)`，保持与当前 Others 页面跳转风格一致。

2. 收敛重复跳转代码
   - `didSelectItemAt` 中 EFC 的未绑定/同步异常分支可复用同一个 `openEmergencyFireEdit(for:)`。
   - `collectionLongPressAction` 中新增 EFC 分支，调用同一个方法。
   - Dongle 长按逻辑保持不变。

3. 增加 contract guard
   - 在 `scripts/check_efc_controller_flows.sh` 增加断言，确保 `DeviceOthersViewController.swift` 中存在 EFC 长按进入 Edit 的路由方法或调用点。
   - 继续保留现有 Edit 页面范围断言，避免本次需求被误实现成扩展 Edit 页面字段。

## 验证计划

1. 运行 EFC contract：

   `bash scripts/check_efc_controller_flows.sh`

2. 运行格式/空白检查：

   `git diff --check`

3. 运行 iPhoneOS 构建：

   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 需确认点

请确认采用推荐的方案 A：

- 长按 EFC 永远进入 Edit 页面。
- 无 Edit 权限时提示 `no_permission`，不进入只读 Edit。
- 单击行为完全保持当前逻辑，不改为进入 Edit。
