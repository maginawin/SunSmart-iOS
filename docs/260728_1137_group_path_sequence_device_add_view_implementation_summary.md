# GroupPathSequenceDeviceAddView 实施总结

## 实施结果

本次已按确认方案完成 `GroupPathSequenceDeviceAddView` 的 closed/open 状态、固定尺寸布局、默认提示区稳定布局，以及 selected 内容缩放函数清理。

Space Trigger Zone 继续保持隐藏，没有新增入口或用户可见开关。

## 主要改动

### closed / open 状态

- 默认状态调整为 closed。
- closed 仅展示 Add to Path / Add to Zone 标题行。
- 标题行固定高度为 44，顶部与 View 顶部对齐。
- closed 图标使用向上箭头；open 图标使用向下箭头。
- closed 总高度为 `44 + safe area bottom`。
- open 基础总高度为 `44 + 44 + 8 + 160 + 8 + safe area bottom`。

### adding content view

- Quick Add / Trigger Add / Manually Add 菜单行固定高度为 44。
- adding content view 左右间距固定为 16，上下间距固定为 8。
- adding content view 基础高度固定为 160，圆角固定为 10。
- Group Path Sequence 与 Group Trigger Zone 使用 fixed-base 高度策略。
- 隐藏的 Space Trigger Zone 使用 dynamic-selected 高度策略，为后续继续复用公共 View 保留动态内容能力。
- Manually Add 展开为多行时允许内容高度超过 160，避免裁切。

### 默认提示布局

- 为共享的 `GroupPathSequenceDeviceAddStepView` 增加可配置布局策略。
- 本次三个添加模式均使用 equal-columns 策略。
- 三个提示项等宽，外侧间距与列间距均固定为 16。
- 每列宽度为 `(addingContentView.width - 64) / 3`，第二个提示始终位于水平中心。
- 共享组件的其他既有调用继续使用 legacy 策略，避免影响无关页面。

### 缩放函数清理

以下五个确认范围文件中的 `SCRXFrom`、`SCRYFrom` 已全部清理，包括 selected 内容和旧注释：

- `GroupPathSequenceDeviceAddView.swift`
- `GroupPathSequenceQuickAddView.swift`
- `GroupPathSequenceTriggerAddView.swift`
- `GroupPathSequenceManuallyAddView.swift`
- `GroupPathSequenceAddDeviceCell.swift`

机械清理后，对失去隐式类型信息的尺寸变量补充了明确的 `CGFloat` 类型，保持原数值和既有布局关系。

## 回归保护

新增静态契约测试，覆盖：

- 默认 closed 状态及箭头映射。
- 44 / 8 / 16 / 160 固定尺寸。
- closed/open 高度公式。
- Group 与 Space 高度策略。
- 默认提示区三等分布局。
- 五个目标文件无缩放函数残留。
- Space Trigger Zone 入口继续隐藏。
- 清理缩放函数后的 `CGFloat` 类型契约。

## 验证结果

- 静态契约测试：通过。
- `git diff --check`：通过。
- 五个目标文件缩放函数残留检查：无结果。
- Space More 入口检查：未包含 Trigger Zone。
- SunSmart generic iPhoneOS Debug 构建：通过。
- Archipelago generic iPhoneOS Debug 构建：通过。
- SLG Sync Plus generic iPhoneOS Debug 构建：通过。
- SylSmart generic iPhoneOS Debug 构建：通过。

## 待人工验收

构建与静态检查不能代替页面视觉验收。建议下一步重点检查：

- 首次进入 Path Sequence 页面时是否保持 closed。
- closed/open 箭头方向与点击切换。
- 带 Home Indicator 和不带 Home Indicator 设备上的底部安全区。
- 中英文提示文案下第二项是否始终居中、三列是否等宽。
- Quick Add、Trigger Add、Manually Add 的 selected 状态布局。
- Manually Add 两行、三行展开时的高度与折叠行为。

本次未执行 Git commit、merge、push 或 PR 操作。
