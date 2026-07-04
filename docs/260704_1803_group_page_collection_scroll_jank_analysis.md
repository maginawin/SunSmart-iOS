# Group 页面设备列表滚动卡顿根因分析

## 背景

- 入口：Site > Space > Group 列表，长按一个设备数量为 83 的 group 后进入 `GroupViewController`。
- 现象：进入 group 页面后，滑动页面内设备列表 collection view 时明显卡顿。
- 参考日志：`/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/fix/enter group log.txt`。

## 日志证据

日志共 3595 行，关键特征如下：

- 前 2594 行主要是 Auto Layout 冲突，`Unable to simultaneously satisfy constraints` 出现 96 次。
- 相关冲突全部指向 `DeviceUpDownRatioControlView` / `UpDownRatioQuickButtonsView`，涉及文件行号集中在 `DeviceUpDownRatioControlView.swift#50`、`#72`、`#78`、`#79`、`#81`、`#176`、`#189`、`#190`。
- 冲突中出现 `_UITemporaryLayoutWidth == 0`、`_UITemporaryLayoutHeight == 0`，也出现外层页面宽度为 393 时，quick buttons 固定宽度和间距无法满足的情况。
- 最后一条约束冲突之后才开始出现密集 `SensorStatus` 日志：`SensorStatus(values:)` 共 256 次，`message:SensorStatus` 共 121 次，涉及 22 个 message source。
- `SensorStatus` 的 opcode 是 `0x52`，payload 多为 `A00900` / `A00901`，即 Presence Detected 状态频繁上报到 group address `0xC000`。

## 代码链路

### 进入页面

`GroupViewController.viewDidLoad()` 会调用 `setupUI()` 和 `bindSliderAciton()`，`viewWillAppear()` 会调用 `updateUI()`，并把 `MeshLibManager.manager.messageDelegate` 指向当前页面。

`setupUI()` 中：

- collection view 使用 `AlignCenterFlowLayout`，横向分页。
- iPhone 默认 `columnNum = 3`、`rowNum = 3`，83 个设备约为 10 页。
- 页面同时创建 `DeviceUpDownRatioControlView`，初始隐藏，但仍加入 `contentView` 并参与约束布局。

### 设备列表

`GroupViewController.collectionView(_:cellForItemAt:)` 每个 item 使用 `GroupDeviceViewCell`。

`GroupDeviceViewCell` 继承 `DevicesViewCell`，每次设置 `device` 时会：

- 更新图片、背景、名称、进度条、文本颜色。
- 多次用 SnapKit 更新 icon 约束。
- 触发 `AdaptiveTextView` 文本自适应计算。
- 更新 `CustomProgressView` 进度。

这些操作单次不一定很重，但在高频刷新下会累积到主线程。

### 消息回调

`GroupViewController.didReceiveMessage` 里：

- 先处理传感器消息，`SensorStatus` 会调用 `sensorView?.reloadSensorData(...)`。
- 然后对 source node 执行 `node.updateData(message:)`。
- 如果 source node 属于当前 group，或消息目标是 all nodes，或是绑定到当前 group 的 switch action，就进入 UI 更新。
- 普通非 switch action 会调用 `reloadCollectionItem(node:)`。

`reloadCollectionItem(node:)` 的问题是：

- 先在 `group.nodes` 中查找 node index。
- 如果 cell 可见，则直接设置 cell 的 `device`。
- 无论 cell 是否可见，都会继续更新 group 级 UI：
  - `onoffBtn.isEnabled`
  - `group.isOn`
  - `group.lightness`
  - `updateControlPanel()`
  - `updateUpDownRatioUI()`

这些 group 级 UI 更新会反复读取或过滤 `group.nodes`。

### Group 聚合属性

`Group.lightness`、`Group.isOn`、`supportLightness`、`effectiveSupportCct`、`effectiveCctRange` 等属性会遍历 `nodes`。

`GroupViewController` 自己的计算属性也会遍历 `group.nodes`：

- `groupControlCCTNodes`
- `showsGroupControlCCT`
- `currentGroupCCTRange`
- `upDownRatioNodes`
- `showsUpDownRatioModeButton`

