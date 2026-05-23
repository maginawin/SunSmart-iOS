# PJEightKeySwitchMonitorVC 顶部电池栏 UI 分析与修复计划

## 背景

本次分析对象是 `PJEightKeySwitchMonitorVC` 导航栏下方的电池信息控件，实际布局实现位于：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorHeaderView.swift`

目标展示顺序：

- battery icon
- battery level
- Status:
- battery status
- battery updated date-time
- refresh button

## 当前实现

`PJEightKeySwitchMonitorVC` 中 `headerView` 宽度与屏幕同宽，高度为 `SCRYFrom(24)`，顶部距离 safe area 为 `SCRYFrom(14)`。

`PJEightKeySwitchMonitorHeaderView` 当前约束如下：

- `batteryIconView.left = superview.left + SCRXFrom(24)`
- `batteryIconView.width = height = SCRXFrom(20)`
- `batteryLabel.left = batteryIconView.right + SCRXFrom(6)`
- `statusPrefixLabel.left = batteryLabel.right + SCRXFrom(24)`
- `statusValueLabel.left = statusPrefixLabel.right + SCRXFrom(4)`
- `refreshButton.right = superview.right - SCRXFrom(24)`
- `refreshButton.width = height = SCRXFrom(30)`
- `updatedLabel.right = refreshButton.left - SCRXFrom(23)`

## 对照结论

### 符合项

- battery icon 与屏幕左边间隔 24：基本符合现有项目缩放体系，当前为 `SCRXFrom(24)`。
- refresh button 与屏幕右边间隔 24：基本符合现有项目缩放体系，当前为 `SCRXFrom(24)`。

### 不符合项

- battery level 与 battery icon 右左间隔要求为 4，当前为 6。
- status 与 battery level 右左间隔要求为 24，当前已按方案 B 改为 `SCRXFrom(24)`。
- battery updated date-time 与 status 右左间隔要求为 24，当前已按方案 B 建立 date-time 左侧与 status 右侧之间的约束。
- battery updated date-time 与 refresh button 间隔要求为 4，当前为 23。
- 屏幕宽度不够时需要压缩 battery updated date-time，当前 `updatedLabel` 只有右侧约束，没有左侧下限、宽度上限、压缩优先级与截断策略，不能保证优先压缩更新时间，也可能和 status 文本发生重叠。

## 主要风险

当前布局是左侧文本链和右侧更新时间链分别独立布局：

- 左侧链：battery icon -> battery level -> Status: -> battery status。
- 右侧链：battery updated date-time -> refresh button。

两条链之间没有约束关系。只要状态文本、更新时间文本、本地化文案或屏幕宽度变化，就可能出现间距不稳定或内容重叠。该问题不会通过调整单个 offset 完整解决，必须补齐左侧链与右侧链之间的约束关系。

## 可选方案

### 方案 A：保留现有 UILabel 结构，只修 SnapKit 约束

做法：

- 将 battery level 左侧间距改为 4。
- 将 `Status:` 左侧间距改为 24。
- 将 refresh button 右侧间距保持 24。
- 将 updated date-time 右侧间距改为 refresh button 左侧 4。
- 为 updated date-time 增加左侧约束：等于 battery status 右侧 24。
- 设置 updated date-time 单行、尾部截断，并降低水平抗压缩优先级。
- 设置 battery、status 相关 label 的水平抗压缩优先级高于 updated date-time。

优点：改动最小，贴合现有实现。

缺点：`Status:` 与 status value 仍是两个独立 label，后续如果要整体复用 status 区域，结构不够明确。

### 方案 B：引入 status 容器，将 `Status:` 与 status value 作为一个整体

做法：

- 新增 `statusContainerView` 或水平 `UIStackView` 包住 `statusPrefixLabel` 与 `statusValueLabel`。
- battery level 到 status 容器左侧为 24。
- status 容器内部保留 `Status:` 与 status value 的 4 间距。
- updated date-time 左侧等于 status 容器右侧 24。
- updated date-time 右侧等于 refresh button 左侧 4，并优先压缩 updated date-time。

优点：语义最清晰，能把 status 作为用户需求中的一个整体处理。

缺点：比方案 A 多一个容器或 stack view，改动略多。

### 方案 C：整个顶部栏改为 UIStackView，并使用 spacer 处理弹性宽度

做法：

- 使用一个水平 stack 管理所有元素。
- 固定 icon、refresh button 与各固定间距。
- 在 updated date-time 前后用约束或 spacer 控制压缩行为。

优点：整体结构规则统一。

缺点：现有 SnapKit 精确右边界和中间压缩规则更适合直接约束；使用 stack view 反而需要额外处理 30 与 4 的混合固定间距，以及 updated date-time 的优先压缩，收益不明显。

## 推荐方案

推荐采用方案 B。

理由：

- 用户需求中的 `Status: [battery status]` 是一个语义整体，容器可以让“更新时间距离 status 右侧 24”这个约束表达更准确。
- 能明确保证 refresh button 右侧 24、更新时间 label 到 refresh button 4、更新时间文本起点到 status 24。
- 当屏幕宽度不足时，只压缩 updated date-time，不影响 battery level、status prefix、status value 的可读性。
- 改动范围仍然局限在 `PJEightKeySwitchMonitorHeaderView.swift`，不影响 ViewModel、VC 数据流或其他 8 键开关逻辑。

## 修复计划

1. 修改 `PJEightKeySwitchMonitorHeaderView.swift` 的顶部栏布局结构。
   - 新增 status 容器或水平 stack，包含 `statusPrefixLabel` 和 `statusValueLabel`。
   - 保持现有 label、button、image 的颜色、字体、图片资源不变。

2. 调整固定间距。
   - battery icon 左侧：24。
   - battery level 左侧到 battery icon 右侧：4。
   - status 容器左侧到 battery level 右侧：24。
   - status 容器内部 `Status:` 到 status value：4。
   - refresh button 右侧：24。
   - updated date-time 右侧到 refresh button 左侧：4。
   - updated date-time 左侧等于 status 容器右侧：24。

3. 增加压缩策略。
   - updated date-time 设置单行和尾部截断。
   - updated date-time 水平抗压缩优先级低于 battery level 和 status。
   - battery level、status prefix、status value 保持更高抗压缩优先级。

4. 验证窄屏和长文案场景。
   - 检查普通状态：`95% Status: Normal Updated 2 min ago`。
   - 检查低电量状态：`10% Status: Low Battery Updated 2 min ago`。
   - 检查未知或故障状态：`-- Status: Unknown/Fault Updated 7 days ago`。
   - 检查小屏宽度下 updated date-time 被截断，且 refresh button 不偏移、status 不被覆盖。

5. 构建验证。
   - 先运行 `git diff --check`。
   - 再运行 SunSmart iOS 真机泛型构建命令：
     `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 注意事项

- 当前项目大量使用 `SCRXFrom` 表示横向间距。若设计要求中的 24、4、30 必须是原始 point 值而不是按屏宽缩放后的值，需要在实现前确认；否则建议沿用现有 `SCRXFrom` 体系，保持本页面与项目其他 UI 一致。
- 本次修复不需要修改 `PJEightKeySwitchMonitorVC` 或本地化文案；`PJEightKeySwitchMonitorViewModel` 仅将低电量 battery level 改为纯百分比。
- 当前工作区已有其他未提交改动，本计划不覆盖或回退那些改动。
