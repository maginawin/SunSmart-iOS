# Path Sequence 设备控件固定尺寸需求分析与待确认方案

## 1. 文档状态

- 当前状态：方案 A 已于 2026-07-28 获得确认，允许进入实施计划与 Inline Execution。
- 本轮范围：只分析 Sequence、Trigger Zone 和 `GroupPathSequenceDeviceAddView` 中的设备列表布局，不修改业务代码。
- 分析基线：`trigger-zone-july`，HEAD `6e6c53fb`。
- 实施门禁：确认本方案后再编写正式实施计划并修改代码。

## 2. 结论

需求合理、可以实现，而且有必要同时处理 iPhone 和 iPad。

当前布局在标准 375pt 宽 iPhone 上，设备控件宽度通过现有公式恰好接近 44pt；在标准 834pt 宽 iPad 上，同一公式会得到约 78pt。因此当前 UI 并不是稳定的 44×44，而是“iPhone 偶然接近目标、iPad 随容器放大”。

不能只把现有 `SCRYFrom` 替换为固定数字。完整尺寸链还包含：

- Collection View 根据容器宽度计算 Item 宽度。
- Sequence 自定义 Layout 根据 Item 宽度绘制连接线。
- Trigger Zone 根据 Item 宽度反推 Table View Cell 高度。
- `GroupPathSequenceDeviceAddView` 中的 Trigger Add 和 Manually Add 通过公共横向 Layout 根据容器宽度计算 Cell 宽高。
- Manually Add 还会根据计算出的 Item 宽度决定多行列表和父 View 高度。

推荐将“设备控件大小”解释为用户实际看到的圆形设备控件固定为 44×44；Collection View 的布局槽位继续自适应宽度，以保持 iPhone 5 列、iPad 8 列和当前均匀分布。若要求 `UICollectionViewCell.frame` 本身也必须严格为 44×44，则应采用本文的备选方案 B。

## 3. 源码现状

### 3.1 Sequence

`GroupPathSequencePathViewCell` 当前存在以下尺寸行为：

- iPhone Item 高度使用 `SCRYFrom(62)`。
- iPad Item 高度使用 `SCRYFrom(90)`。
- Item 宽度由 Collection View 宽度、列数、Inset 和间距动态计算。
- 可见圆形 `boxView` 的宽度等于整个 Item 宽度。
- 顶部 `sequenceLabel` 只有顶部和水平中心约束，没有固定 16pt 高度。
- 设备图片依赖图片资源固有尺寸，没有显式 20×20 约束。
- iPhone 和 iPad 使用不同的图片顶部、图片与名称间距。

在标准宽度下：

- iPhone：Item 宽度约 44，圆形控件约 44。
- iPad：Item 宽度约 78，圆形控件约 78。

因此 Sequence 确实同时受到纵向 `SCRYFrom` 和横向容器宽度计算影响。

### 3.2 Trigger Zone

`GroupPathSequenceTriggerZoneViewCell` 复用 `GroupPathSequencePathItem`，只是隐藏顶部 `sequenceLabel`。

当前行为：

- Item 通过 `sizeForItemAt` 使用动态宽度，并让高度等于宽度。
- Table View Cell 自适应高度再次根据动态 Item 宽度计算。
- 行间距、Section 上下 Inset、最小高度和部分交互菜单指标使用 `SCRYFrom`。
- iPad 上 Item 同样约为 78×78，不是目标的 44×44。

此外，自适应高度使用 Table View 提供的目标宽度计算 Item 宽度，但 Collection View 本身还有左右 8pt 外部约束，两者当前存在轻微宽度口径差异。改成固定 44pt 设备高度后，可以顺便消除这个误差来源。

### 3.3 `GroupPathSequenceDeviceAddView`

公共父 View `GroupPathSequenceDeviceAddView.swift` 已在前序任务中移除了 `SCRXFrom` 和 `SCRYFrom`，并使用固定外壳指标，因此父 View 本身无需为本需求再次改造。

展示设备的直接 Cell 是 `GroupPathSequenceAddDeviceCell`：

- Cell 文件当前没有直接使用 `SCRYFrom`。
- 设备图片依赖资源固有尺寸，当前资源实际为 20×20pt。
- Cell 的圆角和边框直接作用于整个 Cell。
- Cell 最终宽高由 `HorizontalDirectionFlowLayout` 根据容器宽度计算。

因此这里属于“没有直接使用 `SCRYFrom`，但设备控件仍被间接放大”：

- iPhone 上约 44×44。
- iPad 上约 78×78。