因此在 83 个设备的 group 中，每条 mesh message 都可能触发多轮 O(n) 节点扫描。

### Layout 放大点

`AlignCenterFlowLayout.prepare()` 每次会遍历全部 item，为每个 item 重建 layout attributes。83 个 item 本身不算极端，但在 `reloadData()`、`reloadItems()` 或布局失效频繁发生时，会线性放大。

`layoutAttributesForElements(in:)` 也通过过滤完整 `attrubutesArray` 返回可见区域 attributes，滚动期间会被频繁调用。

## 根因判断

导致滚动卡顿的是多个因素叠加，按影响优先级如下：

1. `DeviceUpDownRatioControlView` 的 quick buttons 布局约束有确定冲突。
   - 5 个 quick buttons 使用固定宽度和固定高度。
   - stack view 贴满父 view。
   - 页面初始或隐藏布局阶段父 view 临时宽高为 0，必然冲突。
   - 在 393 宽设备上，扣除 collection view 左右约束后，quick buttons 的固定宽度加 stack spacing 也会超出可用宽度。
   - 约束冲突会让 Auto Layout 反复求解、打断约束并打印大量日志，这是明确的主线程开销。

2. Group 页消息刷新粒度过粗。
   - 大量 presence sensor publish 进入当前 group 页面。
   - 每条 group 内 node 消息都会触发 `reloadCollectionItem(node:)`。
   - 即使目标 cell 不可见，也会更新 group 级控制面板和 up/down ratio UI。
   - 这会在滚动期间持续插入 UI 工作，和 collection view 滚动抢主线程。

3. 83 个设备把每次刷新成本放大。
   - collection view 分页约 10 页。
   - `AlignCenterFlowLayout.prepare()` 和多个 group 聚合 getter 都是按 `group.nodes` 线性计算。
   - 单次 O(n) 不严重，但 121 条 `message:SensorStatus` / 256 条 `SensorStatus(values:)` 叠加后就明显。

4. cell 配置本身有额外布局和文本计算成本。
   - `DevicesViewCell.device` 会更新 SnapKit 约束、图片、进度条和自适应文本。
   - `AdaptiveTextView.layoutSubviews()` 会重复做 attributed text bounding 计算。
   - 这不是第一根因，但会放大滚动中的掉帧。

## 结论

这个问题真实存在，且主要不是蓝牙 Mesh 收包慢，也不是 collection view 一次性渲染了 83 个 cell。

更准确的根因是：Group 页在大 group 下把高频 sensor publish 转化成高频主线程 UI 刷新；这些刷新又触发多个 group-level O(n) 计算和 `DeviceUpDownRatioControlView` 的约束冲突。进入页面时先被大量 Auto Layout 冲突拖慢，随后滚动过程中继续被 sensor message 驱动的 UI 更新打断，因此设备数量越多、sensor publish 越密集，卡顿越明显。

## 后续修复方向

建议按以下顺序处理：

1. 先修 `DeviceUpDownRatioControlView` 约束冲突。
   - quick buttons 不应在父 view 宽高为 0 时强制 `layoutIfNeeded()`。
   - 5 个按钮的固定宽度和 spacing 需要能适配 iPhone 可用宽度。
   - hidden 状态下不应反复刷新内部 quick buttons 布局。

2. 收紧 `reloadCollectionItem(node:)` 的刷新范围。
   - 不可见 cell 不需要立刻刷新 cell UI。
   - 非 light control 相关消息不应每次都更新 group control panel 和 up/down ratio control。
   - sensor-only 消息优先只更新 `GroupSensorView`。

3. 对高频 sensor publish 做 UI 合并或节流。
   - 同一 run loop 或短时间窗口内合并多条 sensor update。
   - 滚动期间避免立即执行非必要 collection item reload。

4. 缓存 group 页面常用派生数据。
   - 例如 group node address -> index、CCT nodes、up/down ratio nodes、support flags。
   - 只在 group 成员变化或设备 capability 变化时重建。

5. 降低 cell 配置成本。
   - 避免每次 `device` 设置都无差别更新 SnapKit 约束。
   - 对 `AdaptiveTextView` 的重复 text fitting 做输入和 bounds 未变化时的短路。

