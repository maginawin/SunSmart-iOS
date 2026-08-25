# Search by Name 扩展需求分析与开发方案

## 1. 分析结论

需求方向合理，现有 `DeviceNameFilterSession`、`DeviceNameFilterMenuView`、`DeviceNameFilterSearchView` 可以复用；新增入口必须使用独立的页面实例级过滤会话，不能复用或重置 `DevicesViewController` 当前持有的 Space Main 过滤会话。

需求主体已经覆盖页面、入口位置、图标状态、生命周期和 Path/Zone 共享关系。过滤后的选择语义、显示名称匹配范围、零结果空态，以及 Path 中过滤按钮与现有展开按钮的布局关系已于 2026-08-25 确认，本文已按最终确认结果更新。

当前分析基线：

- 分支：`ttl-test`
- HEAD：`de0d9ebf feat: add icons`
- 工作区：干净
- `device_filter`、`device_filter_selected` 已提交到共享 `SunSmart/Assets.xcassets`；SVG 画布为 30×30，并启用了矢量保留。

## 2. 当前实现事实

### 2.1 现有 Space Main 过滤

- `DevicesViewController` 持有一个 `DeviceNameFilterSession`，Lights、Switches、Sensors、Others 共享。
- 已有过滤规则为：首尾 Trim、忽略大小写的子串匹配；空字符串等同 Reset；输入草稿只有点击键盘 Search 才提交；Cancel 不改变已提交条件。
- 菜单和搜索输入视图已经支持 English、简体中文。
- 当前菜单定位只适合左下角入口：菜单总是尝试出现在按钮上方。Scheduler 左上角按钮没有上方空间，因此不能原样直接调用，需增加“上方不足时显示在按钮下方”的自适应定位，同时保持 Lights 的现有位置和图片不变。

### 2.2 Group Members

- 页面为 `GroupMembersViewController`，底部使用 `GroupDevicesFunctionView`。
- `GroupDevicesFunctionView` 还被 `GroupCheckViewController` 使用，因此新增过滤入口必须默认关闭，仅由 Members 显式启用。
- 当前左侧已有 Sync 按钮，且在组需要同步时可能显示；过滤按钮不能覆盖 Sync。
- 当前 `nodes` 同时承担完整业务数据与 Collection View 数据源。增加过滤后必须拆分完整集合和可见集合，否则点击、长按、修复、排序、全选会发生下标错位或误操作。
- `selectNodes` 是最终保存的成员选择结果；过滤只改变可见列表，不能删除被过滤隐藏设备的选择状态。

### 2.3 Scheduler Devices

- `ScheduleDevicesView` 是添加/编辑 Scheduler 内展示在 UIWindow 上的底部弹层，不是独立导航控制器页面。
- 每次点击 Target - Devices 都创建一个新的 `ScheduleDevicesView`。因此过滤会话由该弹层实例持有即可；Cancel、Confirm 或点击遮罩关闭后，重新打开自然为空条件。
- 当前标题居中，Select All 在右侧，左侧有足够位置放置 30×30 过滤按钮。
- 同样需要完整 `nodes` 与可见集合分离；最终 Confirm 仍返回完整的 `selectNodes`。

### 2.4 Path Sequence / Trigger Zone

- 两个 Proximity profile 最终共用 `GroupPathSequencePageController`。
- Sequence 和 Trigger Zone 分别由 `GroupPathSequenceViewController`、`GroupPathSequenceTriggerZoneController` 承载，并共同复用 `GroupPathSequenceDeviceAddView` 及其 `GroupPathSequenceManuallyAddView`。
- 最适合的状态所有者是 `GroupPathSequencePageController`：父页持有一份过滤会话并注入两个子页，切换 Sequence/Trigger Zone 时条件保留，真正退出 Path Sequence 页面实例后条件消失。
- `GroupPathSequenceDeviceAddView` 还被 Space Trigger Zone 使用。新增能力必须采用默认关闭/可选注入，不能改变当前隐藏的 Space Trigger Zone 页面。
- Manually Add 右侧现有 `unfoldBtn`，用于设备超过一行时展开/收起，当前与右侧附件按钮共用同一位置。新增过滤按钮若直接放到右侧会重叠。

## 3. 已确认的产品语义

### 3.1 会话隔离与生命周期

| 场景 | 会话所有者 | 保留条件 | 清空条件 | 与 Space Main 关系 |
| --- | --- | --- | --- | --- |
| Group Members | 当前 `GroupMembersViewController` 实例 | Push 设备详情、同步页后返回 | Pop 或 dismiss 当前 Members 页面实例 | 完全隔离，不读取或重置 Lights 条件 |
| Scheduler Devices | 当前 `ScheduleDevicesView` 实例 | 弹层保持打开期间 | Cancel、Confirm、遮罩关闭；再次打开为空 | 完全隔离 |
| Path / Zone | `GroupPathSequencePageController` | Sequence/Trigger Zone 切换，以及 Push Help 后返回 | 退出当前 Path Sequence 页面实例 | Path 与 Zone 共用；与 Lights 隔离 |

