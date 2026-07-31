# GroupPathSequenceDeviceAddView 测试问题分析与修复方案草案

## 1. 结论

本轮反馈的三个现象均真实存在，并且可由当前代码结构解释：

1. 首次进入 Path Sequence，以及首次切换到懒加载的 Trigger Zone 页面时，底部添加 View 存在 safe area 高度初始化时序问题。
2. 未选择 Path 或 Zone 时，Quick Add、Trigger Add、Manually Add 的提示文案高度不同，会使整组 1、2、3 标签随垂直居中约束上下漂移。
3. 默认提示状态确实同时存在外层 adding content card 和内层 step guide 两个白色圆角 View，可以收敛为仅外层一个圆角容器。

推荐修复方向是：

- 公共 `GroupPathSequenceDeviceAddView` 只计算并上报不包含 safe area 的内容高度。
- Group Sequence / Group Trigger Zone Controller 使用自身已经稳定的 safe area 计算最终外部高度。
- equal-columns 提示布局固定标签顶部为 40。
- equal-columns 模式下的 step guide 改为透明、无圆角，保留外层 adding content card 作为唯一圆角背景。

本轮不改变 selected 状态布局，不开放 Space Trigger Zone 入口。

## 2. 问题一：首次进入和页面切换时高度错误

### 2.1 现象真实性

当前两个 Group Controller 均采用以下结构：

- `GroupPathSequenceDeviceAddView` 底部约束到 Controller View 底部。
- 外部高度约束初始值为 0。
- 公共 View 通过高度回调更新外部高度约束。
- closed 内容高度应为 44，但公共 View 当前还会把自己的 `safeAreaInsets.bottom` 加入回调高度。

首次进入时，公共 View 在最终 frame 和 safe area 尚未稳定前就会刷新首选高度。此时容易先得到 44，而不是 `44 + safe area bottom`。由于 View 仍固定在屏幕底部，44 高度会同时覆盖安全区，导致 Add to Path / Add to Zone 行进入 Home Indicator 区域。

首次切换到 Trigger Zone 时，该子 Controller 由 `WMPageController` 懒加载，生命周期会重新走一遍相同的初始高度流程，因此出现相同问题。

### 2.2 根因

根因是当前高度计算形成了初始化反馈环：

1. 外部高度决定 `GroupPathSequenceDeviceAddView` 的 frame。
2. 子 View 的 frame 又影响它自己的 `safeAreaInsets.bottom`。
3. 子 View 再使用这个 safe area 计算并回调外部高度。

首次布局时，外部高度从 0 开始，子 View 的 safe area 尚未成为最终值。当前实现依赖后续 `safeAreaInsetsDidChange()` 再次回调修正，但在页面容器初次布局、懒加载页面切换等场景中，这个修正不够确定。

此外，两个 Group Controller 的非动画高度更新只修改约束常量，不立即完成父 View 布局。用户点击展开或收起后，公共 View 已拥有稳定的 frame 和 safe area，并再次刷新高度，所以问题才表现为“操作一次后恢复”。

### 2.3 备选方案

#### 方案 A：在页面出现和切换后额外刷新

在 `viewDidAppear`、`didEnter` 或下一轮 RunLoop 再调用一次高度刷新。

优点：

- 改动最小。

缺点：

- 仍保留子 View safe area 与外部高度之间的反馈环。
- 容器尺寸、横竖屏或后续复用场景仍可能出现类似时序问题。
- 修复依赖额外生命周期补丁，不推荐。

#### 方案 B：Controller 持有 safe area 真值，公共 View 只上报内容高度

公共 View 的高度输出不再包含自身 safe area：

- hidden：0。
- closed：44。
- Group fixed-base open：264。
- Manually Add 多行或 Space dynamic-selected：继续按现有高度策略输出实际内容高度。

Group Controller 缓存最新内容高度，并计算：

`最终高度 = 内容高度 + Controller View 的 safeAreaInsets.bottom`

在以下时机同步最终高度：

- 收到公共 View 内容高度变化回调。
- `viewSafeAreaInsetsDidChange()`。
- `viewWillLayoutSubviews()`，用于覆盖 `WMPageController` 首次给子页面设置 frame 的场景。

只在目标高度实际变化时更新约束，初始同步不执行动画，用户操作后的展开/收起继续使用现有动画。

优点：

- 消除子 View 高度对自身 safe area 的循环依赖。
- 首次进入和 Trigger Zone 懒加载走同一套确定逻辑。
- 保留已确认的公共 View + 高度策略设计。
- Space Trigger Zone 虽然继续隐藏，但仍可保留 dynamic-selected 策略。

缺点：

- 高度回调语义需要从“最终高度”明确调整为“内容高度”。
- 所有三个调用方都要同步检查，避免隐藏的 Space Controller 将来启用时高度语义不一致。

这是推荐方案。

#### 方案 C：引入独立 safe-area 容器或背景填充 View

将添加 View 固定在 Controller safe area 上方，再用单独背景 View 填充 Home Indicator 区域。

优点：

- safe area 完全由约束结构表达。

缺点：

- 会新增容器层级，并改变当前“一个公共 View 表示整个底部区域”的结构。
- 动态 selected 高度、阴影和圆角需要重新梳理。
- 对本轮聚焦修复而言范围偏大。

本轮不推荐。

## 3. 问题二：1、2、3 标签在三种模式间上下漂移

### 3.1 现象真实性

三个模式使用的是同一组标签图片资源：

- `proximity_lighting_step1`
- `proximity_lighting_step2`
- `proximity_lighting_step3`

三张 @2x 图片均为 40 × 40 px，代码中的 `UIImageView` 也统一约束为 20 × 20 pt。因此跨模式的上下位置差异不是图片尺寸导致。

