# Group Control Up/Down Ratio 设计

## 背景

当前 group control page 只有 OnOff button 和 AUTO button。单灯 up/down light control page 已有 `DeviceUpDownRatioControlView`，用于编辑 `Up / Down Ratio`，并通过 `Node.PreConfiguration.upRatio` 持久化到本地数据库。

本次需求是在 group control page 中，当组内包含任意 up/down light 时，在 AUTO button 右侧增加 up/down ratio mode button。选中该按钮后，在 `controlPanelView` 上方显示与单灯页一致的 `Up / Down Ratio` 控件，并将编辑结果持久化到组内所有 up/down light 成员。

本次只规划 UI、状态和本地持久化，不新增 Mesh 命令下发。后续命令功能可直接读取每个成员节点的 `upRatio` / `downRatio`。

## 目标

- 组内没有 up/down light 时，group control page 保持现有 OnOff button + AUTO button 展示方式。
- 组内包含任意 up/down light 时，在 AUTO button 右侧增加 up/down ratio mode button。
- up/down ratio mode button 默认未选中，使用资源 `up down ratio button - unselected`。
- up/down ratio mode button 选中后，使用资源 `up down ratio button - selected`，并在 `controlPanelView` 顶部显示 `DeviceUpDownRatioControlView`。
- `DeviceUpDownRatioControlView` 默认值为 50/50。
- 当前 `GroupViewController` 从子页面返回时保持 ratio mode button 的选中态和 ratio 值。
- 左右滑切换 group 时重置为未选中，并将 ratio 值恢复为 50/50。
- ratio 控件的修改影响组内所有 `supportsUpDownRatioControl` 的节点，并持久化到每个节点的 `preConfiguration`。

## 非目标

- 不新增 Mesh 下发命令。
- 不修改 `Node.supportsUpDownRatioControl` 的能力判断规则。
- 不修改单灯页 `DeviceLightViewController` 的 ratio 控件行为。
- 不改 Scene、Profile、batch control 或其他 group 入口的语义。
- 不给非 up/down light 节点写入 `upRatio`。

## 设计来源

- 默认两按钮布局参考 Figma `130:9406`。
- 包含 up/down light 的三按钮布局参考 Figma `130:9338`。
- ratio button 选中态参考 Figma `130:9382`。
- ratio 控件参考 Figma `118:13930`，并复用现有 `DeviceUpDownRatioControlView`。

## 架构

改动集中在 `GroupViewController`。

新增 group 页局部状态：

- `isUpDownRatioModeSelected`：控制 ratio mode button 选中态，以及 ratio 控件是否显示。
- `groupUpRatioValue`：当前 group 页显示和写入的 up ratio，默认 50。

新增 group 页局部计算：

- `upDownRatioNodes`：`group.nodes.filter { $0.supportsUpDownRatioControl }`。
- `showsUpDownRatioModeButton`：`!upDownRatioNodes.isEmpty`。

不新增 group model 字段。ratio 的最终持久化仍落在每个成员节点自己的 `Node.PreConfiguration.upRatio` 上。

## UI 行为

### 无 up/down light

`showsUpDownRatioModeButton == false` 时，保持当前布局：

- OnOff button
- AUTO button
- `controlPanelView`

不创建可见 ratio button，也不显示 `DeviceUpDownRatioControlView`。

### 有 up/down light

`showsUpDownRatioModeButton == true` 时：

- OnOff button、AUTO button、up/down ratio mode button 按 Figma 形成三按钮布局。
- ratio mode button 在 AUTO button 右侧。
- 默认未选中，图标为 `up down ratio button - unselected`。
- 点击后切换选中态。
- 选中时图标为 `up down ratio button - selected`，并显示 `DeviceUpDownRatioControlView`。
- 再次点击取消选中，隐藏 `DeviceUpDownRatioControlView`，`controlPanelView` 回到现有顶部位置。

button 的位置约束需要兼容 iPhone 与 iPad。iPhone 按 Figma 的 40pt 间距组织；iPad 保留当前 group 页 56pt button 尺寸风格，并采用对应比例的间距。

## 生命周期

新创建 `GroupViewController` 时：

- `isUpDownRatioModeSelected = false`
- `groupUpRatioValue = 50`

从子页面返回当前 `GroupViewController` 时：

- 保持 `isUpDownRatioModeSelected`
- 保持 `groupUpRatioValue`

左右滑切换到另一个 group 时：

- 重置 `isUpDownRatioModeSelected = false`
- 重置 `groupUpRatioValue = 50`
- 重新根据新 group 的 `upDownRatioNodes` 判断是否显示 ratio mode button。

## 数据流

`DeviceUpDownRatioControlView` 的输入值来自 `groupUpRatioValue`，默认 50。

用户拖动 slider 时：

1. 更新 `groupUpRatioValue`。
2. 将值写入所有 `upDownRatioNodes` 的 `node.upRatio`。
3. 保持 UI 实时刷新。

用户结束拖动或点击 quick button 时：

1. 更新 `groupUpRatioValue`。
2. 将值写入所有 `upDownRatioNodes` 的 `node.upRatio`。
3. 对每个 up/down light 节点调用 `node.preConfiguration.save(meshUUID:nodeAddress:)`。

如果某个节点缺少 `meshUUID`，只更新内存值，不弹 HUD，不中断页面交互。

## 刷新同步

`updateUI()` 负责刷新：

- ratio mode button 是否隐藏。
- ratio mode button 图标状态。
- `DeviceUpDownRatioControlView` 是否隐藏。
- `DeviceUpDownRatioControlView.upValue`。
- `controlPanelView` 顶部约束。

以下入口需要保持 ratio UI 同步：

- `viewWillAppear`
- `updateUI`
- `updateControlPanel`
- OnOff 操作后
- AUTO 操作后
- brightness / CCT slider 和输入弹窗变更后
- 设备状态消息刷新后
- 左右滑切 group 后

## 错误处理

- 无 up/down light：不展示新增入口，不产生保存行为。
- Mesh 未连接：不影响 ratio 本地编辑；ratio 保存是本地预配置行为，不依赖 Mesh 下发。
- Emergency manual control blocked：保持现有亮度、CCT、OnOff 阻断逻辑；ratio 本地编辑不新增阻断。
- 保存失败：不弹错误，不回滚内存值；后续可通过单灯页或再次操作覆盖保存。

## 测试计划

手动验证：

- 无 up/down light 的组保持现有两按钮布局。
- 有 up/down light 的组显示第三个 ratio mode button。
- ratio mode button 默认未选中。
- 点击 ratio mode button 后图标切换为 selected，并显示 `DeviceUpDownRatioControlView`。
- 再次点击后图标回到 unselected，并隐藏 ratio 控件。
- 从子页面返回时保持当前选中态和 ratio 值。
- 左右滑切换 group 后重置为未选中和 50/50。
- 修改 group ratio 后，组内所有 up/down light 单灯页显示相同 ratio。
- 非 up/down light 成员不受影响。

命令验证：

- `git diff --check`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
