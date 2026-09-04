# Space Trigger Zone Filter Widget 布局优化分析与开发计划

## 1. 需求结论

本需求合理，但如果只把 filter widget 外框从 90pt 改为 100pt，`New only` 仍存在被截断的风险。需要同时收紧 Space Trigger Zone 专用状态下标题与下拉箭头之间的间距，才能在保持 100pt 固定宽度的前提下满足“文字完整展示”。

本次应覆盖 Space Trigger Zone 的三种添加模式：

- Quick Add
- Trigger Add
- Manually Add

三种模式由 `SpacePathTriggerZoneController` 同步同一份 Group 筛选和 Added Devices 筛选状态。只修改一种模式会导致用户切换添加方式后控件位置、宽度或弹窗对齐方式不一致。

## 2. 当前实现与问题原因

### 2.1 页面与复用关系

入口为 `Site -> Space -> More -> Trigger Zone`，由 `SpaceMoreViewController` 创建 `SpacePathTriggerZoneController`。

`SpacePathTriggerZoneController` 复用公共 `GroupPathSequenceDeviceAddView`，并对其三个子 View 分别启用 Space Trigger Zone 专用的双筛选布局：

- `GroupPathSequenceQuickAddView.configureSpaceTriggerZoneQuickAdd(...)`
- `GroupPathSequenceTriggerAddView.configureSpaceTriggerZoneFilterLayout(...)`
- `GroupPathSequenceManuallyAddView.configureSpaceTriggerZoneFilterLayout(...)`

公共子 View 也被 Group Path Sequence 和 Group Trigger Zone 使用，但后两者走默认配置，不启用 Space 的双筛选布局。

### 2.2 当前横向约束

三种添加模式的 Space 专用布局目前一致：

- Help 控件固定在左侧；
- `All eligible groups` 所在的 Group Filter 固定宽度为 186pt；
- Group Filter 与 filter widget 间隔 8pt；
- filter widget 固定宽度为 90pt；
- filter widget 右边仅使用“不超过右侧 16pt”的约束，而不是固定贴合右侧。

这会产生两个直接问题：

1. filter widget 的 90pt 外框过窄；
2. Group Filter 固定宽度、filter widget 又固定宽度，剩余空间不能自然分配。在不同屏宽下，filter widget 的右边距可能大于 16pt，窄屏还可能出现约束竞争。

### 2.3 `New only` 仍可能截断的原因

filter widget 当前内部为：

- 标题左边距 12pt；
- 下拉箭头宽度 16pt；
- 箭头右边距 12pt；
- 标题与箭头间距 12pt。

当外框宽度改为 100pt 后，标题实际可用宽度只有 48pt。当前 13pt Light 系统字体下，`New only` 的测量宽度约为 55pt，因此只修改外框宽度仍不足以稳定完整展示。

为同时满足 100pt 固定宽度和完整文案，Space Trigger Zone 紧凑筛选状态采用用户确认的内部间距：标题与箭头间距从 12pt 调整为 4pt，箭头右边距从 12pt 调整为 8pt。这样标题可用宽度为 60pt；默认 Group Path Sequence / Group Trigger Zone 布局继续保留原间距。

### 2.4 弹窗定位

filter widget 弹窗宽度在 iPhone 为 256pt、iPad 为 320pt。当前弹窗左上角横坐标按“filter widget 右边坐标减去弹窗宽度”计算，而 `TitleSelectView` 再以该点作为弹窗左边，因此数学上弹窗右边等于 filter widget 右边。

本次不需要修改公共 `TitleSelectView`。把 filter widget 固定到白色矩形内容卡片右侧 12pt 后，继续基于 filter widget 的实时 `frame.maxX` 计算弹窗锚点，弹窗会随控件一起移动并保持右边对齐。需要增加回归断言，防止以后改回基于父 View 或固定屏幕坐标定位。

## 3. 推荐约束方案

Space Trigger Zone 的三种添加模式统一使用以下横向关系：

1. Help 控件保留现有左边、尺寸和顶部约束；
2. filter widget 宽度固定为 100pt；
3. filter widget 右边与白色矩形内容卡片右边固定间隔 12pt；
4. Group Filter 左边仍与 Help 控件保持 6pt 间隔；
5. Group Filter 右边与 filter widget 左边保持 8pt 间隔；
6. 删除 Group Filter 的 186pt 固定宽度，让其由左右约束自然填充剩余空间；
7. Space 紧凑状态下，filter widget 标题与箭头间距调整为 4pt；
8. Space 紧凑状态下，filter widget 箭头右边距调整为 8pt，使 `New only` 获得 60pt 文本空间；
9. 弹窗继续使用 filter widget 右边作为定位基准，弹窗右边与控件右边严格对齐。