不将关键词写入 `SpaceData`、Group、Schedule、数据库、UserDefaults、通知或全局单例。

### 3.2 名称匹配

- 延续现有规则：首尾 Trim、忽略大小写、子串匹配、空提交等同 Reset，不搜索 Address 或 MAC。
- Members 与 Scheduler 的 `DevicesViewCell` 在开启 `displayDeviceNamePrefix` 时展示“组名-设备名”，因此推荐同时匹配设备名和可见组名前缀；关闭前缀时只匹配设备名。
- Path / Zone 的 Manually Add 当前只展示 `node.name`，因此只匹配设备名。
- Path / Zone 的过滤范围严格限定为 `Manually Add` 下方的设备列表；同一个关键词不得过滤或改变 Quick Add、Trigger Add 的设备集合、Path/Zone 已添加内容、候选计算或其他分类状态。

### 3.3 过滤与选择

- 过滤只改变可见集合，不改变原始候选设备和已选结果。
- Members 中，被过滤隐藏的当前 Group 成员继续保留在 `selectNodes`；用户随后 Save 时，不会仅因过滤而将其移出 Group。
- Scheduler 中，被过滤隐藏的已选 Target Device 继续保留在 `selectNodes`；用户随后 Confirm 时仍会返回这些设备。
- Path / Zone Manually Add 中，如果当前 `selectDevice` 被过滤隐藏，继续保留该选择状态；Reset 或修改条件使其重新可见时恢复选中显示。
- Members 和 Scheduler 的 Select All 只增加/取消当前过滤结果中的可选设备；隐藏设备保持原选择状态，Select All 不操作隐藏集合。
- Members 的 Save、Scheduler 的 Confirm、Path/Zone 的实际添加逻辑继续使用原有完整业务状态。
- 排序先作用于完整集合，再重新派生过滤结果；过滤不改变业务排序规则。

### 3.4 零结果空态

- 原始候选集合为空且未过滤：保留各页面原有空态和操作。
- 条件生效且无匹配结果：统一展示已有本地化文案 `No matching devices` / `没有匹配的设备`。
- 过滤按钮必须继续显示 selected 图片，以便用户通过 Reset 恢复。
- Path / Zone 的 Manually Add 保留现有内容卡布局、动态高度和分页，只替换零结果提示语义，不把过滤空态误判为整个 Path/Zone 为空。

## 4. UI 布局方案

### 4.1 通用按钮

- 视觉和约束尺寸均固定为 30×30，使用常量 30，不使用 `SCRXFrom` / `SCRYFrom` 缩放。
- 无文字；正常图片 `device_filter`，条件生效图片 `device_filter_selected`。
- 补充使用现有本地化 `Search by Name` 作为 accessibility label。
- 不修改 Lights 的 `SpaceFunctionFooterView.countBtn` 图片、尺寸或交互。

### 4.2 Members

- Sync 显示时维持现有左侧位置；过滤按钮展示在整个 Sync 组件按钮右边，二者不覆盖。
- Sync 隐藏时，过滤按钮使用 Footer 左侧入口位置。
- 过滤按钮与现有操作区垂直对齐。
- `GroupDevicesFunctionView` 新能力默认关闭，`GroupCheckViewController` 保持现状。

### 4.3 Scheduler Devices

- 在顶部栏左边距 23 放置 30×30 按钮，与右侧 Select All 的外边距对称。
- `Devices` 标题继续保持相对整个弹层水平居中，不改成过滤按钮和 Select All 之间的局部居中。

### 4.4 Path / Zone

- 仅在 `Manually Add` 被选中时显示过滤按钮。
- 现有展开/收起按钮的位置、约束和行为完全不变。
- 过滤按钮放在展开/收起按钮左侧，二者水平间隔固定为 16pt；即使当前设备不足一行、展开/收起按钮隐藏，过滤按钮仍以该按钮的原有布局位置作为锚点，不移动到最右侧。
- Quick Add / Trigger Add 下的刷新按钮仍使用原右侧位置；进入 Manually Add 后才显示过滤按钮，并按设备行数沿用原有展开/收起按钮显隐规则。
- Group Path/Zone 显式启用；Space Trigger Zone 不启用。

## 5. 开发步骤

