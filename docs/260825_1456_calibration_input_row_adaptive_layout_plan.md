# Calibration inputRow 自适应布局需求分析与实施计划

## 1. 需求理解

目标是在 `LightSensorTargetSensorValueView` 的 `inputRow` 中，保持现有排列顺序：

1. `Target value` 输入框
2. `LX` 单位
3. `Use sensor reading` 按钮

宽度分配规则调整为：

- `Use sensor reading` 按钮根据当前本地化文案和水平内边距决定自身宽度，英文与中文均不得被截断。
- `LX` 根据自身文字的固有内容宽度展示，不设置固定宽度，也不得被压缩。
- 输入框不再使用固定宽度，取得前两项和两个间距之外的全部剩余宽度。

用户描述中的 `User sensor reading` 按现有国际化文案 `Use sensor reading` 理解；本次不修改文案或国际化 Key。

## 2. 当前实现与问题原因

当前 `inputRow` 已经使用水平 `UIStackView`，左右各保留 16pt，三个 arranged subview 之间的间距为 8pt。

但其宽度策略仍是固定分配：

- 输入框固定为缩放后的 152pt。
- `Use sensor reading` 按钮固定为缩放后的 114pt。
- `LX` 依靠 UILabel 固有宽度。

固定宽度不会参考实际本地化文案。英文 `Use sensor reading` 加上按钮应有的左右留白后，所需宽度可能超过 114pt，最终发生标题压缩或截断。与此同时，输入框即使存在多余空间也无法吸收，因为自身宽度已被固定。

只删除固定宽度仍不充分：按钮、UILabel 和 UITextField 默认水平抗压缩优先级接近，空间不足时 Auto Layout 不保证一定压缩输入框。因此必须明确三者的 hugging 与 compression resistance 关系。

## 3. 推荐布局方案

### 3.1 保持不变

- 保持 `UIStackView`，排列顺序不变。
- 保持 `.horizontal`、`.center` 和 8pt 间距。
- 保持 inputRow 左右 16pt、顶部 16pt 和当前 32pt 行高。
- 保持输入框左侧 8pt 内边距、字体、边框和交互逻辑。
- 保持按钮当前 1pt 边框、15pt 圆角、32pt 高度、字体、颜色和点击逻辑。
- 不修改英文、简体中文本地化文件。
- 不修改 Calibration 状态、传感器读数请求、输入校验或 Dim level 流程。

### 3.2 `Use sensor reading` 按钮

- 删除 114pt 固定宽度。
- 增加对称的水平 content inset，使按钮固有宽度包含文字宽度和视觉留白；建议左右各 12pt。
- 标题保持单行。
- 水平 content hugging priority 设为 required，避免按钮在有剩余空间时无意义拉伸。
- 水平 compression resistance priority 设为 required，确保 Stack View 优先保留完整按钮文案。

### 3.3 `LX` 单位

- 不增加固定宽度，继续使用 UILabel 的 intrinsic content size。
- 水平 content hugging priority 设为 required。
- 水平 compression resistance priority 设为 required。
- 不修改现有 `LX` 文案、字体和颜色。

### 3.4 `Target value` 输入框

- 删除 152pt 固定宽度。
- 水平 content hugging priority 设为 defaultLow，使其吸收 inputRow 的全部剩余空间。
- 水平 compression resistance priority 设为 defaultLow；在极窄宽度下，输入框是唯一允许优先收缩的控件。
- 保留 32pt 高度。
- 不设置新的等宽、比例宽度或基于屏幕尺寸计算的宽度，避免再次把文案长度与固定设备宽度耦合。

### 3.5 最终宽度关系

输入框宽度应由下式自然确定：

`inputRow 可用宽度 - LX 固有宽度 - 按钮固有宽度 - 两个 8pt 间距`

按钮文案或语言变化时，按钮宽度随 intrinsic content size 变化，输入框自动取得新的剩余宽度。

## 4. 测试与验收计划

### 4.1 自动化回归

先扩展 `SensorCalibrationWorkflowContractTests` 建立失败用例，再实施布局修改：

- 输入框不得保留固定宽度约束。
- Use sensor reading 按钮不得保留固定宽度约束。
- 按钮与 LX 必须设置 required 水平抗压缩优先级。
- 输入框必须设置较低的水平 hugging 和抗压缩优先级。
- 按钮必须存在明确的水平 content inset。

该检查用于防止固定宽度和错误优先级回归，但它仍属于源码契约，不能代替实际布局测试。

### 4.2 实际布局测试

工程当前只有四个 App target，没有可直接运行的 XCTest target，因此现有 `Tests/` 脚本不能实例化 UIKit 视图并执行 Auto Layout。

按照当前 `AGENTS.md` 的 UI 验证要求，实施完成后需要在实际 iPhone 上进入 Calibration 的 Sensor 模式，分别用 English 和简体中文验证；不能仅凭编译和静态契约宣告完成。

至少覆盖以下窗口宽度对应的设备：

- 320pt 宽度等级：验证最窄支持场景，输入框仍有正宽度。
- 375pt 宽度等级：验证项目基准尺寸。
- 更宽设备或 iPad：验证输入框吸收额外空间，按钮与 LX 不被拉伸。

每个场景检查：

- `Use sensor reading` 或 `使用传感器读数` 完整单行显示，无省略号、裁切或缩小字体。
- `LX` 完整显示，宽度贴合文字。
- 输入框位于最左侧，取得其余空间，三项顺序正确且无重叠。
- 两个 8pt 间距保持一致。
- 输入、Use sensor reading 点击、返回读数和键盘行为不变。

若实施环境没有可用真机，应明确将实际布局验收标记为未完成，不以四品牌构建替代。

### 4.3 构建与共享 target 检查

修改位于四品牌共享文件。完成代码和布局验收后，串行执行以下 iphoneos、关闭签名的 Debug 构建：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

同时执行 Sensor Calibration 聚焦契约与 `git diff --check`。

## 5. 工作区保护

当前工作区已有未提交改动：

- `AGENTS.md` 新增 UI 实际布局测试要求。
- Dim level 加号按钮约束修复及其回归检查。
- `inputRow` 附近由用户调整的按钮边框、圆角和 32pt 高度。
- 已生成的 Dim level 修复记录。

后续实施只修改 `inputRow` 的宽度分配、内容内边距和水平优先级；必须保留上述现有改动，不覆盖、不回退、不扩大到其他 UI。

## 6. 实施步骤

1. 在现有 Sensor Calibration 契约中新增 inputRow 自适应规则，确认修改前失败。
2. 删除输入框和 Use sensor reading 按钮的固定宽度约束。
3. 配置按钮水平内边距及 required hugging/compression resistance。
4. 配置 LX 的 required hugging/compression resistance。
5. 配置输入框的低 hugging/compression resistance，使其填充剩余宽度。
6. 运行聚焦契约，确认从失败转为通过，并执行 `git diff --check`。
7. 在 English 和简体中文下完成实际 iPhone 布局与交互测试。
8. 串行完成四品牌 iphoneos Debug 无签名构建。
9. 复核最终 diff，只包含获批范围，并记录自动化与真机验收边界。

## 7. 结论

推荐方案不依赖屏幕宽度计算，也不为中文和英文分别设置常量。通过 intrinsic content size、content inset 和明确的优先级，让按钮与单位先取得完整显示所需宽度，输入框承担全部弹性空间。这与需求一致，并能适应后续本地化文案长度变化。
