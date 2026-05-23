# CCT 参数设置 Figma UI 优化设计

## 背景

本设计针对 `Device Parameter Settings` 页面中两个 CCT 参数的启用后 UI：

- `Change Control Page`
- `Absolute CCT Range`

参考 Figma 页面：

`https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-drafts?node-id=31-11665&t=VpC261Dq8qDh9wOu-11`

现有工程中，这两个属性已经具备数据存储、云同步、启用开关和保存逻辑。本次只优化启用后的 UI 表现和交互，并修正特殊设备的厂商 ID 判断。

## 特殊设备判断

特殊设备条件为：

| 字段 | 值 |
|---|---|
| `companyIdentifier` | `0x0A78` |
| `productIdentifier` / `CID` | `0x2013` |

不保留 `0x0178 / 0x2013` 的兼容判断。

该特殊设备的行为：

| 属性 | 默认值 |
|---|---|
| `Change Control Page` | `Single White` |
| `Absolute CCT Range` | `2700K...5000K` |
| `PWM frequency` | 不展示 |

其他支持 CCT 的设备：

| 属性 | 默认值 |
|---|---|
| `Change Control Page` | `Tunable White` |
| `Absolute CCT Range` | `2700K...6500K` |
| `PWM frequency` | 保持现有逻辑 |

## 方案选择

| 方案 | 做法 | 优点 | 风险 |
|---|---|---|---|
| A | 保留现有两个专用 cell，重做内部 UI | 改动聚焦，复用现有数据流、启用逻辑、保存逻辑 | 需要新增 CCT 专用 slider 映射 |
| B | 新建整套 Figma 专用 CCT cell | 新旧实现隔离 | 重复标题、开关、note、reset、slider 逻辑 |
| C | 保留当前控件，只调整文案和布局 | 改动最小 | 与 Figma 差距明显 |

采用方案 A。

## UI 结构

### Change Control Page

启用前：

- 保持当前白色圆角卡片样式。
- 仅显示标题和右侧开关。
- 开关默认关闭。

启用后：

- 卡片展开。
- 顶部显示标题和右侧开关。
- 标题下方显示浅灰色选项条。
- 选项条内展示两个 radio 选项：
  - `Single White`
  - `Tunable White`
- 选中的选项使用现有 `select` 资源，未选中使用现有 `select_un` 资源。
- 默认项追加 `(Default)`。
- 底部显示说明文案。

文案规则：

| 设备类型 | 默认选项 | 展示文案 |
|---|---|---|
| `0x0A78 / 0x2013` | `Single White` | `Single White (Default)`、`Tunable White` |
| 其他 CCT 设备 | `Tunable White` | `Single White`、`Tunable White (Default)` |

### Absolute CCT Range

启用前：

- 保持当前白色圆角卡片样式。
- 仅显示标题和右侧开关。
- 开关默认关闭。

启用后：

- 卡片展开。
- 顶部左侧显示标题。
- 顶部右侧显示 `Reset` 按钮和开关。
- 标题下方左侧显示当前 min CCT，右侧显示当前 max CCT。
- 数值下方显示一条 CCT 专用双滑块。
- 滑块左右两侧分别是现有 `scene_data_value_minus` 和 `scene_data_value_add` 按钮。
- 底部显示说明文案。

`Reset` 行为：

| 设备类型 | Reset 后 |
|---|---|
| `0x0A78 / 0x2013` | `2700K...5000K` |
| 其他 CCT 设备 | `2700K...6500K` |

## CCT Range Slider

新增 `DeviceParameterCctRangeSlider`，不要修改全局 `RangeSlider`，避免影响 RSSI、Absolute Sensitivity 等现有页面。

### 数值范围

| thumb | 可选范围 | 不可选范围 |
|---|---|---|
| min thumb | `1000K...2700K` | `(2700K, 5000K)` 和 `5000K...10000K` |
| max thumb | `5000K...10000K` | `1000K...2700K` 和 `(2700K, 5000K)` |

`2700K` 和 `5000K` 是合法边界值；只有 `(2700K, 5000K)` 这个开区间不可选。

### 映射规则

视觉上 slider 是一条连续横线，但交互映射分为三段：

