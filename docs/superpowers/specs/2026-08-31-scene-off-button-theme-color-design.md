# Scene Group OFF 按钮主题色设计

## 背景

在 Space → Scene → 长按场景 → Settings → 选择 Group 后，`SceneExecuteDataPickerView` 会显示包含 OFF 按钮、亮度滑块和可选色温滑块的底部弹框。当前 OFF 按钮将 SunSmart 默认紫蓝色及浅色边框直接写为固定 RGB，导致 Lumineux 构建仍显示 SunSmart 颜色。

## 目标与范围

- OFF 按钮的选中背景、未选中文字和未选中边框全部由现有品牌主题变量派生。
- SunSmart 保持当前默认主题观感；Lumineux 使用其 `Bar_Color`，当前为 `RGB(77, 115, 138)`。
- 保留按钮的标题、尺寸、圆角、状态判断、点击行为和亮度联动。
- 不修改亮度或色温滑块、不调整其他页面的硬编码颜色，也不引入新的主题系统。

## 方案

继续使用现有编译条件下按品牌解析的 `Bar_Color`，不新增颜色常量：

| OFF 状态 | 背景 | 文字 | 边框 |
| --- | --- | --- | --- |
| 选中，亮度为 0 | `Bar_Color` | 白色 | 无边框 |
| 未选中，亮度大于 0 | 白色 | `Bar_Color` | `Bar_Color.withAlphaComponent(0.6)` |

初始化和每次状态刷新都通过同一套主题化样式设置，避免初始化颜色与切换后的颜色不一致。`isOn`、`selectedIsOn`、`setLightnessValue(_:)` 和 `offBtnAction()` 的数据流保持不变。

## 验证

- 先增加失败回归测试，证明 OFF 按钮样式不能包含原有固定 RGB，并必须使用 `Bar_Color` 及其透明度派生边框。
- 验证默认 SunSmart 编译条件下按钮仍解析为默认主题色。
- 验证 Lumineux 编译条件下按钮解析为 `RGB(77, 115, 138)`，选中与未选中状态符合上表。
- 运行相关 Scene/Lumineux 测试与静态检查，并核对按钮约束没有变化。

## 非目标

- 不修改 `scene_group_on`、`scene_group_off` 或其他图片资源。
- 不改变 Scene Group 的保存、预览、Mesh 控制或色温能力判断。
- 不提交或推送与本按钮主题化无关的文件。