约束链完成后不再需要 filter widget 的左边约束：其位置由“固定宽度 + 固定右边距”确定；Group Filter 则由“固定左边 + 关联 filter widget 左边”自然确定宽度。这样不存在重复或相互竞争的横向约束。

## 4. 修改范围

### 4.1 运行代码

计划只修改以下三个文件中的 Space 专用布局分支：

- `SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`

不计划修改：

- `GroupPathSequenceDeviceAddView` 的高度、折叠、模式切换和数据逻辑；
- `SpacePathTriggerZoneController` 的筛选状态、设备列表或保存逻辑；
- 公共 `TitleSelectView`；
- 本地化 Key 和中英文文案；
- Group Path Sequence / Group Trigger Zone 的默认筛选布局；
- SDK、资源、依赖和 target 配置。

### 4.2 测试代码

扩展现有：

- `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`

采用先失败再修复的方式，为 Quick Add、Trigger Add、Manually Add 三种 Space 配置统一验证：

- filter widget 宽度为 100pt；
- filter widget 右边固定为 12pt，而不是 `lessThanOrEqual`；
- Group Filter 的右边关联 filter widget 左边并保留 8pt 间隔；
- Space 配置不再保留 Group Filter 的 186pt 固定宽度；
- Space 紧凑状态下标题与箭头间距为 4pt、箭头右边距为 8pt，`New only` 的文本可用宽度为 60pt；
- 弹窗横向锚点仍由 filter widget 的 `frame.maxX - menuWidth` 得出；
- 默认 Group Path / Group Trigger Zone 配置仍保持原来的全宽布局和右侧 16pt，防止扩大影响范围。

## 5. 验证计划

### 5.1 自动化验证

1. 运行 `GroupPathSequenceDeviceAddViewContractTests`，确认新增断言在修改前失败、修改后通过；
2. 运行 `git diff --check`；
3. 检查差异只包含三个子 View、对应 contract test 和实施文档；
4. 由于三个 View 同时加入多个 App target，使用真机 SDK、关闭签名分别构建：
   - SunSmart
   - Archipelago
   - SLG Sync Plus
   - SylSmart
   - Lumineux

构建通过只证明共享源码和各 target 编译兼容，不代替实际布局验收。

### 5.2 实际布局与交互验证

在真实页面 `Site -> Space -> More -> Trigger Zone` 验证，不使用 Simulator 代替最终验收：

1. 分别进入 Quick Add、Trigger Add、Manually Add；
2. 验证 `New only` 和 `Used` 都完整展示，filter widget 宽度均为 100pt；
3. 验证 filter widget 右边与白色矩形背景右边间隔为 12pt；
4. 点击 filter widget，验证弹窗右边与控件右边对齐；
5. 在弹窗中切换 `Ignore added devices` 与 `Show the devices added in other paths`，验证标题、选中态、设备过滤结果不回退；
6. 验证 `All eligible groups` 自然占用剩余空间，切换具体 Group 后布局不跳动；
7. 分别检查英文和简体中文；
8. 覆盖窄屏 iPhone、常规 iPhone 和 iPad 弹窗宽度。若 Group 名称超过剩余空间，允许单行尾部截断，但不得挤压 100pt filter widget、Help 控件或 8pt 间隔。

## 6. 风险与边界

- 三个子 View 的布局代码目前重复，必须三处同步修改；本次不额外抽取公共组件，避免扩大重构范围。
- Group Filter 改为弹性宽度后，极窄屏或超长 Group 名称可能发生尾部截断，这是固定 Help、固定 100pt filter widget 和固定间距下的合理降级；不能通过压缩 filter widget 规避。
- 本次只处理视觉布局和弹窗锚点，不改变 `showAddedDevices` 的业务语义、设备筛选结果、添加流程或保存同步。
- 源码 contract 和通用真机构建不能证明最终视觉间距，实际页面的中英文、三模式和弹窗交互检查仍是完成条件。

## 7. 已确认实施口径

按用户确认方案实施：三种添加模式统一调整；filter widget 固定 100pt、外部右边距固定 12pt；Group Filter 弹性填充；Space 紧凑状态下标题与箭头间距为 4pt、箭头右边距为 8pt；弹窗保持以 filter widget 右边为锚点；不修改公共弹窗、业务逻辑、本地化和默认 Group 页面布局。
