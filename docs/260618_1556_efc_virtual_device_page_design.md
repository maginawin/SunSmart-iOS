# 虚拟 EFC 设备页短按入口设计

## 背景

入口为 `Site - Space - Main - Others`。当前 EFC 列表项短按逻辑中，`unboundDevice` 和 `syncIssueDevice` 都会直接进入 `LinkedEmerFireEditVC`。这导致未绑定的虚拟 EFC 短按进入 Edit 页面。

产品期望调整为：

- 长按虚拟 EFC 仍进入 Edit 页面。
- 短按虚拟 EFC 进入虚拟 EFC 设备页。
- 虚拟 EFC 设备页只允许查看未绑定状态、进入 Edit 或删除本地虚拟设备。

当前 worktree 里已有一轮真实 EFC 删除优化：真实设备页 Delete 正在收敛到共享 cleanup + Reset 删除流程。本设计必须保护这条真实设备删除链路，同时给未绑定虚拟 EFC 单独分流。

## 目标

1. Others 页面短按未绑定虚拟 EFC 时进入 `EmerFireAlarmMonitorVC`。
2. Others 页面长按 EFC 时继续进入 `LinkedEmerFireEditVC`。
3. 虚拟 EFC 设备页顶部状态固定显示 `Unlinked`，文字样式与 `Normal State` 相同。
4. 虚拟 EFC 设备页底部四个按钮点击时都提示：
   `Not executed. Please link a device first.`
   - Identify
   - Mock fire alarm
   - Mock power loss
   - Mock restore
5. 虚拟 EFC 是否 associate with groups 不影响按钮逻辑，未绑定设备优先提示 link-device toast。
6. 虚拟 EFC 设备页右上角菜单只展示：
   - Edit：进入 EFC Edit 页面。
   - Delete：展示删除确认弹窗，message 为 `Are you sure to delete the EFC device?`。
7. 虚拟 EFC Delete 样式与虚拟 Battery power switch 一致：`notification` 标题、`Cancel + Confirm`、Confirm 为 destructive。
8. 虚拟 EFC Delete 只删除本地虚拟 EFC 配置、刷新列表并关闭设备页；不执行 EFC cleanup sync、不调用 Mesh Reset。

## 非目标

- 不修改 EFC Edit 页面字段范围。
- 不修改真实 EFC 设备页删除语义。
- 不修改 EFC associated group 同步、subscription、vendor payload 或 AppKey 逻辑。
- 不把虚拟 EFC 建成独立新页面。
- 不改 `DeviceEmerFireData.displayStatus` 的共享语义。

## 方案对比

### 方案 A：设备页内按未绑定状态分流

短按 Others 中的 EFC 默认进入 `EmerFireAlarmMonitorVC`，在设备页内部通过 `currentDevice?.bindNode == nil` 识别未绑定虚拟 EFC，并应用虚拟设备行为。

优点：

- 改动最小，复用现有 EFC 设备页布局。
- 不影响 EFC Edit 页面和真实 EFC 删除 Reset 流程。
- 能在 action 入口统一保证“未绑定设备优先提示 link-device toast”。
- 后续如果虚拟 EFC 绑定真实设备，设备页自然回到真实设备逻辑。

风险：

- 需要在菜单和按钮入口分别加未绑定分支，避免真实设备菜单项或 group-first toast 泄漏到虚拟设备页。

### 方案 B：创建独立虚拟 EFC 设备页

为未绑定虚拟 EFC 新建单独页面，只实现 Unlinked 状态、四个按钮 toast、Edit/Delete 菜单。

优点：

- 虚拟设备行为隔离更强。

缺点：

- 需要复制现有设备页 UI 和导航结构。
- 未来 EFC 设备页 UI 调整时维护成本高。
- 对当前需求来说改动过大。

### 方案 C：修改 `displayStatus` 或 Store 层语义

通过改变虚拟 EFC 的 `displayStatus` 或 Store merge 规则，使短按路由避开 Edit 分支。

优点：

- 短按入口处看起来改动少。

缺点：

- `unboundDevice` 当前同时驱动 Others 列表虚线样式、未绑定状态判断和 Edit 兜底行为。
- 改模型层容易影响 Add/Edit/Restore 或列表展示。
- 不推荐。

## 推荐方案

采用方案 A。

## 详细设计

### Others 页面短按路由

修改 `DeviceOthersViewController.collectionView(_:didSelectItemAt:)` 的 EFC 分支：

- `unboundDevice` 不再直接打开 Edit。
- 未绑定虚拟 EFC 打开 `EmerFireAlarmMonitorVC(space:device:config:)`。
- `syncIssueDevice` 建议保留现有直接进入 Edit 的行为，因为它代表真实设备已有绑定但配置需要修复，不属于虚拟设备页需求。
- 长按逻辑继续调用 `openEmergencyFireEdit(for:)`，保持“长按进入 Edit”的预期。