1. 扩展共享过滤菜单的锚点定位：优先显示在按钮上方；空间不足时显示在下方；水平位置限制在安全区内。增加契约测试，证明 Lights 左下入口仍显示在上方，Scheduler 左上入口显示在下方。
2. 为 `GroupDevicesFunctionView` 增加默认关闭的 30×30 过滤按钮和回调；在 `GroupMembersViewController` 内创建独立会话、观察图片状态、派生可见节点，并全面切换 Collection View 下标、长按、修复、排序与 Select All 到可见集合。
3. 在 `ScheduleDevicesView` 内创建独立会话和可见节点集合；接入顶部过滤按钮、空态、选择、修复、控制和 Select All，关闭弹层后不保留条件。
4. 在 `GroupPathSequencePageController` 创建共享会话并注入 Sequence/Trigger Zone 两个子控制器；由 `GroupPathSequenceDeviceAddView` 只在 Manually Add 模式显示按钮，由 `GroupPathSequenceManuallyAddView` 在每次 `reloadData` 后从完整候选集合派生可见集合。过滤逻辑不接入 Quick Add、Trigger Add 或其他 Path/Zone 数据源。
5. 保持 Path 展开/收起按钮原位置，在其左侧 16pt 增加过滤按钮；保持 Group 的 `.fixedBase` 高度策略、Manually Add 的 1～3 行动态高度和分页，不改变 Quick/Trigger Add、拖拽、识别、Path/Zone 写入逻辑。
6. 复用现有本地化 Key，不新增硬编码文案；检查共享资源和源码在 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target 中的集成。

## 6. 预计修改范围

- `SunSmart/Main/Device/Filter/View/DeviceNameFilterMenuView.swift`
- `SunSmart/Main/Group/View/GroupDevicesFunctionView.swift`
- `SunSmart/Main/Group/Controller/GroupMembersViewController.swift`
- `SunSmart/Main/Timed/View/ScheduleDevicesView.swift`
- `SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift`
- `SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift`
- `SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`
- 相关 `Tests/Device`、`Tests/Group`、`Tests/Timed` 契约/逻辑测试

原则上无需修改 Lights 控制器、Space Main Footer、现有本地化文件、两套新图片内容或 SDK。

## 7. 验证方案

### 7.1 自动化与静态验证

- 现有 `DeviceNameFilterSessionTests`：Trim、空提交、大小写、子串、Reset、观察者。
- 新增会话隔离用例：Members Reset 不影响 Space Main；Path 和 Zone 共享同一条件；Scheduler 每次新弹层为空。
- Members 契约：过滤后 data source/点击/长按/修复使用可见节点；隐藏已选保持不变；Save 不因过滤移出隐藏成员；Select All 只操作可见节点；Sync 显示时保持最左且 Search 位于其右侧，Sync 隐藏时 Search 使用左侧入口位置。
- Scheduler 契约：标题仍全局居中；顶部按钮 30×30；隐藏已选保持不变且 Confirm 继续返回；Select All 只操作可见节点。
- Path 契约：只在 Manually Add 显示且只过滤 Manually Add 设备列表；Quick Add、Trigger Add 及其他内容不受影响；Path/Zone 共用；Space Trigger Zone 不启用；过滤按钮位于原位置 unfold 左侧 16pt；隐藏的 `selectDevice` 保持不变；分页和动态高度不回退。
- 菜单定位契约：底部按钮向上弹、顶部按钮向下弹、安全区夹取正确。
- 运行 `git diff --check`。

### 7.2 构建验证

按项目规则直接、串行执行 generic iPhoneOS 无签名构建：

- SunSmart
- Archipelago
- `SLG Sync Plus`
- SylSmart

构建只证明源码、资源和 target 集成，不代替交互验收。

### 7.3 实际布局与交互验收

- 真实 iPhone 与 iPad 检查 30×30、不缩放、标题居中、安全区、横竖屏/分屏（如设备支持）。
- Members：Sync 显示/隐藏、过滤零结果、Push 详情返回、退出重进、隐藏已选保持不变、过滤后 Select All、Save 不误移出隐藏成员。
- Scheduler：添加/编辑、Cancel/Confirm/遮罩关闭、隐藏已选保持不变、离线不可取消设备在过滤后的处理、Repair、退出重开。
- 两个 Proximity profile：Sequence/Trigger Zone 切换、Path/Zone 共用条件、Manually Add 一行/多行、隐藏当前选择保持不变、过滤按钮与原位置 unfold 间距、Help 往返、退出重进。
- 验证已有 Lights 过滤条件在进入和退出 Members、Scheduler、Path Sequence 后保持不变，Lights 左下角图片没有变化。

## 8. 最终确认结果

1. 过滤只改变可见列表，不清除被隐藏设备的已选状态；Select All 只操作当前可见设备，隐藏设备保持原选择。
2. Members 和 Scheduler 在启用设备名称前缀时，组名也参与匹配；Path/Zone 只匹配设备名。
3. Path/Zone 不改变展开/收起按钮位置；过滤按钮位于其左侧，间隔 16pt，且只在 Manually Add 选中时展示。
4. Push 到详情或 Help 后返回保留条件；只有真正退出对应 Members、Scheduler Devices 弹层或 Path Sequence 页面实例才清空。
5. 过滤零结果统一使用 `No matching devices`，不显示原始“无设备”引导。
6. Members 显示 Sync 时，Sync 保持在左侧，Search 位于 Sync 组件右边；Sync 隐藏时 Search 使用左侧入口位置。
7. Path/Zone 的 Search 只过滤 Manually Add 设备列表，不过滤 Quick Add、Trigger Add 或其他分类内容。

本方案已完成需求确认；业务代码实施仍需明确开始指令。
