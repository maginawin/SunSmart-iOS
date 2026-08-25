# Search by Name 扩展实施与验证记录

## 结果

已将现有设备名称过滤能力扩展到 Group Members、Scheduler Devices，以及 Proximity Path Sequence / Trigger Zone 的 Manually Add 列表，同时保持 Space Lights 原有按钮资源和行为不变。

## 已实现范围

### Group Members

- 左下角增加仅图片的 30 x 30 过滤按钮。
- Sync 显示时，过滤按钮位于 Sync 右侧；Sync 隐藏时，过滤按钮占用左侧位置。
- 过滤仅改变可见设备，不修改被隐藏设备的已选状态。
- Select All 仅作用于当前可见设备，被隐藏设备保持原选择。
- Members 页面实例持有独立过滤会话，离开页面栈后随实例释放，不影响 Space Lights 的过滤参数。
- 显示设备名前缀时，同时匹配设备名和组名。

### Scheduler Devices

- 弹窗左上角增加仅图片的 30 x 30 过滤按钮，Devices 标题继续相对整个顶部栏居中。
- 过滤仅改变可见设备，不修改被隐藏设备的已选状态。
- Select All 仅作用于当前可见且可选择设备，被隐藏设备保持原选择。
- 保留编辑已有 Scheduler 时不可取消设备的原有保护。
- 每个 Devices 弹窗实例持有独立过滤会话，关闭后自动清空。
- 显示设备名前缀时，同时匹配设备名和组名。

### Path Sequence / Trigger Zone

- 过滤会话由 Path Sequence 父页面持有，Sequence 与 Trigger Zone 共用。
- 过滤只进入 Manually Add 设备列表，不进入 Quick Add、Trigger Add 或 Space Trigger Zone 的复用入口。
- 过滤按钮只在展开视图且选中 Manually Add 时显示。
- 保持原展开/收起按钮位置不变；过滤按钮位于其左侧，固定间距 16，固定大小 30 x 30。
- 被过滤隐藏的当前选中设备继续保持选中；重置或重新匹配后恢复可见选中态。
- 离开 Path Sequence 页面栈后，过滤会话随父页面实例释放。
- Manually Add 仅匹配设备原始名称。

### 共用过滤与弹窗

- 继续复用 `DeviceNameFilterSession` 的 Trim、大小写不敏感子串匹配、空输入重置和 Search 提交语义。
- 复用现有国际化文案和无匹配空状态。
- 过滤菜单支持优先显示在按钮上方；顶部空间不足时改为显示在按钮下方，以适配 Scheduler 左上角入口。
- 新入口正常状态使用 `device_filter`，过滤状态使用 `device_filter_selected`；未修改 Space Lights 的按钮资源。

## 自动化验证

以下独立 Swift 测试均已编译并执行通过：

- `DeviceNameFilterSessionTests`
- `DeviceNameFilterMenuViewContractTests`
- `DeviceNameFilterSearchViewContractTests`
- `GroupPathSequenceDeviceAddViewContractTests`
- `DeviceNameFilterExpansionContractTests`

新增扩展契约覆盖：

- 三处会话所有权和生命周期边界。
- 完整列表与可见列表分离。
- 隐藏选择保留和可见范围 Select All。
- Scheduler 不可取消设备保护。
- Group Sync 与过滤按钮相邻关系。
- Path 过滤按钮尺寸、与展开按钮的 16 点间距，以及仅 Manually Add 接入过滤。
- 顶部入口的过滤菜单上下方向回退。

`git diff --check` 已通过。

## iPhoneOS 构建验证

基于最终代码，以下 Debug、generic iPhoneOS、关闭签名构建均通过：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

构建输出仍包含工程既有的资源名称重复、Info.plist 位于 Copy Bundle Resources、FSCalendar 重复 Compile Sources 等警告；未出现本次改动导致的编译错误。

## 尚需实际 UI 验收

当前环境的 CoreDevice 服务连接失效，无法枚举或连接真机，因此本次不能完成项目要求的实际布局与手势验收。以下项目仍应在真机上验证，不能由源码契约或编译结果替代：

- Group Members 中 Sync 显示/隐藏两种状态下的按钮位置、点击区域及不遮挡。
- Scheduler 顶部标题居中、过滤按钮左对齐，以及过滤菜单向下展开。
- Path Sequence / Trigger Zone 中按钮只随 Manually Add 显示，展开按钮位置不变且两按钮视觉间距为 16。
- 三个入口的 30 x 30 图片均不缩放，正常/选中资源切换正确。
- 过滤、切换分类、Select All、隐藏选择保留、页面退出重进清空等完整交互。
- iPhone 与 iPad、英文与简体中文下的布局和文案。