Trigger Add 当前 Collection View 高度已经固定为 68，但 iPad Item 仍可能按约 78pt 生成，存在裁剪或内部空间不一致风险。Manually Add 则继续用动态 Item 宽度计算列表高度，使 iPad 内容高度随设备宽度放大。

## 4. 需求合理性

### 4.1 合理部分

- 44×44 是稳定且符合最小触控尺寸的设备控件规格。
- 设备图标固定为 20×20，可以避免依赖资源固有尺寸。
- Sequence 顶部标签固定为 16，可以明确得到 60pt 的 Item 纵向内容高度。
- iPhone、iPad 使用同一设备控件尺寸，可以消除当前约 44pt 与约 78pt 的视觉差异。
- 清理设备列表尺寸链中的 `SCRYFrom`，可以避免同一宽度设备因屏幕高度不同而产生不同控件高度。

### 4.2 需要明确的边界

推荐本次只清理“设备列表尺寸链”中的 `SCRYFrom`，不对两个页面的所有 `SCRYFrom` 做全文件或全页面清理。

例如以下内容不属于设备控件尺寸链，建议保持现状：

- 页面空状态位置。
- Table View 外壳圆角和页面顶部间距。
- Section Header 的按钮尺寸与圆角。
- 非设备 Item 的弹出菜单整体视觉重设计。

这样可保持改动聚焦，避免把一个设备尺寸需求扩大为整个 Path Sequence 页面的响应式布局重构。

## 5. 容易遗漏的影响

### 5.1 Sequence 连接线

Sequence 的连接线由 `GroupPathSequencePathLayout` 根据 Item 中心和 Item 宽度计算。

如果仅把内部圆形控件改为 44，而仍用自适应布局槽位宽度计算转角端点，iPad 上转角线会连接到布局槽位边缘，而不是 44pt 圆形控件边缘。因此连接线端点必须使用固定控件宽度 44 计算。

### 5.2 Sequence Add Item

Sequence 首尾的 Add Item 与设备 Item 共用同一行高和布局槽位。设备圆形控件改为 44 后，Add Item 的虚线圆也应固定为 44，才能保持连接线和上下对齐一致。

顶部 16pt 标签只属于 Sequence 设备位置语义；Add Item 没有标签，但仍保留对应的顶部 16pt 空间，使所有圆形控件位于同一水平线。

### 5.3 Trigger Zone 空数据和多行高度

Trigger Zone 有设备时，每行高度应由固定 44、固定行间距和固定 Section Inset 计算。

没有设备时不能继续使用 `row - 1` 直接参与间距计算，应显式处理零行，继续保留当前 `No Data` 最小高度，避免负间距参与高度公式。

### 5.4 Add View 的选中边框

`GroupPathSequenceAddDeviceCell` 当前直接在整个 Cell Layer 上绘制圆角和选中边框。

推荐增加固定 44×44 的内部设备控件容器，并把边框、圆角、图片和名称移入该容器。Trigger Add 和 Manually Add 的选中状态需要同步改为更新内部容器边框，否则 iPad 上仍会看到宽于 44pt 的选中区域。

Manually Add 的长按拖拽交互挂在整个自适应 Cell 上。若不提供自定义 Drag Preview，UIKit 会默认以 `interaction.view`，即整个 Cell，生成拖拽预览。因此预览尺寸并不保证为 44×44：iPhone 上可能接近 44×44，iPad 上会随自适应槽位变宽；默认预览轮廓也是矩形。应让 lifting preview 直接使用固定 44×44 的内部 `boxView`，并通过圆形 `visiblePath` 与透明背景保持圆形视觉。

拖拽仍挂在 Collection View Cell 上，业务回调和设备地址数据不需要变化。

### 5.5 Add View 高度策略

Trigger Add：

- 保留前序任务已经确认的 68pt Collection View 高度。
- 44pt 设备控件在 68pt 区域内垂直居中。

Manually Add：

- 单行设备内容高度改为固定 44。
- 两到三行使用 `44 × 行数 + 固定行间距`。
- 继续沿用公共父 View 已实现的 160pt 基础内容高度和多行动态增高策略。

不能继续用 Item 动态宽度计算 Manually Add 高度，否则 iPad 仍会比 iPhone 高。

### 5.6 名称显示

设备控件从 iPad 当前约 78pt 缩小到 44pt 后，设备名称的可用空间会减少。现有 `AdaptiveTextView` 可以继续负责字号适配，但需要真机检查长设备名称、English 和简体中文显示效果。

本需求没有要求更改名称字体或截断策略，建议本次不顺手调整。

