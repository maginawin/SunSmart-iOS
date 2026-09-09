# Site Trigger Zone Item 组件实现与验收记录

日期：2026-09-09。状态：代码及自动检查完成，真机布局与交互待验收。依据：[已确认的开发方案](260909_1623_site_trigger_zone_item_component_plan.md)。

## 已实现

- 新增 Site 专用展示模型、非空卡片、Space 分区、设备网格和表头；真实/模拟模式共用展示规则。
- 保留原有 No Data Cell 及表头分支：72pt 内容高度、40pt 表头、圆角、文本、未选中/黄色选中边框维持现状。
- 有 N 个 Space 显示 N−1 条分隔线；仅一个 Space 不显示线。设备网格按实际容器宽度换行，Space 数量不限制为四个。
- 卡片高度由完整约束与设备行数决定，宽度变化时重新计算；窄窗口可将设备数量或操作组移到下一行。
- 所有设备固定采用现有灰色设备图形并统一染色，不绑定 Node.state，不识别、删除或控制设备。
- 只有完整成员清单中所有 Space 均有有效 Owner/Editor 授权才允许编辑；Visitor、No access、未知权限或待验证状态使整个 Zone 只读。
- 只读 Zone 无论是否选中均显示 View only；每个 Space 均带锁，包括其中的 Owner/Editor。选中只读 Zone 隐藏添加面板并清除其目标编号。
- No access 保留已公开的名称与数量，设备区域显示受限提示；未知数量不显示为 0，未知信息不伪装成 No Data。
- 待同步图标按 Space 的任务显示；无法归属 Space 的 Zone 元数据任务显示在 Zone 标题。同步类型在展示模型和辅助朗读中区分 Cloud、Device、Both，未复用带“点击重试”的页面云同步文案。
- 四按钮顺序为 Test、Reset、Delete、Save。根据后续间距修复要求，标题区固定为 40 pt，名称、按钮位置与尺寸均对齐 No Data；采用其 SCRXFrom/SCRYFrom 尺寸适配，取消原 44 pt 按钮撑高表头和窄屏换行。品牌按钮文字继续使用 Bar_Color。

## Debug 预览使用

右上角保留 +，新增 Test。首次进入是真实模式；点击 Test 切入 29 个固定模拟场景，再次点击返回真实数据。Release 不提供预览入口。

预览时显示 Preview mode 提示，默认选中 D02；每个卡片下方标注场景编号、权限组合及是否需要同步，便于对照原方案。点击卡片、标题或设备区可以切换选中项。

可编辑非空卡片的四按钮只给出预览提示，不修改模拟成员、不清除同步状态、不调用真实增删/保存、数据库、网络或 Mesh。+ 在预览模式禁用，真实重试控件不接受点击；空卡片 Test/Reset 继续禁用。

切换时分别管理真实和模拟选择，保存并恢复真实滚动位置及添加面板展开状态。真实异步同步结果仍归入真实状态，不覆盖模拟列表或显示成功 HUD；切回时重新读取最新真实数据，已删除的真实选择不会恢复。

## 数据和业务边界

真实模式仍支持已有空成员 Zone。非空 members/未知 schema 的原有保护保留，未改变 extensionData 格式、云端保存流程或按 zoneId 保存的范围。

模拟数据仅创建展示快照，不创建 SpaceData、Node 或 Auth 信息；No access 不依赖导入一个假的 Visitor Space。跨 Space 相同设备地址通过 Space ID 与设备 ID 组合区分。

本期未实现真实非空成员解析、服务端权限摘要接口、跨 Space 设备同步、Test/Reset 的 Mesh 功能。这些仍按已确认方案留到后续功能期。

## 文件与资源

| 文件 | 内容 |
| --- | --- |
| SiteTriggerZoneItemModel.swift | 展示模型、权限/同步派生规则、模式与选择状态 |
| SiteTriggerZonePreviewFixtures.swift | Debug 下 29 个基础场景，包含 0/1/2/3/4 Space 与长名称等边界 |
| SiteTriggerZoneItemCell.swift | 卡片、权限 badge、Space 分区、设备网格 |
| SiteTriggerZoneItemHeaderView.swift | 非空表头、View only、同步图标、四操作按钮 |
| SiteTriggerZoneContentView.swift | 一次性快照刷新、旧空项与新非空项路由、动态高度和面板显示 |
| SiteTriggerZoneViewController.swift | Debug Test 切换、操作隔离、真实状态恢复 |
| GroupPathSequenceDeviceAddView.swift | 仅增加只读 isCollapsed，用于恢复面板状态；未更改共享行为 |
| Assets.xcassets/SiteTriggerZone | 从 Figma 导出的锁、同步、眼睛 SVG；Space 分隔线由代码绘制 |
| en/zh-Hans Localizable.strings | 新增 16 个对应的中英文 Key |
| Tests/Site/SiteTriggerZoneItemPolicyTests.swift | 状态、完整性、角色组合、摘要、同步和模式隔离测试 |
| Tests/UI/SiteTriggerZoneItemLayoutProbe.swift | 用生产视图在设备测试宿主执行的布局检查，不加入发布 target |