### 虚拟设备状态展示

`EmerFireAlarmMonitorVC.refreshRealState()` 已在 `currentDevice.bindNode == nil` 时调用 `renderUnlinkedState()`。继续把这条分支作为虚拟 EFC 设备页状态入口：

- `statusWarningView` 显示 `Unlinked`。
- 文本颜色使用 `Title_Color`，与 `Normal State` 一致。
- `currentState` 可继续使用 `.disabled` 作为无真实设备时的页面内部状态，避免新增展示状态枚举。

### 按钮行为

在以下 action 入口最前面加未绑定设备 guard：

- `identifyAction()`
- `mockFireAlarmAction()`
- `mockPowerLossAction()`
- `mockRestoreAction()`

判断条件为 `currentDevice?.bindNode == nil`。命中后：

- 展示 `Not executed. Please link a device first.`。
- 返回 `false`，不触发按钮 loading。
- 不继续检查 associated groups。
- 不发送 Mesh 命令。

这样能保证虚拟 EFC 即使配置了 associated groups，也不会显示 `Not executed. Please link a group first.` 或 `Not executed. No devices in associated groups.`。

### 右上角菜单

在 `EmerFireAlarmMonitorRouting.moreClick()` 中根据是否为未绑定虚拟 EFC 分流：

- 未绑定虚拟 EFC：只组装 Edit 和 Delete。
- 真实 EFC：保留现有权限、Information、Refresh 等逻辑。

Edit：

- 继续调用 `openEditSettings(config:)`。
- 保留 edit 权限检查，无权限时提示 `no_permission`。

Delete：

- 未绑定虚拟 EFC 使用虚拟删除流程。
- 弹窗样式对齐虚拟 Battery power switch：
  - title：`notification`
  - message：`Are you sure to delete the EFC device?`
  - actions：Cancel + Confirm
  - Confirm 使用 destructive 样式
- 确认后只调用本地删除：
  - `DeviceEmerFireStore.shared.deleteCachedDevice(device)`
  - 刷新 Others / Devices / Space 相关通知
  - 展示 `done!`
  - 延迟关闭当前设备页
- 不调用 `EmergencyFireControllerSyncPlanner.makeDeleteCleanupItems()`。
- 不调用 `deleteNodes(nodes:)`。
- 不发送 Mesh Reset。

### 本地化

现有本地化已包含：

- `Unlinked`
- `Not executed. Please link a device first.`

需要新增：

- `Are you sure to delete the EFC device?`

英文保持原文；中文可翻译为“确定要删除该 EFC 设备吗？”。

### Contract 与验证

更新 `scripts/check_efc_controller_flows.sh`，增加以下约束：

- Others 页面 EFC 短按不再把 `.unboundDevice` 直接路由到 Edit。
- Others 页面 EFC 长按仍调用 `openEmergencyFireEdit(for:)`。
- EFC 设备页存在未绑定 action guard，并且四个按钮都使用该 guard。
- 未绑定虚拟 EFC 菜单只走 Edit/Delete 分支，不包含 Information / Refresh。
- 虚拟 EFC 删除文案存在。
- 虚拟 EFC 删除不调用 cleanup sync 或 `deleteNodes(nodes:)`。

验证命令：

1. `bash scripts/check_efc_controller_flows.sh`
2. `git diff --check`
3. `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与边界

- 如果虚拟 EFC 有 associated groups，设备页仍展示组列表，但四个底部按钮必须优先提示 link-device toast。
- `syncIssueDevice` 建议继续直接进入 Edit，避免改变真实设备异常修复入口。
- 真实 EFC Delete 继续使用当前共享 cleanup + Reset 删除流程，不受虚拟删除分支影响。
- 虚拟 EFC Delete 只删除本地缓存，不会清理真实 Mesh 节点，因为虚拟 EFC 没有绑定节点。

## 验收标准

1. Others 页面长按虚拟 EFC 进入 Edit 页面。
2. Others 页面短按虚拟 EFC 进入 EFC 设备页。
3. 虚拟 EFC 设备页顶部状态显示 `Unlinked`，颜色与 `Normal State` 一致。
4. 虚拟 EFC 设备页点击 Identify / Mock fire alarm / Mock power loss / Mock restore，均提示 `Not executed. Please link a device first.`。
5. 虚拟 EFC 是否有关联 group 不影响第 4 条。
6. 虚拟 EFC 设备页右上角菜单只显示 Edit 和 Delete。
7. 虚拟 EFC 菜单 Delete 弹窗显示 `Are you sure to delete the EFC device?`，样式与虚拟 Battery power switch 删除确认一致。
8. 确认删除虚拟 EFC 后，Others 列表刷新，设备页关闭，不发 Mesh Reset。
9. 真实 EFC 设备页 Delete 仍走 cleanup + Reset 删除流程。
