# Battery/AC Power Switch Edit Panel Size 修复计划

## 背景

用户反馈：battery power switch / ac power switch 的 Edit 页面，在 iPad 上展示的 panel type 图片过大。

预期行为：

- 与 kinetic switch 的 Edit 页面中展示的 panel type 图片保持相同尺寸。
- Cell / 预览区域高度与 kinetic switch Edit 页面一致。
- iPad 与 iPhone 都复用 kinetic switch 的尺寸逻辑。

## 真实性分析

结论：问题大概率真实，且根因集中在 Edit 页公共 panel preview 尺寸策略，而不是 Battery/AC 图片资源本身。

依据：

- `PJPreAddEightKeySwitchesVC` 是 Battery/AC power switch Edit 的入口之一，`PJEightKeySwitchMonitorVC.pushEditor()` 会 push 到该编辑器。
- `DeviceSwitchesViewController` 中 kinetic 8-key switch 的编辑也会进入 `PJPreAddEightKeySwitchesVC`，因此修复应优先放在该编辑器的共享 UI 层，避免 Battery/AC 单独补丁。
- `PJEightKeySwitchEditorView.updatePanelPreviewHeight()` 当前按 `panelPreviewView.bounds.width` 动态计算高度。
- `PJEightKeySwitchPanelView.preferredHeight(for:)` 在 preview 模式下，如果存在图片资源，会按图片原始比例计算高度；iPad 上容器更宽时，高度会随宽度放大。
- `Scene Panel (8 key)` 与 `Brightness Panel (8 key)` 图片资源尺寸均为 343x320，资源本身没有发现 Battery/AC 专属异常。

## 影响范围

优先检查和修改：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchEditorView.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchPanelView.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

只读确认：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`
- `SunSmart/Main/Device/Controller/DevicesViewController.swift`
- `SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift`

不建议纳入本次改动：

- 不改图片资源。
- 不改 Battery/AC 业务保存、LINK、Sync、activation 逻辑。
- 不修改 target 配置、资源引用或本地化。

## 修复方案

### 方案 A：使用 kinetic 基准高度统一 8-key panel preview

这是推荐方案。

做法：

1. 在 `PJEightKeySwitchPanelView` 内定义 kinetic 基准高度。
2. Edit 页、Select Panel 页、Group Power Switch 展开卡片都复用同一个高度常量。
3. `preferredHeight(for:)` 不再按 iPad 宽度和图片比例放大，而是返回 kinetic 基准高度。
4. Battery、AC、kinetic 都通过同一个方法计算尺寸，不根据 `powerSwitchKind` 分叉。

优点：

- 改动集中在 8-key panel preview UI，风险可控。
- 符合“Battery/AC 与 kinetic 完全一致”的预期。
- Edit、Select Panel、Group 展开卡片三处一致。

风险：

- 如果 iPhone 当前高度已经符合预期，需避免新增上限导致小屏显示压缩。

### 方案 B：调整 `PJEightKeySwitchPanelView.preferredHeight(for:)` 为全局上限

不推荐作为首选。

原因：

- `PJEightKeySwitchPanelView` 被 Select Panel 页面和 Group Power Switch cell 复用。
- 全局收敛会改变多个页面的 cell 高度和图片展示，不符合本次“Edit 页面”聚焦修复。

## 推荐实施步骤

1. 确认 kinetic Edit 页现有 iPad 目标尺寸。
   - 从 `DeviceSwitchesViewController` 长按 kinetic 8-key switch 进入 Edit。
   - 以旧 kinetic panel cell 的 288 内容高度作为新 8-key preview 基准。

2. 在 `PJEightKeySwitchPanelView` 增加统一预览尺寸策略。
   - 统一供 kinetic、Battery、AC 使用。
   - iPad / iPhone 都不随容器宽度无限放大。

3. 调整 `panelPreviewView` 约束。
   - 保持顶部间距、左右布局与现有表单一致。
   - 高度由统一策略更新，不写 Battery/AC 特例。

4. 同步 Select Panel 页与 Group Power Switch 展开卡片。
   - Select Panel cell 使用同一 preview cell 高度。
   - Group Power Switch 展开卡片的容器高度和 row height 使用同一 preview/action 高度。

5. 验证编辑入口。
   - kinetic switch Edit：iPad / iPhone。
   - Battery power switch Edit：iPad / iPhone。
   - AC power switch Edit：iPad / iPhone。
   - 切换 `Scene Panel (8 key)` 与 `Brightness Panel (8 key)` 后，预览高度不跳成异常大图。
   - 进入 LINK 后返回 Edit，预览尺寸保持一致。

6. 构建验证。
   - 使用 iPhoneOS `xcodebuild`，不使用 Simulator 作为交付校验。
   - 运行推荐命令：
     `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 验收标准

- iPad 上 Battery/AC Edit 的 panel type 图片尺寸与 kinetic Edit 一致。
- iPad 上 Battery/AC Edit 的预览区域高度与 kinetic Edit 一致。
- iPhone 上 kinetic、Battery、AC Edit 的布局逻辑一致，没有新增异常留白或裁切。
- Select Panel 页面使用同一 preview 高度。
- Group Power Switch 展开卡片使用同一 preview 高度。
- `SunSmart` iPhoneOS Debug 构建通过。

## 待确认点

已确认：

1. 以“Switch 列表长按进入 kinetic 8-key Edit”作为视觉基准。
2. 同步调整 Select Panel 页和 Group Power Switch 展开卡片。