四个新增生产 Swift 文件已各加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 的 Sources 一次。共享资源与中英文本地化已检查，未修改 SDK 或依赖。

Figma 来源为已确认方案中的六个节点；此次另读取 615:4623 的 design context，并下载其锁/同步/眼睛导出资源。设备继续复用已有 path_device_offline 和尺寸常量。

### 分隔线优化（2026-09-09）

按用户要求，移除 `site_zone_divider` 图片资源，改为 Site 专用 UIView 的 CAShapeLayer 绘制。保留原设计的 `#CAD5E3`、1 pt 线宽、2 pt 实线与 2 pt 间隔，随布局宽度更新路径。Space 间仍保留上下各 16 pt 间距，N 个 Space 只显示 N−1 条线，单 Space 不显示线。真机布局验收仍待执行。

本次优化后重新执行五品牌 Debug generic iPhoneOS 构建，全部通过；源码、工程、测试及脚本中无 `site_zone_divider` 引用，`git diff --check` 通过。下表 Release 与策略测试记录来自此次分隔线优化之前。

## 验证记录

| 检查 | 结果 |
| --- | --- |
| 原 Site Trigger Zone 数据测试 | 通过：100 Zone、身份、兼容、pending、冲突和重启恢复 |
| 新 Item 策略测试 | 通过：29 场景、全部双 Space 角色组合、清单完整性、受限摘要、同步归属、模式隔离 |
| 五个品牌 Sources membership | 通过：四个新源文件各一次 |
| 中英文本地化 / SVG 资源清单 / project.pbxproj | 检查通过 |
| 五品牌 Debug generic iPhoneOS 构建 | 最终代码全部通过：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux |
| SunSmart Release generic iPhoneOS 构建 | 通过 |
| Debug/Release 产物检查 | Debug 包含预览入口和 fixture 标记；Release 二进制中均不存在 |
| UIKit 布局探针 | 最终版本已通过针对实际 SunSmart 模块的类型检查；真机运行未执行 |
| 真机交互、旋转、iPad 可变窗口与截图 | 尚未收到设备选择回复，未安装或运行测试 App；此项未完成 |

`git diff --check` 通过；所有改动保留在工作区，未提交 Git。

构建均直接运行 xcodebuild，使用 iphoneos、generic/platform=iOS 和 CODE_SIGNING_ALLOWED=NO；没有使用 Simulator。编译与状态测试不代替实际布局、真实服务端或 Mesh 验收。

## 真机验收路径

1. 以 Debug 打开 Site → Trigger Zone；核对真实 No Data 的两种状态以及现有新增、删除、Save。
2. 点击导航 Test，核对 Preview mode、+ 禁用、D02 默认选择；点击四按钮只出现预览提示。
3. 点击 D04/D05/T05/Q02/Q04，核对所有分区保留、View only、全 Space 锁、受限消息、同步图标与面板隐藏。
4. 点击 S01、D03、Q03，检查单 Space 无线、7/11 设备换行、四 Space 的三条线和完整卡片高度。
5. 查看 B01–B05，检查 Zone 级同步、未知/待验证权限、未知数量、长名称及同名 Space。
6. 中英文分别检查 iPhone 窄屏/标准宽度/横屏和 iPad 宽度变化；滚动复用时反复切换 1/4 Space、只读/可编辑、选中/未选中。
7. 再次点击 Test，确认回到最新真实列表、原选择及面板状态，真实数据库没有模拟 Zone；在真实同步返回期间重复切换。

布局探针覆盖 288、351、398、736、480、320pt 等容器宽度、全部非空场景两种选择状态、重复复用、图标存在性、标签边界、受限设备隐藏、与 No Data 对比名称及按钮坐标、选择前后间距、面板切换和 100 个真实空项。它需要设备测试宿主运行，当前不能将此清单表述为已通过。