当前 equal-columns 布局只解决了水平方向：

- 三列 `.fillEqually`。
- 左右间距和列间距均为 16。
- 第二列水平居中。

垂直方向仍使用：

- 整个 `stackView` 相对 guide View 垂直居中。
- 每个 Step 的图片在 Step 顶部。
- Step 高度由图片、8 间距和多行文案共同决定。

Quick Add、Trigger Add、Manually Add 的提示文案不同，换行数和最大文案高度也不同，因此整个 stack 高度不同。垂直居中后，stack 顶部随高度变化，1、2、3 图片也会一起上下移动。

### 3.2 推荐约束

仅对 `.equalColumns` 使用固定顶部基准：

- 以标签 2 的图片顶部为基准，顶部距 adding content view 顶部固定为 40。
- 由于三个 Step 已经使用顶部对齐，标签 1、2、3 的图片顶部统一位于同一条水平线上。
- 连接线继续与标签图片垂直中心对齐。
- 移除 equal-columns 的垂直居中约束。
- legacy 布局继续保持原有垂直居中行为，避免影响其他复用页面。

这样提示文案的行数只会向下增长，不再反向推动标签位置。

## 4. 问题三：两个圆角矩形

### 4.1 原因

当前默认提示状态存在两层圆角背景：

1. 外层 `contentCardView`：白色，圆角 10，高度 160。
2. 内层 `GroupPathSequenceDeviceAddStepView`：白色，圆角 10，并位于外层卡片内。

Quick Add、Trigger Add、Manually Add 自身已经被改为透明且无圆角，但 equal-columns step guide 仍保留了 legacy 样式的白色背景和圆角，因此形成重复的内容表面。

### 4.2 推荐优化

- 外层 `contentCardView` 保持白色和圆角 10，作为唯一 adding content view。
- `.equalColumns` 的 `GroupPathSequenceDeviceAddStepView` 改为透明背景、圆角 0，只负责提示内容布局。
- `.legacy` 继续保留白色背景和原有圆角，避免影响其他使用者。
- Quick Add、Trigger Add、Manually Add 的透明容器关系保持不变。

## 5. 推荐实施范围

### 5.1 公共 View

修改：

- `GroupPathSequenceDeviceAddView.swift`
- `GroupPathSequenceDeviceAddStepView.swift`

内容：

- 将高度回调定义为不包含 safe area 的内容高度。
- 删除公共 View 对自身 `safeAreaInsets.bottom` 的高度依赖及对应缓存。
- 保留 fixed-base / dynamic-selected 高度策略。
- equal-columns 标签顶部固定为 40。
- equal-columns step guide 改为透明、无圆角；legacy 不变。

### 5.2 Group 调用方

修改：

- `GroupPathSequenceViewController.swift`
- `GroupPathSequenceTriggerZoneController.swift`

内容：

- 缓存公共 View 最近一次内容高度。
- 使用 Controller View 的 safe area bottom 计算最终高度。
- 在 safe area 变化和首次布局前同步最终高度。
- 首次同步不动画；用户展开、收起和模式切换继续保留现有动画。
- 不需要在 `GroupPathSequencePageController.didEnter` 增加一次性延迟刷新补丁。

### 5.3 隐藏的 Space Trigger Zone

检查并按新高度回调语义更新：

- `SpacePathTriggerZoneController.swift`

该页面当前把添加 View 放在 safe area 之上，并另外保留底部间距，因此不应再次叠加 Group 页面使用的 safe area 高度。继续保持：

- dynamic-selected 内容高度策略。
- 页面入口隐藏。
- 不新增用户可见入口或功能。

## 6. 回归测试计划

### 6.1 自动化契约

更新现有 Group 静态契约测试，覆盖：

- 公共 View 的高度输出不再读取自身 safe area。
- closed 内容高度固定为 44。
- fixed-base open 内容高度固定为 264。
- 两个 Group Controller 使用自身 safe area 组成最终高度。
- safe area 和首次布局生命周期均会重新同步缓存高度。
- Space Controller 不重复叠加 safe area。
- equal-columns 使用固定顶部 40，且不再使用垂直居中。
- equal-columns 透明且圆角为 0，legacy 样式保持不变。
- Space Trigger Zone 入口继续隐藏。

### 6.2 静态与构建验证

- 运行更新后的静态契约测试。
- 运行 `git diff --check`。
- 检查本轮目标文件未重新引入 `SCRXFrom`、`SCRYFrom`。
- 使用 generic iPhoneOS 分别构建：
  - SunSmart
  - Archipelago
  - SLG Sync Plus
  - SylSmart

### 6.3 真机视觉验收

- 带 Home Indicator 的设备首次进入 Path Sequence，closed 高度直接正确，无需先展开或收起。
- Sequence 首次切换到 Trigger Zone，closed 高度直接正确。
- 在两个页面间重复切换，底部高度不跳变。
- Quick Add、Trigger Add、Manually Add 默认提示中，标签 2 顶部距 adding content view 顶部为 40。
- 标签 1、2、3 顶部对齐，英文和简体中文文案换行不影响图片位置。
- 默认提示只显示一个白色圆角 adding content view。
- 选择 Path 或 Zone 后的 selected 状态布局保持本轮修改前效果。
- 无 Home Indicator 设备的 safe area 为 0 时，closed 高度仍为 44。

## 7. 非目标

- 不优化 selected 状态的其他视觉细节。
- 不改变 Add Device 业务行为。
- 不新增或修改国际化文案。
- 不开放 Space Trigger Zone。
- 不重构 `WMPageController`。
- 不执行 Git commit、merge、push 或 PR。

