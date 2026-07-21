# Battery/AC Power Switch Monitor Enable 状态图片设计

## 背景

Battery power switch 与 AC power switch 共用 Monitor 页面底部的 Settings 弹窗。该弹窗当前有三处使用 switch 外观表达 Enable/Disable 状态：

- 弹窗顶部 `Enable` 右侧使用只读 `UISwitch`。
- 展开区域的图例中，`Enable` 左侧使用自绘 mini switch。
- 展开区域的图例中，`Disable` 左侧使用自绘 mini switch。

顶部 `UISwitch` 已通过透明触摸拦截层实现只读，展开区域的 mini switch 也不可交互。本次将三处统一改为图片状态展示，进一步明确它们仅用于表达状态，不提供切换操作。

现有 Assets 中已经包含：

- `sensor_occupy`
- `sensor_unoccupy`

无需新增或修改图片资源。

## 目标

- 顶部 `Enable` 右侧不再显示 `UISwitch`，改为 20 × 20 状态图片。
- 当前状态为 Enable 时，顶部显示 `sensor_occupy`。
- 当前状态为 Disable 时，顶部显示 `sensor_unoccupy`。
- 展开图例的 `Enable` 左侧显示 20 × 20 的 `sensor_occupy`。
- 展开图例的 `Disable` 左侧显示 20 × 20 的 `sensor_unoccupy`。
- 三张图片全部不可点击，不触发任何状态修改或设备命令。
- 保留现有 Enable/Disable 发送流程代码，便于未来重新启用交互能力。

## 范围

本次只调整 Battery/AC power switch Monitor 页面底部 Settings 弹窗的 Enable/Disable 状态展示。

不调整：

- 独立 Edit Switch 页面的 Enable 控件。
- Group Power Switch 页面中的 Enable 控件。
- Monitor 页面顶部状态、Panel 控制、Group Link、Groups 列表或展开/收起行为。
- Virtual、Battery、AC 的 Enable/Disable 数据模型、持久化、同步或发送逻辑。
- 本地化、资源、target、依赖、协议或 NordicSigMeshSDK。

## 已确认的当前实现

- 底部弹窗由 `PJEightKeySwitchMonitorStatusSetView` 管理。
- 顶部 `UISwitch` 读取 `State.isEnabled` 显示当前状态。
- 顶部 `UISwitch` 目前由透明 `UIControl` 覆盖，因此用户无法切换。
- 展开图例使用两个 `PJEightKeySwitchMiniSwitchLegendView` 分别绘制 Enable 和 Disable 状态。
- `PJEightKeySwitchMonitorVC` 仍通过 `enableChanged` 连接既有 Virtual/Battery/AC 更新与发送流程。
- `sensor_occupy` 和 `sensor_unoccupy` 已存在于共享 Assets 中。

## 方案比较

### 方案 A：直接使用 UIImageView 替换三处 switch 展示（采用）

顶部状态和展开图例均改用 `UIImageView`，统一复用现有图片资源。删除不再使用的 `UISwitch`、透明触摸拦截层及 mini switch 绘制实现，但保留外部 Enable/Disable 发送流程。

优点：视图语义明确、层级简单、改动集中、不引入新资源或新组件。

### 方案 B：新增通用 Enable 状态图片组件

封装统一的状态与图片映射，再由顶部和图例复用。

缺点：当前只有三处固定展示，新增组件和接口的维护成本高于收益。

### 方案 C：在 UISwitch 上方覆盖图片

继续保留 UISwitch 和触摸拦截层，再叠加状态图片。

缺点：不可见交互控件、拦截层和图片并存，视图层级复杂，未来更容易出现点击或布局问题。

## 采用的设计

### 1. 顶部状态图片

用一个 `UIImageView` 替换顶部 `UISwitch` 和透明触摸拦截层。

- 图片根据 `State.isEnabled` 在每次 `configure(state:)` 时更新。
- Enable：`sensor_occupy`。
- Disable：`sensor_unoccupy`。
- 图片使用 `scaleAspectFit`。
- 宽高均使用项目现有缩放规则表达 20pt，保持视觉为正方形。
- 图片右侧继续与弹窗保持现有 24pt 语义间距。
- `Enable` 文案继续位于状态图片左侧，保持现有 8pt 语义间距。

顶部状态图片位于可展开的 `headerButton` 上方。为避免触摸穿透到底层按钮，顶部 `UIImageView` 自身启用 hit testing，但不绑定任何手势或 action；它只消费图片区域的触摸，不触发状态切换，也不触发弹窗展开/收起。

### 2. 展开图例图片

将原来的两个 mini switch view 替换为两个 `UIImageView`：

- `Enable` 左侧固定显示 `sensor_occupy`。
- `Disable` 左侧固定显示 `sensor_unoccupy`。
- 两张图均为 20 × 20，使用 `scaleAspectFit`。
- 复用现有普通图例 item 构建逻辑，使 Group Linked、Group Unlinked、Enable、Disable 四项使用一致的图片与文案间距。

