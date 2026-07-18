# Simulate Fault View Controller 改造设计

## 背景与目标

`DeviceLightViewController` 有两类进入方式：

- 从 Lights 设备列表进入时，设备详情包在 `NavigationViewController` 中以默认 modal 样式展示。
- 从 Group 相关页面进入时，设备详情通过 Navigation Controller push。

当 Simulate Fault 仅是设备页内的 UIView overlay 时，它与外层设备页的 modal/pop 生命周期耦合。外层交互式转场可触发 `viewWillDisappear`，从而在转场未必完成时提前移除 overlay。

本次改造目标是将 Simulate Fault 变为独立 View Controller，让系统 presentation controller 管理展示、半透明背景、下滑关闭和 modal 生命周期，避免继续与底层设备页手势耦合。

## 方案决策

采用独立 `SimulateFaultViewController`，设置 `modalPresentationStyle = .automatic`。

方案取舍已确认：

- 使用 UIKit 在当前系统和当前设备上选择的原生 modal/sheet 形态。
- 由系统控制宽度、高度、圆角、转场和半透明 dimming 效果。
- 不再强制遮罩等于黑色 `alpha = 0.3`，仅保留系统半透明背景的视觉语义。
- 不再强制弹窗与 Device List 页面同宽或高度完全由内容推导。
- 保留系统下滑关闭，不实现自定义 pan gesture。
- 取消“点击弹窗内容区域外必须关闭”的要求。

## 为什么不强行支持外部点击关闭

`.automatic` 样式下，弹窗外的 dimming 区域属于系统 `UIPresentationController` 管理的 container，不在 `SimulateFaultViewController.view` 的触摸范围内。因此新 VC 不能靠根视图 tap gesture 稳定收到外部点击。

把手势动态添加到系统 `containerView` 会依赖系统 presentation 层级，并可能与原生 sheet pan 和底层交互竞争，不作为跨系统版本方案。如果改用自定义 `UIPresentationController`，则已不再是本次确认的纯 `.automatic` 设计。

## 组件边界

### SimulateFaultViewController

职责：

- 承载 header、内容 Scroll View、stack view 和三个 Simulate Fault section。
- 直接接收并处理 `SimulateFaultAction`，不向 `DeviceLightViewController` 或 `DeviceLightsViewController` 回传。
- 监听 Space 权限变化；丢失有效 edit capability 时调用系统 `dismiss(animated: true)`。

不负责：

- 不自定义 modal transition、dimming view 或下滑手势。
- 不发送 Mesh 命令。
- 不保留 item 选中状态。
- 不修改 Node 或 Space 数据。

### SimulateFaultSectionView

保留现有实现：

- Header 左侧 label、右侧 tag。
- Collection View item 使用固定宽高、自动换行和瞬时高亮点击效果。
- 点击 item 产生 typed action，不关闭弹窗。

### DeviceLightViewController

改造后仅负责：

- 继续使用 `space.deviceOperates.contains(.edit)` 决定菜单可见性并在展示前二次校验。
- 创建并 present `SimulateFaultViewController`。

删除：

- `simulateFaultOverlayView` 弱引用。
- `viewWillDisappear` 中针对 overlay 的 dismiss。
- 交互式 pop 手势的保存、禁用和恢复。
- `handleSimulateFaultAction` 回传入口。

## 布局

- 新 VC 根视图使用系统 sheet 背景和顶部圆角，不再在业务层绘制遮罩或弹窗外形。
- Header 和三个 section 位于 Scroll View 内，Scroll View 覆盖 VC 可用内容区域。
- Stack View 的水平 inset、section 间距、图标、字体、颜色和 item 尺寸继续复用现有值。
- Collection View 高度仍根据 item 换行数计算；系统 sheet 宽度变化后重新计算。
- iPad 等宽屏上，Light Status 在系统分配宽度允许时保持一排；不再强制 sheet 宽度等于底层设备页。
- 内容高于系统分配的 sheet 可用高度时，通过 Scroll View 访问全部内容。

## 展示与关闭

- `DeviceLightViewController` 使用标准 `present(viewController, animated: true)`。
- `SimulateFaultViewController.modalPresentationStyle = .automatic`。
- 不设置 `isModalInPresentation = true`，允许系统交互式下滑关闭。
- 不自定义 `UISheetPresentationController.detents`，由当前系统选择展示尺寸，避免为不同系统版本建立分支策略。
- 权限丢失时主动调用 `dismiss(animated: true)`。
- 不增加外部点击手势；用户主要通过系统下滑手势关闭。

## 导航手势边界

- Simulate Fault 是 modal View Controller，不是 push 页面，自身不使用横向侧滑返回。
- Simulate Fault 显示时，不人工修改底层 `interactivePopGestureRecognizer`。原生 modal 层负责管理与底层页面的交互关系。
- Simulate Fault 关闭后，底层设备页继续保持原生行为：push 入口可横向侧滑返回，modal 入口可使用系统纵向拖动关闭。

## 按钮事件处理

- Section View 继续将 item 点击转换为 `SimulateFaultAction`。
- `SimulateFaultViewController` 内部的 `handleAction` 直接接收 action。
- 点击后不关闭弹窗，不显示选中状态。
- 本次范围内 `handleAction` 不发送命令、不修改数据，仅建立 VC 内部 typed action 处理边界。
- 不增加向其他控制器的 action callback。

## 权限

- 菜单仍仅在有效 edit capability 下显示。
- 点击菜单时再次校验 edit capability，防止菜单展示后权限变化。
- 新 VC 接收 `SpaceData`，用于监听展示期间的权限变化并在权限丢失时主动关闭。

## 测试与验收

### 自动化验证

- 静态契约：新 VC 明确使用 `.automatic`，允许交互式 dismiss，不安装自定义 outside tap 或 pan gesture。
- 静态契约：新 VC 内部处理 typed action，不使用 Mesh API，不向其他控制器回传。
- 静态契约：`DeviceLightViewController` 不再持有 overlay，不再操作 interactive pop gesture。
- 现有菜单图标、权限、国际化、固定内容和无选中状态契约继续通过。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target 使用 iPhoneOS Debug 构建。

### 人工验收

- 从 Lights 列表的 modal 设备页和 Group 的 push 设备页分别打开 Simulate Fault。
- 弹窗使用当前系统的原生 sheet/modal 样式，背景保持系统半透明效果。
- 内容区滑动和 item 点击不关闭，item 点击不显示选中状态。
- 通过系统下滑手势关闭 Simulate Fault。
- 小屏或较矮 sheet 上所有内容可通过 Scroll View 访问。
- Simulate Fault 关闭后，底层设备页的 push 侧滑返回或 modal 下滑关闭保持原生行为。
- iPhone 和 iPad 均接受 UIKit 在当前系统上选择的宽度、高度和 dimming 效果。

## 范围边界

- 仅改造 light 设备页的 Simulate Fault。
- 不修改其他设备页、其他 popup 或全局 modal 样式。
- 不修改 Mesh SDK、协议或命令发送。
- 不修改已确认的文案、图标、固定 item 内容和无选中状态要求。
