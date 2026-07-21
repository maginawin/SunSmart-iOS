# Battery/AC Power Switch Edit Panel 锁定设计

## 背景

Battery power switch 与 AC power switch 共用独立的 Edit Switch 页面。当前页面中的 Panel 行固定使用带箭头样式，并在具备编辑权限时统一响应点击，因此无论虚拟设备还是已经 LINK 的真实设备，都可以进入 Select Panel 页面修改 Panel 类型。

真实 Battery/AC power switch 的 Panel 类型由实际设备型号决定，不应在 App 的 Edit 页面中被修改；未 LINK 的虚拟 Battery/AC power switch 则需要继续允许用户选择 Panel 类型，以便后续按所选类型匹配并 LINK 真实设备。

## 目标

- 虚拟 Battery power switch 的 Panel 行保留右侧箭头，允许进入 Select Panel 页面。
- 虚拟 AC power switch 的 Panel 行保留右侧箭头，允许进入 Select Panel 页面。
- 真实 Battery power switch 的 Panel 行保留当前 Panel 值，隐藏右侧箭头，点击不跳转。
- 真实 AC power switch 的 Panel 行保留当前 Panel 值，隐藏右侧箭头，点击不跳转。
- 虚拟设备完成 LINK 并刷新当前 Edit 页面后，Panel 行立即切换成真实设备的只读状态。

## 范围

本次只调整独立的 Edit Switch 页面，包括从 Main - Switches 长按入口和 power switch monitor 页进入的同一编辑器。

不调整：

- Group 页面中的 Group Power Switch 展开卡片及其 Panel 行。
- Select Panel 页面自身的布局和选择逻辑。
- Battery/AC power switch 的 Create 页面既有 Panel 选择能力。
- Group、Scene、More Settings 等其他信息行。
- Panel 类型的协议、持久化、同步、导入导出或设备型号映射。
- 现有 Space edit 权限语义。

## 已确认的当前实现

- 独立 Edit Switch 页面由 `PJPreAddEightKeySwitchesVC` 管理。
- 页面内容由 `PJEightKeySwitchEditorView` 组合。
- Panel、Group、Scene、More Settings 共用 `PJEightKeySwitchInfoRowView`。
- Panel 行当前固定为带值和箭头的样式，点击统一调用 Select Panel 跳转。
- 页面已经通过当前持久化 switch 数据判断是否真实 LINK，无需新增另一套 virtual/real 规则。
- LINK 完成后，页面会重新绑定最新 switch 数据，适合在同一刷新链路中同步更新 Panel 行状态。

## 方案比较

### 方案 A：动态配置共享 Panel 行（采用）

让共享信息行支持运行时显示或隐藏箭头，再由 Edit 页面根据真实设备绑定状态控制 Panel 行的视觉和点击能力。

优点：改动集中；复用现有真实设备判断；支持 LINK 完成后的实时状态切换；不影响其他页面。

### 方案 B：分别创建可编辑和只读 Panel 行

为虚拟设备和真实设备各维护一个 Panel 行，再按状态切换。

缺点：产生重复视图和约束，状态刷新时需要维护两套内容，不符合最小改动原则。

### 方案 C：拆分虚拟与真实设备编辑器

为两类设备维护不同的 Edit Controller 或 View。

缺点：除 Panel 行外绝大部分编辑逻辑完全相同，拆分会扩大影响面和回归风险。

## 采用的设计

### 1. 单一状态来源

Edit 页面继续复用已有真实设备绑定判断。判断基于当前实时/持久化的 switch 数据，而不是根据页面标题、Battery/AC 类型或临时表单值推测。

Panel 类型是否允许修改的规则为：

- 具备 edit 权限。
- 当前 switch 未 LINK 到真实设备。

只有两个条件同时满足时，Panel 行才能响应点击。

### 2. Panel 行视觉状态

`PJEightKeySwitchInfoRowView` 增加运行时切换箭头显示状态的能力，但保持现有初始化样式和其他信息行行为不变。

- 虚拟设备：显示箭头，Panel 值保持当前带箭头布局。
- 真实设备：隐藏箭头，Panel 值右侧间距调整为普通只读信息行布局，避免箭头消失后留下多余空白。

