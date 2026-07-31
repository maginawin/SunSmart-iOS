# GroupPathSequenceDeviceAddView 测试问题修复总结

## 实施结果

已按确认的方案 B 完成以下修复：

- 首次进入 Path Sequence 时，closed 状态高度不再依赖公共 View 尚未稳定的 safe area。
- 首次切换到懒加载的 Trigger Zone 页面时，使用相同的 Controller safe-area 高度同步机制。
- Quick Add、Trigger Add、Manually Add 默认提示中的 1、2、3 标签顶部固定。
- 默认提示仅保留外层 adding content view 一个白色圆角背景。
- selected 状态布局未进行额外优化。
- Space Trigger Zone 继续保持隐藏。

## 高度数据流

`GroupPathSequenceDeviceAddView` 现在只上报不包含 safe area 的内容高度：

- hidden：0。
- closed：44。
- Group fixed-base open：264。
- dynamic-selected 和 Manually Add 多行状态继续按现有策略计算实际内容高度。

Group Sequence 与 Group Trigger Zone Controller：

- 缓存公共 View 最近一次内容高度。
- 使用自身 `view.safeAreaInsets.bottom` 计算最终高度。
- 在 safe area 变化时重新同步。
- 在 `viewWillLayoutSubviews()` 中重新同步，覆盖 `WMPageController` 首次设置子页面 frame 的场景。
- 仅在目标高度实际变化时更新约束。
- 初始同步不动画，用户操作后的既有动画逻辑保持不变。

隐藏的 Space Trigger Zone：

- 继续使用 dynamic-selected 策略。
- 继续使用原有的 safe-area 上方定位和底部间距。
- 适配内容高度回调语义，不重复叠加 safe area。

## 默认提示布局

equal-columns 模式现在：

- guide 填满 adding content view，不再保留旧的上下 12 内层间距。
- 1、2、3 标签图片顶部统一距 adding content view 顶部 40。
- 三列继续等宽，左右间距和列间距继续为 16。
- 连接线继续与图片垂直中心对齐。
- 文案换行只向下增长，不再通过垂直居中推动标签上下漂移。

legacy 模式继续保留原有垂直居中、白色背景和圆角。

## 圆角层级

- 外层 `contentCardView` 继续使用白色背景和圆角 10。
- equal-columns 的 `GroupPathSequenceDeviceAddStepView` 改为透明背景和圆角 0。
- Quick Add、Trigger Add、Manually Add 中间容器继续保持透明。

因此默认提示只剩一个可见的白色圆角 adding content view。

## TDD 记录

### 高度数据流

RED 首个失败：

- `Closed content height must be the fixed 44-point header`

GREEN：

- 公共 View 高度输出移除自身 safe area。
- 两个 Group Controller 使用 Controller safe area。
- Space Controller 不重复叠加。
- 契约测试通过。

### 标签定位与圆角

RED 首个失败：

- `Equal-column step images must stay 40 points below the content-card top`

GREEN：

- equal-columns 标签顶部固定为 40。
- guide 填满 adding content view。
- equal-columns 背景透明、圆角为 0。
- 契约测试通过。

## 验证结果

- 更新后的 Group 静态契约测试：通过。
- `git diff --check`：通过。
- 已确认的五个缩放清理文件中未重新引入 `SCRXFrom`、`SCRYFrom`。
- SunSmart generic iPhoneOS Debug：构建通过。
- Archipelago generic iPhoneOS Debug：构建通过。
- SLG Sync Plus generic iPhoneOS Debug：构建通过。
- SylSmart generic iPhoneOS Debug：构建通过。

构建日志存在项目既有的 AppIntents metadata warning：

- `Metadata extraction skipped. No AppIntents.framework dependency found.`

该 warning 未导致构建失败，与本轮 UI 改动无关。

## 真机待验收

- 带 Home Indicator 的设备首次进入 Path Sequence，Add to Path 行不进入安全区。
- Sequence 首次切换到 Trigger Zone，Add to Zone 行位置正确。
- 两个页面重复切换时 closed 高度不跳变。
- Quick Add、Trigger Add、Manually Add 默认提示中，标签 2 顶部距 adding content view 顶部为 40。
- 标签 1、2、3 顶部对齐，英文与简体中文文案换行不影响标签位置。
- 默认提示只显示一个白色圆角矩形。
- 选择 Path 或 Zone 后，selected 状态保持修改前布局。
- 无 Home Indicator 设备 closed 高度为 44。

本次未执行 Git commit、merge、push 或 PR。
