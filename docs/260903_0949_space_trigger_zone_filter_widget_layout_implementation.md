# Space Trigger Zone Filter Widget 布局优化实施总结

## 实施结果

已按确认方案完成 `Site -> Space -> More -> Trigger Zone` 中 filter widget 的布局优化，并同步覆盖：

- Quick Add
- Trigger Add
- Manually Add

三种模式现在使用相同的 Space Trigger Zone 专用约束：

- filter widget 固定宽度 100pt；
- filter widget 右边与白色内容卡片右边固定间隔 12pt；
- `All eligible groups` 所在 Group Filter 取消 186pt 固定宽度，改为填充 Help 控件与 filter widget 之间的剩余空间；
- Group Filter 与 filter widget 间隔保持 8pt；
- filter widget 标题与箭头间距调整为 4pt；
- filter widget 箭头右边距调整为 8pt；
- `New only` 的理论文本区域由原来的 38pt 增加到 60pt；
- 弹窗继续按 filter widget 的实时右边坐标定位，因此弹窗右边与控件右边保持对齐。

默认 Group Path Sequence 和 Group Trigger Zone 布局未改变；默认配置会显式恢复标题与箭头 12pt、箭头右侧 12pt 的原始间距，避免 View 重新配置时继承 Space 专用样式。

## 修改文件

运行代码：

- `SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift`
- `SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift`

测试：

- `Tests/Group/GroupPathSequenceDeviceAddViewContractTests.swift`

文档：

- `docs/260903_0941_space_trigger_zone_filter_widget_layout_plan.md`
- `docs/260903_0949_space_trigger_zone_filter_widget_layout_implementation.md`

未修改业务筛选逻辑、设备添加流程、保存同步、公共 `TitleSelectView`、本地化、资源、依赖、SDK 或 target 配置。

## 测试结果

### Contract

先增加布局 contract，旧实现按预期失败于 Space Quick Add 的固定 Group Filter；完成三种模式修改后通过：

- `GroupPathSequenceDeviceAddViewContractTests layout passed`

Contract 覆盖：

- 三种模式的 100pt filter widget；
- 内容卡片右侧 12pt 固定间距；
- Group Filter 弹性宽度和 8pt 控件间距；
- 标题到箭头 4pt；
- 箭头到控件右边 8pt；
- 弹窗继续以 filter widget 右边定位；
- 默认配置重新应用时恢复原始 12pt 标题和箭头间距；
- 移除旧的 90pt 宽度和非固定右边约束。

### 静态检查

- `git diff --check`：通过。

### 多 target 真机 SDK 构建

使用 Debug、`iphoneos`、`generic/platform=iOS`、关闭签名进行构建，以下 scheme 全部成功：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart
- Lumineux

构建时远程 `NordicSigMeshSDK` 解析为 `release` 分支 revision `86f5ec9`；本次未修改 SDK。

## 实际布局验收边界

当前环境无法完成真机页面验收：

- `xcrun devicectl list devices` 因 CoreDeviceService 初始化超时失败；
- `xcrun xcdevice list` 只发现本机 Mac，没有可用 iOS 真机。

因此以下项目仍需在真实 iPhone / iPad 页面确认，不能由 contract 或通用构建替代：

1. Quick Add、Trigger Add、Manually Add 中 `New only` 和 `Used` 的实际显示；
2. filter widget 与白色内容卡片右边的视觉 12pt 间距；
3. 点击后的弹窗右边与 filter widget 右边视觉对齐；
4. 英文与简体中文显示；
5. 窄屏 iPhone 上 `All eligible groups` 或超长 Group 名称的尾部截断效果；
6. iPad 中 320pt 宽弹窗的位置。

源码约束、contract 和五个 target 构建均已完成；真机视觉与交互验收保持为独立待验证项。