### 5.7 图片范围

固定 20×20 的对象建议只包含设备在线、离线图片：

- `path_device`
- `path_device_offline`

Sequence Add 图标和方向箭头不是“设备图片”，保持现有资源固有尺寸，避免扩大视觉改动。

### 5.8 多 Target

相关 Swift 文件被四个品牌 Target 共同编译：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

实现后必须同步进行四个 Target 的 generic iPhoneOS 构建验证。

## 6. 方案比较

### 6.1 方案 A：固定可见控件，保留自适应布局槽位（推荐）

做法：

- iPhone 保留 5 列，iPad 保留 8 列。
- Collection View 的 Item 槽位宽度继续按容器均分。
- 槽位内部的圆形设备控件固定为 44×44并水平居中。
- Sequence 槽位高度固定为 60：顶部标签 16 + 圆形控件 44。
- Trigger Zone 槽位高度固定为 44。
- Add View 的设备 Cell 增加内部 44×44 控件容器。
- Sequence 连接线继续使用槽位中心定位，但转角端点改用固定 44pt 控件边界。

优点：

- 最小改动即可保持当前每列中心位置、分页数量和 iPad 8 列布局。
- 不需要改变公共 `HorizontalDirectionFlowLayout` 的全局算法。
- iPad 不会出现所有 44pt Cell 挤在左侧的问题。
- 对现有点击、分页、拖拽和业务回调影响较小。

代价：

- iPad 上 Collection View Cell 的透明布局槽位会宽于 44pt，但用户看到的控件严格为 44×44。
- 点击热区可能大于可见圆形控件；这通常有利于可用性，但不等于 Cell Frame 固定 44。

### 6.2 方案 B：Collection View Cell 本身固定为 44

做法：

- Sequence Cell 为 44×60。
- Trigger Zone 和 Add View Cell 为 44×44。
- 根据容器宽度、列数和左右 Inset 动态计算列间距，保持现有列中心位置。
- Sequence 自定义 Layout、Trigger Zone Flow Layout 和 Add View 横向分页 Layout 都需要支持动态分布固定 Item。

优点：

- Collection View Cell Frame 和可见设备控件都严格符合固定尺寸。
- 点击区域与视觉区域一致。

代价：

- 需要同时调整三套 Layout 行为，改动和回归面更大。
- Add View 使用的 `HorizontalDirectionFlowLayout` 是公共组件，需要增加显式配置并保护其他调用页面。
- 分页宽度、旋转或容器尺寸变化时，需要额外验证动态间距刷新。

适用条件：

- 产品或测试标准明确要求检查 `UICollectionViewCell.frame` 必须为 44×44，而不只是可见设备控件。

### 6.3 方案 C：只把 `SCRYFrom` 替换为固定数字

不推荐。

该方案可以让部分纵向高度固定，但不会改变 iPad 上按容器宽度得到的约 78pt 控件，也不会修复 Add View 的动态 Item 宽高和 Manually Add 高度。因此无法完整满足需求。

## 7. 推荐设计

采用方案 A，并建立以下固定布局契约：

| 对象 | iPhone | iPad |
| --- | ---: | ---: |
| 可见设备控件 | 44×44 | 44×44 |
| 设备图片 | 20×20 | 20×20 |
| Sequence 顶部标签 | 高 16 | 高 16 |
| Sequence 槽位内容高度 | 60 | 60 |
| Trigger Zone 槽位高度 | 44 | 44 |
| Trigger Add Collection View | 高 68 | 高 68 |
| 列数 | 5 | 8 |

设备控件内部统一使用固定布局，不再保留 iPad 专用的图片顶部和图片到名称间距。建议沿用当前 iPhone 视觉关系：

- 图片顶部 3。
- 图片到名称间距 2。
- 名称继续使用现有 `AdaptiveTextView`。

## 8. 预计修改范围

### 8.1 Sequence 与 Trigger Zone 公共 Item

`GroupPathSequencePathViewCell.swift`

- 集中定义设备控件 44、设备图片 20、Sequence 标签 16、Sequence 槽位高度 60。
- Sequence 圆形 `boxView` 固定为 44×44并水平居中。
- `sequenceLabel` 固定高度 16。
- 在线、离线设备图片显式固定为 20×20。
- Add Item 的虚线圆固定为 44×44。
- 移除该设备 Collection View 尺寸链中的 `SCRYFrom`。
- 移除设备控件内部的 iPhone/iPad 两套纵向间距。

`GroupPathSequencePathLayout.swift`