| 区域 | 含义 |
|---|---|
| 左段 | min 可调区，`1000K...2700K` |
| 中段 | 固定间隔区，`2700K...5000K` |
| 右段 | max 可调区，`5000K...10000K` |

Figma 中 slider 比例不作为实现依据。实际实现只需保证：

- min thumb 只能停在 `1000K...2700K`。
- max thumb 只能停在 `5000K...10000K`。
- 拖动到中间区域时吸附到合法边界：
  - min thumb 吸附到 `2700K`。
  - max thumb 吸附到 `5000K`。
- 数值步进为 `100K`。
- 左右数值标签固定显示在 slider 上方左右两端，不跟随 thumb 移动。

### 加减按钮

左右加减按钮复用现有 Absolute Sensitivity 的交互：

- 当前高亮或最近操作的是 min thumb 时，`- / +` 调整 min。
- 当前高亮或最近操作的是 max thumb 时，`- / +` 调整 max。
- 初始无高亮 thumb 时，默认高亮 max。
- min 加到 `2700K` 后继续加不动。
- max 减到 `5000K` 后继续减不动。

## 文案

`Change Control Page` 和 `Absolute CCT Range` 都使用新的长说明文案，并提供中英文本地化。

文案由实现时按现有中英文风格补充。语义要求：

- `Change Control Page` 说明需要表达：
  - 设备支持单白光和可调白光两种控制页面。
  - 可根据实际灯具类型选择 App 中的控制页面。
  - 改为 `Single White` 后，设备在 App 中按仅亮度控制处理，不展示 CCT 控制。
  - 对应组控能力也会受影响。
- `Absolute CCT Range` 说明需要表达：
  - 设备支持较宽色温范围。
  - 若灯具无法反馈或自动匹配实际色温范围，需要手动设置。
  - 设置后，App 控制页面的 CCT 调节范围受该范围限制。

## 数据流

保持现有数据流不变。

| 属性 | 启用后保存方式 |
|---|---|
| `Change Control Page` | 与 rated power 逻辑一致，启用后参与 SET UP；不下发设备，更新本地和云同步字段 |
| `Absolute CCT Range` | 与 rated power 逻辑一致，启用后参与 SET UP；需要设备参数下发成功后保存 |

多设备同 PID 进入设置页时：

- 若设备值一致，启用后展示设备值。
- 若设备值冲突，启用后展示该设备类型默认值。
- `Reset` 永远恢复为该设备类型默认值。

删除设备后：

- 仍按现有逻辑清除设备配置。
- 重新添加后使用默认值。

## 资源复用

不需要新增或上传图片资源。

优先复用现有资源：

| 用途 | 资源 |
|---|---|
| radio 选中 | `select` |
| radio 未选中 | `select_un` |
| slider 减少 | `scene_data_value_minus` |
| slider 增加 | `scene_data_value_add` |
| slider thumb | `slider_point` 或纯 CALayer 绘制 |

若后续要求完全复刻 Figma 的开关或滑轨图片，再单独补充资源。

## 影响范围

预期改动文件范围：

| 文件 | 目的 |
|---|---|
| `DeviceParameterSettingsViewCell.swift` | 重做两个 CCT cell，并增加 CCT 专用 slider |
| `DeviceParameterSettingsController.swift` | 给 CCT cell 传入默认值，处理 Reset 回调 |
| `Node+Propertys.swift` | 修正特殊设备 company ID |
| `MeshNetwork+SunSmart.swift` | 修正特殊设备隐藏 PWM frequency 的 company ID |
| `Localizable.strings` | 更新或新增说明文案 |

不修改：

- CCT 支持判断入口。
- 云同步 JSON 字段结构。
- Absolute CCT Range 下发参数类型。
- 其他 Device Parameter Settings 属性 UI。

## 验证

实现完成后需要验证：

| 类型 | 内容 |
|---|---|
| 静态检查 | 不引用 Figma 远程资源；无 `0x0178 / 0x2013` 特殊判断残留 |
| UI 逻辑检查 | 特殊设备默认 `Single White`、`2700K...5000K`；普通 CCT 默认 `Tunable White`、`2700K...6500K` |
| Slider 检查 | min 可到 `2700K`，max 可到 `5000K`，不能停留在 `(2700K, 5000K)` |
| 构建 | 按项目指定命令构建 `SunSmart` target |

构建命令：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