状态卡片高度、图例整体排列和弹窗展开高度保持不变。

### 3. 清理不再使用的 UI 实现

在同一 View 文件内移除仅为旧 switch 外观服务的实现：

- 顶部 `UISwitch` 属性、target 和颜色配置。
- 顶部透明触摸拦截层。
- 展开图例的 mini switch 尺寸常量。
- mini switch 专用 track/knob 颜色。
- mini switch item 构建方法。
- `PJEightKeySwitchMiniSwitchLegendView` 私有绘制类。

这属于替换目标 UI 所必需的局部清理，不扩展到其他模块。

### 4. 保留 Enable/Disable 发送流程

继续保留：

- `PJEightKeySwitchMonitorStatusSetView.enableChanged` 回调接口。
- `PJEightKeySwitchMonitorVC` 中既有 `bottomView.enableChanged` 绑定。
- Virtual switch 的本地 Enable 更新流程。
- Battery power switch 的 activation / Tx Enable 流程。
- AC power switch 的直接 Tx Enable 发送流程。

由于当前图片不绑定点击事件，上述路径不会从底部弹窗触发；保留它们仅用于未来恢复交互能力。本次可以移除只服务于旧 `UISwitch.valueChanged` 的私有 UI action 方法，但不能删除 Controller 或发送层流程。

## 状态与图片映射

| 位置 | 状态/含义 | 图片 | 尺寸 | 交互 |
| --- | --- | --- | --- | --- |
| 顶部 `Enable` 右侧 | `isEnabled == true` | `sensor_occupy` | 20 × 20 | 无 |
| 顶部 `Enable` 右侧 | `isEnabled == false` | `sensor_unoccupy` | 20 × 20 | 无 |
| 图例 `Enable` 左侧 | Enable 含义 | `sensor_occupy` | 20 × 20 | 无 |
| 图例 `Disable` 左侧 | Disable 含义 | `sensor_unoccupy` | 20 × 20 | 无 |

`State.isPending` 不改变图片映射。旧 UI 在 pending 和非 pending 状态下都由透明层保持只读，新 UI 继续只展示 `isEnabled` 对应状态。

## 错误处理

本次不新增网络、协议、存储或异步操作，因此不新增错误提示。图片资源已存在；实现时通过源码检查确认资源名准确，并通过 iPhoneOS 构建验证资源引用和代码编译。

## 影响文件

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift`
  - 替换顶部状态和展开图例 UI。
  - 清理旧 switch 展示相关私有实现。
- Inspect only: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 确认 Enable/Disable Controller 绑定与发送流程保留。

不需要修改本地化文件、Assets、target 配置、依赖或 SDK。

## 验收用例

1. Battery power switch 为 Enable 时，弹窗顶部显示 20 × 20 的 `sensor_occupy`。
2. Battery power switch 为 Disable 时，弹窗顶部显示 20 × 20 的 `sensor_unoccupy`。
3. AC power switch 为 Enable 时，弹窗顶部显示 20 × 20 的 `sensor_occupy`。
4. AC power switch 为 Disable 时，弹窗顶部显示 20 × 20 的 `sensor_unoccupy`。
5. 展开图例中，`Enable` 左侧显示 20 × 20 的 `sensor_occupy`。
6. 展开图例中，`Disable` 左侧显示 20 × 20 的 `sensor_unoccupy`。
7. 点击顶部状态图片或图例图片均不触发状态变化、设备命令或弹窗展开/收起。
8. Group Linked、Group Unlinked、Groups 列表和弹窗展开/收起行为保持现状。
9. Monitor Controller 中 Virtual/Battery/AC Enable/Disable 更新与发送流程代码保持存在。

## 验证计划

- 源码检查：确认三处图片映射均使用指定资源名。
- 尺寸检查：确认三张图片约束均为 20 × 20。
- 交互检查：确认顶部状态图片启用 hit testing 但没有 gesture、target 或 action，点击不会穿透到 `headerButton`；图例图片没有交互绑定。
- 清理检查：确认旧顶部 UISwitch、透明拦截层和 mini switch 绘制类已从目标 View 移除。
- 流程保留检查：确认 Controller 中 Enable/Disable 绑定、Virtual 更新、Battery Tx Enable 和 AC Tx Enable 路径未删除。
- 范围检查：确认 Assets、本地化、target、依赖和 SDK 无本需求差异。
- 静态检查：执行 `git diff --check`。
- 构建验证：直接执行 SunSmart iPhoneOS `xcodebuild`，不使用 Simulator。

## 设计自检

- 顶部动态状态和展开图例固定含义均有明确图片映射。
- 三张图片的尺寸和无业务交互语义一致；顶部图片额外消费触摸，避免命中底层展开按钮。
- UI 替换与发送流程保留要求不冲突：当前无触发入口，但底层路径仍存在。
- 业务改动聚焦在一个 View 文件，Controller 仅检查不修改。
- 不涉及新文案、资源、本地化、target、依赖、协议、存储或 SDK 改动。
