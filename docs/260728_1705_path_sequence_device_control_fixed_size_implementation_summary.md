# Path Sequence 设备控件固定尺寸实施总结

## 实施结论

方案 A 已按确认范围完成。

- Path Sequence 与 Trigger Zone 列表中的设备视觉控件统一固定为 `44 × 44`，圆角固定为 `22`，保留原有圆形。
- 设备图片统一固定为 `20 × 20`。
- Sequence 设备顶部序号 `UILabel` 固定高度为 `16`，对应 item 总高度固定为 `60`。
- `GroupPathSequenceDeviceAddView` 及其 Trigger Zone、Manually Add 子列表中的设备视觉控件统一固定为 `44 × 44`，并保持圆形。
- iPhone 与 iPad 共用同一组固定视觉尺寸；外层 collection item 仍按可用宽度自适应，以保留 iPhone 5 列、iPad 8 列的现有排列策略。

## 原问题与根因

原实现将 `SCRYFrom` 同时用于设备控件、图片、标签、行高和间距。该换算以屏幕宽度为输入，因此在 iPhone 上接近设计值的尺寸，到 iPad 上会被明显放大。例如设备控件在 iPhone 上约为 44pt，在 iPad 上可能接近 78pt。

需求的本质是固定视觉控件尺寸，而不是固定每个 collection slot 的宽度。因此本次没有把整个 item 宽度硬编码为 44，而是在自适应 slot 内居中放置固定为 44 × 44 的视觉控件。这样可以同时满足固定控件大小和既有列数策略。

## 主要改动

### Path Sequence

- 集中定义设备控件、图片、序号标签和 item 高度等布局常量。
- Sequence item 高度固定为 60，其中顶部序号标签高度为 16，底部设备控件为 44 × 44。
- 设备图片固定为 20 × 20。
- Add item 的圆形视觉控件固定为 44 × 44。
- 设备控件与 Add item 的圆角明确固定为 22，不再依赖布局时读取 Frame。
- Add item 持有稳定的虚线 `CAShapeLayer`；在 `contentView` 完成布局后，按有效的 44 × 44 Bounds 更新正圆路径。
- 虚线路径向内收 0.5pt，避免 1pt 描边落在 Bounds 外侧而被裁切。
- 连接线端点以实际 44pt 控件宽度计算，避免 iPad 自适应 slot 变宽后连接线偏移。
- 移除该列表布局链中的 `SCRYFrom`。

### Trigger Zone

- collection item 继续使用自适应宽度，item 高度固定为 44。
- 设备 cell 内部视觉控件固定为 44 × 44，设备图片固定为 20 × 20。
- 行高改为基于固定 item 高度、固定行间距和 section inset 计算。
- 对零行场景增加保护，避免出现负间距计算。
- controller 的 estimated row height 调整为固定布局对应的 76pt。
- 移除该列表布局链中的 `SCRYFrom`。

### GroupPathSequenceDeviceAddView

- 保留父视图原有展示策略和外层高度管理，不改动其业务职责。
- `GroupPathSequenceAddDeviceCell` 新增居中的固定 44 × 44 视觉容器，图片固定为 20 × 20。
- 固定视觉容器使用 22pt 圆角，保留修改前的圆形外观。
- Trigger Add 列表高度固定为 68，44pt item 通过上下各 12pt inset 居中。
- Manually Add 列表按 44pt item 高度和固定行间距计算内容高度。
- 选择态边框改为作用于固定视觉容器，而不是自适应宽度的整个 cell。
- Manually Add 长按拖拽的 lifting preview 改为直接快照固定 44 × 44 的 `boxView`，不再使用整个自适应 Cell。
- Drag Preview 使用正圆 `visiblePath` 和透明背景，确保 iPhone、iPad 均显示为圆形设备控件。
- 移除设备列表尺寸链中的 iPhone/iPad 分支缩放。

## 测试过程

采用现有源码契约测试扩展覆盖本次布局约束。

### RED

在修改生产代码前增加固定尺寸约束，分别观察到预期失败：

- `Precondition failed: Device control must be 44 points`
- `Precondition failed: Add device cell must expose its fixed visual control`
- `Precondition failed: The fixed 44-point device control must retain a 22-point circular radius`
- `Precondition failed: Path Add item must retain one stable dashed border layer`
- `Precondition failed: Manually Add must override the adaptive cell's default drag preview`

这证明新增测试能够识别旧实现中的屏幕缩放、缺少固定视觉容器、固定尺寸后圆形约束遗漏，以及 Add item 虚线层布局时机错误。

### GREEN

完成最小实现后，契约测试通过：

```text
GroupPathSequenceDeviceAddViewContractTests layout passed
```

覆盖内容包括：

- 44 × 44 设备视觉控件；
- 22pt 固定圆角，确保设备控件和 Add item 保持圆形；
- Sequence 最左、最右 Add item 在有效 Bounds 上更新稳定的圆形虚线层；
- Manually Add 拖拽预览使用固定 44 × 44 的圆形设备容器；
- 20 × 20 设备图片；
- 16pt Sequence 序号标签；
- 60pt Sequence item 高度；
- Trigger Zone 固定 item 高度、行高公式与零行保护；
- AddView 与 Manually Add 的固定视觉尺寸；
- 选择态边框目标；
- 目标设备列表布局文件不再使用 `SCRYFrom`。

## 构建验证

以下 generic iPhoneOS Debug 构建均已通过：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

四个构建结果均为 `** BUILD SUCCEEDED **`。

## 边界与后续验收

自动化契约测试和 generic iPhoneOS 构建证明了尺寸约束与编译兼容性，但不等同于真实界面视觉验收。建议在 iPhone 与 iPad 真机上重点确认：

- Sequence 设备序号、设备图标、长设备名及连接线对齐；
- Trigger Zone 在 0、1、多行设备场景下的行高；
- Trigger Add 与 Manually Add 的选择态边框及垂直居中；
- iPhone 5 列与 iPad 8 列是否保持；
- Dynamic Type 或较长中英文设备名是否发生截断。

本次未修改业务逻辑、国际化资源、target 配置或依赖，也未执行 Git 提交、合并或推送。
