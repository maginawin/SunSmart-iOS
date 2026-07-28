# GroupPathSequenceDeviceAddView Selected 状态布局优化实施总结

## 1. 实施结果

已按确认的“局部固定约束与统一 Layout Metrics”方案完成 selected 状态布局调整：

- 弹窗使用的 `.equalColumns` 步骤提示路径采用固定纵向间距。
- Trigger Add 的 `UICollectionView` 高度统一固定为 68。
- Trigger Add 与 Manually Add 的 `No devices` 相对整个白色 `adding content view` 居中。
- Quick Add 的 Start/Pause、Stop 和右侧状态文字位于同一垂直中心线，并相对内容卡片垂直居中。

本次未修改控制器、公共父 View、高度策略、业务状态机、代理协议、本地化、资源、依赖或 target 配置。Space Trigger Zone 的入口继续保持隐藏。

## 2. 实际修改

### 2.1 公共步骤提示 View

`GroupPathSequenceDeviceAddStepView` 新增固定 8-point 的 `.equalColumns` 标题间距。

步骤子 View 通过初始化参数接收当前布局模式对应的标题间距：

- `.equalColumns` 使用固定 8。
- `.legacy` 继续使用原有 `SCRYFrom(8)`。

legacy 圆角和其他历史布局保持不变，因此 Profile、Reset 和 Device Add Instructions 等复用页面不会被强制改为固定布局。

### 2.2 Trigger Add

Trigger Add 新增单一的 68-point 列表高度常量，并同时用于：

- `UICollectionView` 高度约束。
- selected 内容首选高度计算。

这样避免约束高度和父 View 上报高度使用不同数值。

`No devices` 从相对列表居中改为相对 Trigger Add 根 View 居中。前序任务中的引导状态与空设备联合显隐规则保持不变。

### 2.3 Manually Add

`No devices` 从相对列表居中改为相对 Manually Add 根 View 居中。

列表动态高度、1～3 行展开、分页以及前序空态显隐修复均保持不变。

### 2.4 Quick Add

Start/Pause 共用按钮移除了相对筛选提示区域的顶部链式约束，改为相对 Quick Add 根 View 垂直居中。

Stop 按钮和状态文字继续相对 Start/Pause 按钮垂直居中。Adding、Pause、Stop 状态切换仍只更新显隐、选中状态、文案、颜色和现有水平偏移。

## 3. TDD 记录

### 3.1 `.equalColumns` 固定标题间距

RED：

`Equal-column guide title spacing must be a fixed 8 points`

GREEN：

`GroupPathSequenceDeviceAddViewContractTests layout passed`

### 3.2 Trigger Add 固定 68 与空态居中

RED：

`Trigger Add collection height must be a fixed 68 points`

GREEN：

`GroupPathSequenceDeviceAddViewContractTests layout passed`

### 3.3 Manually Add 空态居中

RED：

`Manually Add No devices must center in the whole adding content view`

GREEN：

`GroupPathSequenceDeviceAddViewContractTests layout passed`

### 3.4 Quick Add 操作组垂直居中

RED：

`Quick Add Start and Pause must center vertically in the adding content view`

GREEN：

`GroupPathSequenceDeviceAddViewContractTests layout passed`

## 4. 静态验证

- 完整合同测试通过。
- `git diff --check` 通过。
- Parent Add、Quick Add、Trigger Add、Manually Add 和 Add Device Cell 中未发现 `SCRYFrom`。
- 公共步骤 View 的剩余 `SCRYFrom` 仅用于 legacy 圆角和 legacy 标题间距；`.equalColumns` 选择固定 8-point 间距，标题约束只消费注入值。

## 5. iPhoneOS 构建

使用 Debug、generic iPhoneOS、关闭代码签名分别构建：

- `SunSmart`：成功。
- `Archipelago`：成功。
- `SLG Sync Plus`：成功。
- `SylSmart`：成功。

构建日志包含项目既有警告，包括部分资源符号重复、历史 API 弃用和 AppIntents metadata 跳过；未发现与本次修改相关的编译错误。

## 6. 真机待验

自动化合同和构建不能证明视觉布局完全符合预期，仍需真机验证：

1. Sequence 选中 Path 后，Trigger Add 与 Manually Add 的 `No devices` 位于整个白色内容卡片中心。
2. Trigger Zone 选中 Zone 后，同样检查两个空态位置。
3. Trigger Add 有设备时，68 高度列表的点击、分页、刷新和识别仍可用。
4. Manually Add 一行及多行展开时，无约束冲突、裁剪或空态漂移。
5. Quick Add 的 Stop、Adding、Pause 三种状态下，按钮组和右侧文字始终垂直居中。
6. English 与简体中文下，状态文字不遮挡按钮。
7. closed/open 往返及三种添加方式循环切换后，布局不漂移。
8. Space Trigger Zone 入口继续保持隐藏。

## 7. Git 状态

本任务未执行 `git add`、`git commit`、`git push`、merge 或 PR 操作。

