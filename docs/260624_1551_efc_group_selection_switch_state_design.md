# EFC Select Group(s) 右侧开关状态设计

## 背景

Emergency & Fire Controller 进入 Edit 页面后，点击 Group 会进入 Select Group(s) 页面。该页面左侧用于选择关联 Group，右侧显示并控制 Group 的开关状态。

当前 EFC Edit 的真实入口已经切到共享的 `PJDeviceGroupSelectionViewController`，不是旧的 `LinkedEmerFireGroupSelectionVC`。共享页面使用 `SwitchSelectGroupsViewCell` 同时承载左侧选择状态和右侧 Group 开关状态。

## 当前问题

当前实现里，空 Group 只替换了右侧按钮图片，但没有真正禁用按钮交互。按钮回调依赖当前按钮选中态计算下一状态，配合 cell 复用和 reload，可能导致空 Group 右侧状态被视觉污染。

同时，Select all 和行点击本应只影响左侧选择状态，但 reload 后如果右侧开关状态没有完整重置，就会出现右侧开关状态随机变化的表现。

## 已确认需求

- 右侧 Group 开关是否可点击，只看 `group.nodes` 是否非空。
- Group 中有设备时，右侧展示状态与 `group.isOn` 一致，点击右侧按钮可以开/关此 Group。
- Group 中没有设备时，右侧按钮始终禁用，不允许点击后切换开/关状态。
- 点击 Group 行仅切换该 Group 的选中状态，不切换右侧开关状态。
- 点击 Select all 仅批量切换 Group 选中状态，不切换任何 Group 的右侧开关状态，也不发送 Group 开关命令。

## 方案选择

采用推荐方案：在共享 Group Selection 上增加右侧开关交互策略，由 EFC 入口显式选择“非空 Group 可控制”的策略，其他入口保持默认行为。

不采用直接修改共享默认行为，因为该页面也被 8-key switch 预添加页使用，整体改动会扩大影响面。

不采用回退到 EFC 专用旧页面，因为会恢复重复实现，后续共享修复难以覆盖 EFC。

## 设计

### 状态边界

Select Group(s) 页面需要拆分两条独立状态流：

- 左侧选择状态：由行点击、Select all、Done 回写控制。
- 右侧 Group 开关状态：由右侧按钮点击控制，代表 `group.isOn` 并发送 Group 开关命令。

行点击和 Select all 不允许修改 `group.isOn`，也不允许发送 Group 开关命令。

### EFC 入口行为

EFC 入口创建共享 Group Selection 页面时，显式传入右侧开关策略：

- `group.nodes.isEmpty == true`：右侧按钮禁用，展示 disabled 图，不响应点击，不改变按钮选中态。
- `group.nodes.isEmpty == false`：右侧按钮启用，展示 `group.isOn` 对应的 on/off 状态，点击后更新 `group.isOn` 并发送 Group 开关命令。

该判断不使用在线状态，不再依赖 `group.nodes.contains { $0.state }`。

### 共享 Cell 渲染

每次配置 cell 都必须完整重置右侧按钮：

- 重置 `isEnabled`。
- 重置 `isSelected`。
- 设置 normal、selected、disabled 视觉状态。
- 根据当前策略设置或清空点击回调。

这样可以避免 table view 复用、单行 reload、Select all 后 full reload 带来的视觉状态污染。

### 影响面

主要改动范围：

- `PJDeviceGroupSelectionContext`
- `PJDeviceGroupSelectionViewController`
- EFC Edit 页创建 Group Selection 的入口
- `SwitchSelectGroupsViewCell` 需要提供或承载统一配置职责，避免控制器直接散落设置按钮状态
- `scripts/check_efc_controller_flows.sh`

8-key switch 预添加页继续使用默认策略，行为保持现状。

## 验收标准

- EFC Select Group(s) 中，空 Group 右侧按钮不可点击，点击后视觉状态不变化，不发送 Group 开关命令。
- EFC Select Group(s) 中，非空 Group 右侧按钮状态与 `group.isOn` 一致，点击右侧按钮能切换 Group 开关。
- 点击 EFC Group 行只切换左侧选中图标，不改变右侧开关状态。
- 多次单独选择 Group、多次点击右侧开关后，再点击 Select all，只改变左侧选择状态，不随机改变右侧开关状态。
- Select all 不发送 Group 开关命令。
- 8-key switch 预添加页 Group Selection 行为不被改变。
- contract 脚本覆盖 EFC 入口必须使用新策略，空 Group 判断不能依赖在线状态。
- 验证 `git diff --check` 通过。
- 验证 SunSmart iPhoneOS build 通过。

## 后续实施计划

确认该设计后，下一步进入 implementation plan：

1. 扩展共享 Group Selection context，增加右侧开关策略。
2. 在共享选择页按策略渲染并处理右侧按钮。
3. 让 EFC Edit 入口显式使用“非空 Group 可控制”策略。
4. 补充 contract 脚本。
5. 运行静态检查、contract 和 iPhoneOS 构建验证。