箭头显隐只由 virtual/real 状态决定。现有无 edit 权限时的其他页面行为不在本次需求中扩展。

### 3. 点击保护

采用两层保护：

- UI 层：真实设备的 Panel 行关闭点击交互。
- 跳转层：进入 Select Panel 的动作再次检查当前是否仍为虚拟设备。

这样即使后续事件绑定或页面刷新逻辑发生变化，真实设备也不能进入 Select Panel 页面。

### 4. 状态刷新

首次绑定页面数据时统一刷新 Panel 行状态。虚拟设备完成 LINK 后，现有编辑数据刷新流程会重新绑定最新 switch 数据，并在同一处更新：

- Panel 行箭头显隐。
- Panel 行点击能力。
- LINK/LINKED 状态。

不新增通知、缓存字段或额外 virtual/real 状态。

## 行为矩阵

| 设备状态 | Panel 值 | 右侧箭头 | 点击 Panel 行 |
| --- | --- | --- | --- |
| Virtual Battery | 显示 | 显示 | 进入 Select Panel |
| Virtual AC | 显示 | 显示 | 进入 Select Panel |
| Real Battery | 显示 | 隐藏 | 无响应 |
| Real AC | 显示 | 隐藏 | 无响应 |

## 权限与边界行为

- 虚拟设备只有在现有 `canEdit` 条件成立时才能点击 Panel 行。
- 真实设备即使具备 edit 权限，也不能点击 Panel 行。
- Create 模式没有真实设备绑定，继续允许选择 Panel 类型。
- Group、Scene、More Settings 行继续按现有权限和点击规则工作。
- Panel 值始终显示，不因只读状态隐藏或置空。
- 不新增提示文案；点击真实设备 Panel 行不会显示 toast 或弹窗，因为该行已经通过无箭头表达只读状态。

## 影响文件

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift`
  - 为既有带值箭头行补充动态箭头显隐及对应右侧布局更新能力。
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - 复用已有真实设备绑定判断，统一配置 Panel 行状态并增加跳转保护。

不需要修改 ViewModel、Model、Repository、数据库、本地化资源、target 配置或 NordicSigMeshSDK。

## 验收用例

1. Virtual Battery power switch Edit 页面显示 Panel 箭头，点击进入 Select Panel，选择后能更新 Panel 值和预览。
2. Virtual AC power switch Edit 页面显示 Panel 箭头，点击进入 Select Panel，选择后能更新 Panel 值和预览。
3. Real Battery power switch Edit 页面显示当前 Panel 值，不显示箭头，点击无跳转。
4. Real AC power switch Edit 页面显示当前 Panel 值，不显示箭头，点击无跳转。
5. Virtual Battery/AC power switch 完成 LINK 并返回当前 Edit 页面后，Panel 行立即隐藏箭头且不可点击。
6. Create Battery/AC power switch 页面仍可进入 Select Panel。
7. Group 页面中的 Group Power Switch 展开卡片保持现状。
8. Group、Scene、More Settings 行行为不变。
9. 无 edit 权限时，现有编辑限制保持不变。

## 验证计划

- 源码检查：确认 Panel 行视觉状态与点击 guard 使用同一真实设备绑定语义。
- 定向回归：覆盖 Virtual/Real 与 Battery/AC 的四种组合，并检查 LINK 前后状态切换。
- 共享组件回归：确认 Group、Scene、More Settings 行仍显示箭头且可按原规则交互。
- 范围检查：确认 Group Power Switch 页面没有业务改动。
- 静态检查：执行 `git diff --check`。
- 构建验证：直接执行 SunSmart iPhoneOS `xcodebuild`，不使用 Simulator。

## 设计自检

- 需求中的四种设备状态均有明确行为。
- virtual/real 判断复用现有真值，不引入重复状态。
- 视觉状态、点击状态和 LINK 后刷新链路一致。
- 修改范围限定在独立 Edit Switch 页面及其共享信息行能力，不扩展 Group 页面。
- 不涉及新文案、本地化、资源、target、依赖、协议或 SDK 改动。