- 默认 Item 高度改为固定 60，不再使用 `SCRYFrom`。
- 容器宽度变化时重新计算槽位宽度，避免缓存旧宽度。
- 转角连接线端点使用固定 44pt 控件边界。

### 8.2 Trigger Zone 高度

`GroupPathSequenceTriggerZoneViewCell.swift`

- Item 高度固定为 44，宽度继续作为自适应布局槽位。
- 行间距、Section 上下 Inset和最小高度使用固定 point。
- Table View Cell 高度使用固定 44 计算，不再根据 Item 宽度反推。
- 对零设备行数做显式保护。
- 移除该文件设备列表尺寸链中的 `SCRYFrom`。

`GroupPathSequenceTriggerZoneController.swift`

- 将仅用于设备行估算的 `estimatedRowHeight` 改为固定值。
- 不改 Table View 外壳、空状态、Header 或页面其他缩放指标。

### 8.3 Add View 设备控件

`GroupPathSequenceAddDeviceCell.swift`

- 增加内部固定 44×44 设备容器。
- 设备图片显式固定为 20×20。
- 圆角和边框从 Cell Layer 移至内部容器。
- 统一内部纵向间距，不再区分 iPhone/iPad。

`GroupPathSequenceTriggerAddView.swift`

- 横向 Layout 的 Item 高度固定为 44。
- 保持 Item 槽位宽度和每页 5/8 个的现有逻辑。
- 44pt 控件在 68pt Collection View 内垂直居中。
- 选中边框改为内部设备容器。

`GroupPathSequenceManuallyAddView.swift`

- 横向 Layout 的 Item 高度固定为 44。
- 单行和多行列表高度改用固定 44 计算。
- 保持 1～3 行展开、分页、拖拽和公共父 View 动态增高。
- 选中边框改为内部设备容器。

`GroupPathSequenceDeviceAddView.swift`

- 预计无需修改。
- 保留当前 fixedBase/dynamicSelected 高度策略、160pt 基础内容高度、closed/open 和 safe area 数据流。

### 8.4 测试

`Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`

- 扩展现有源码合同测试，覆盖固定 44、20、16。
- 覆盖 Sequence 与 Trigger Zone 不再使用纵向缩放计算设备尺寸。
- 覆盖 Trigger Add、Manually Add 的固定设备高度。
- 覆盖 Manually Add 多行高度不再依赖 Item 动态宽度。
- 覆盖选中边框作用于内部 44pt 设备容器。
- 覆盖公共父 View 的既有 160pt、高度策略和空状态合同不回退。

如现有合同测试过于依赖字符串，可在本次聚焦范围内补充最小的 Layout Metrics 计算测试；不为此引入新的测试框架。

## 9. 验收计划

### 9.1 自动化与静态验证

- 新增合同先确认 RED，再做最小实现并确认 GREEN。
- 运行完整 `GroupPathSequenceDeviceAddViewContractTests`。
- 检查相关设备列表尺寸链不再包含 `SCRYFrom`。
- 运行 `git diff --check`。

### 9.2 构建验证

直接使用 `xcodebuild`、generic iPhoneOS、关闭签名，分别构建：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

不使用 Simulator。

### 9.3 真机 UI 验收

iPhone 和 iPad 均检查：

- Sequence 单行、多行、奇偶蛇形排列。
- Sequence 在线、离线、未绑定和首尾 Add Item。
- Sequence 跨行转角连接线是否连接到 44pt 圆形边缘。
- Sequence 顶部编号标签固定为 16，高度和圆形控件对齐。
- Trigger Zone 空数据、单行、多行。
- Trigger Add 有设备、无设备、分页和选中状态。
- Manually Add 一行、两行、三行、分页、拖拽和选中状态。
- 长设备名称、English 和简体中文。
- closed/open 与三种 Add Mode 循环切换后布局不漂移。

自动化和 generic iPhoneOS 构建只能证明源码合同与编译通过，不能替代真机视觉验收。

## 10. 已确认实施边界

已确认按以下解释实施：

1. 采用方案 A：可见圆形设备控件固定为 44×44，Collection View 自适应布局槽位可以宽于 44。
2. `SCRYFrom` 清理范围限定为设备列表尺寸链，不全量清理页面外壳、Header 和空状态。
3. Sequence Add Item 的虚线圆同步固定为 44×44。
4. 20×20 只应用于在线、离线设备图片，不修改 Add 图标和方向箭头。
5. iPhone 保持 5 列、iPad 保持 8 列；两端设备控件使用完全相同的固定尺寸和内部纵向间距。
