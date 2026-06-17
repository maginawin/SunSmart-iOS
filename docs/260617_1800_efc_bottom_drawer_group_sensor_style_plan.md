# EFC 底部弹窗对齐 GroupSensorView 样式方案

## 背景

目标是让 EFC 设备页底部的 `EmerFireAlarmStatusSetView` 按 `P.Occupancy sensing with daylight harvesting` group 页面底部弹窗的收起/展开 UI 更新。

reference 实现是：

- `GroupViewController` 在 `profile.type == .occupancy_daylight / .vacancy_daylight / .daylight` 等传感器 profile 下显示 `GroupSensorView`。
- `GroupSensorView` 作为 root view 上的 bottom overlay：
  - 收起高度：`SCRYFrom(40) + kSafeAreaBottomHeight`
  - 展开时 view 高度扩到 `superview.height - safeAreaInsets.top`
  - 内部 `contentView` 固定高度：`SCRYFrom(352) + kSafeAreaBottomHeight`
  - 展开时显示 `shadeView`，`contentView` 从底部滑上来
  - header 使用 `topView`，左侧 arrow + title，右侧状态组
  - 展开时 `topView.top = SCRYFrom(8)`，收起时 `topView.top = 0`
  - 展开时 `contentView` 顶部圆角 20
- `GroupViewController` 主内容底部按 collapsed drawer 高度再加 `SCRYFit(20)` 留白，避免内容和折叠态抽屉贴齐。

EFC 现状：

- `EmerFireAlarmMonitorVC` 直接把 `statusSetView` 贴到 `view.bottom`。
- `EmerFireAlarmStatusSetView` 通过内部高度在 `SCRYFrom(40)` 和 `SCRYFrom(320)` 间切换。
- 没有 shade overlay，没有 full-screen expanded overlay，也没有像 `GroupSensorView` 那样的 slide-up container。
- header 行当前直接约束到 panel 顶部，导致收起态顶部视觉贴边。

## 推荐方案：迁移 EFC 弹窗交互 shell，保留 EFC 内容

不复用或抽象 `GroupSensorView`，因为它绑定了 sensor 数据、cell、delegate 和占用/光照状态。EFC 应在 `EmerFireAlarmStatusSetView` 内实现同款 bottom drawer shell，只迁移视觉和展开/收起机制。

### 1. `EmerFireAlarmStatusSetView` 结构调整

把当前单一 `contentView` 拆成三层：

- `shadeView`
  - 填满 `EmerFireAlarmStatusSetView`
  - 收起隐藏，展开显示
  - 点击时收起弹窗
- `contentView`
  - 白色底部面板
  - 固定高度建议改为 `SCRYFrom(352) + kSafeAreaBottomHeight`，与 `GroupSensorView` 一致
  - 展开时添加顶部圆角 20
  - 收起时只露出 40 + safe area 的 header 区域
- `topView`
  - 承载 `headerButton`、arrow、title、右侧四个 status/action icon
  - header 元素的约束改成参考 `GroupSensorView`：arrow 靠左，title 跟随 arrow，右侧 icon 组靠右，全部围绕 topView 内的 header baseline 布局

### 2. 展开/收起动画

`setExpanded(_:animated:)` 改为接近 `GroupSensorView.show()/hide()`：

- 收起：
  - root height = `SCRYFrom(40) + kSafeAreaBottomHeight`
  - `shadeView.isHidden = true`
  - `topView.top = 0`
  - `arrowImageView.image = arrow_up`
  - `legendHeaderView` 和 `tableView` 隐藏
  - `contentView` 回到 collapsed 位置
- 展开：
  - root height = `superview.height - superview.safeAreaInsets.top`
  - `shadeView.isHidden = false`
  - `topView.top = SCRYFrom(8)`
  - `arrowImageView.image = arrow_down`
  - `legendHeaderView` 和 `tableView` 显示
  - `contentView` 从底部滑到 `rootHeight - panelHeight`

为了让 view 能更新自身外部高度，建议在 `EmerFireAlarmStatusSetView` 暴露：

- `var collapsedHeight: CGFloat`
- `var expandedOverlayHeightProvider: (() -> CGFloat)?`
- `var heightChangeHandler: ((CGFloat, Bool) -> Void)?`
- `var expansionChangedHandler: ((Bool) -> Void)?`

由 `EmerFireAlarmMonitorVC` 持有 `statusSetViewHeightConstraint` 并在回调中更新高度，这比 view 内部直接改自己的 SnapKit 约束更清晰。

### 3. `EmerFireAlarmMonitorVC` 宿主调整

修改 `statusSetView` 约束：

- 保留 `left/right/bottom == superview`
- 新增并持有 height constraint，初始为 `statusSetView.collapsedHeight`
- 配置 `heightChangeHandler` 更新约束并执行 `view.layoutIfNeeded()`
- 配置 `expandedOverlayHeightProvider` 返回 `view.bounds.height - view.safeAreaInsets.top`
- 展开时可同步 `isModalInPresentation = true`，收起后恢复 `false`，与 `GroupViewController` 的 `sensorViewDidShow/Hide` 一致

主内容避让：

- 保持当前 EFC 页面主体布局不大改。
- 为 `moniView` 增加一个低风险底部保护约束：
  - `moniView.bottom.lessThanOrEqualTo(statusSetView.snp.top).offset(-SCRYFit(20))`
  - 使用不高于 required 的优先级，避免短屏和现有 top spacing 约束冲突。
- 如果实际视觉仍被短屏压缩，再单独规划整页 scroll，不在本次顺手重构。

### 4. 保持 EFC 业务不变

- `HeaderAction`、四个 header icon 的点击行为不变。
- `legendHeaderView`、`tableView` 和 status row 数据不变。
- 上一个任务移除 Disabled legend 的结果继续保留。
- 不改 SDK、协议、配置模型、资源或 target 配置。

## 备选方案

### 方案 A：推荐方案，迁移 bottom drawer shell

优点：最接近 `GroupSensorView` 的收起/展开 UI；能同时解决折叠态顶部贴边和展开态缺少 overlay 的差异。

缺点：改动比单纯调 padding 大，需要处理 root height 与 panel slide 动画。

### 方案 B：只补 header top spacing

优点：风险最低，能修复“收起时 top 间隔为 0”的局部问题。

缺点：不是真正按 group 页面底部弹窗样式更新；展开/收起机制、shade、slide-up 行为仍不一致。

### 方案 C：抽象通用 BottomDrawerView

优点：长期复用性最好。

缺点：会牵涉 `GroupSensorView` 和 EFC 两套页面，风险和回归面明显扩大，不适合当前需求。

## 验证计划

- 静态检查：
  - `EmerFireAlarmStatusSetView` 有 shade/topView/contentView 分层。
  - `EmerFireAlarmMonitorVC` 持有并更新 `statusSetView` height constraint。
  - EFC header actions 仍接到原有 `headerActionHandler`。
- `git diff --check`
- iPhoneOS build：
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

