# Site Trigger Zone 面板底部间距优化实施记录

依据[已确认方案](260912_1614_site_trigger_zone_panel_spacing_plan.md)实施。

## 改动结果

生产代码仅修改 `SunSmart/Main/Site/TriggerZone/SiteTriggerZoneContentView.swift`。

- 面板底部由“安全区底部再上移 16pt”，改为距当前容器底部 `max(safeAreaInsets.bottom, SCRYFrom(16))`，与 Space Trigger Zone 的间距规则一致。
- 常见底部安全区 34pt 的全面屏场景中，外部底部空白从 50pt 减少到 34pt。无底部安全区时沿用 Space 的缩放最小边距。
- 使用当前容器安全区；在安全区变化及布局时更新约束，适应容器与窗口安全区不一致的情况。
- 展开与收起使用同一底部约束，保留现有高度动画和列表与面板之间的 8pt 间距。

共用面板的标题栏、模式栏、内容卡片及 Quick add 页脚底部间距本来已一致，未改动。常规选中、单行设备、内容可容纳时继续使用 290pt 首选展开高度；Site 窄屏长文案和 Manual 多行展开继续按需增高。当前没有运行中的证据表明需进一步修改内部高度算法，因此保留其避让逻辑，等待实际对照验收后判断。

没有修改文案、本地化、资源、target 配置、依赖、SDK、权限、候选筛选或设备操作行为。没有创建 Git commit 或推送。

## 约束核对

检查了状态区域 → 列表 → 面板 → 容器底部的纵向约束。面板首选高度优先级仍为 750，列表最小高度仍为 60pt；标题栏和模式栏各 44pt，内容卡片上、下间距各 8pt，Quick add 页脚距内容底部 6pt。

底部空间减少后，释放的空间由上方列表获得，不直接改变面板自身高度。极短容器下的压缩风险需要实际布局探针检查，未据源码检查宣称不存在运行时裁切。

## 布局探针

扩展 `Tests/UI/SiteTriggerZoneCandidateLayoutProbe.swift`：

- 使用真实子 UIViewController 承载 Site ContentView，通过 `additionalSafeAreaInsets.bottom` 的 0 → 34 → 20 → 0 变化检查安全区传播与底部更新。
- 配置另一份共用生产面板，采用 Space 已选 Zone 的三模式配置，测量常规 290pt 高度与内容底部间距；保存 Space 参考面板图片。
- 检查各模式、各候选状态和 Manual 行数下，面板高度是否被压缩或额外增加，列表与面板是否保持 8pt 间距。
- 检查收起后高度 44pt，底边位置符合展开时的同一规则。
- 继续沿用英文/简体中文、多种容器尺寸、空状态、长文字、页脚遮挡和菜单检查。

这是共用面板的 Space 配置对照，不等同于运行完整 Space 控制器。设备上仍需对两个实际入口作视觉比较。

## 已执行验证

- `GroupPathSequenceDeviceAddViewContractTests`：通过。
- `SpaceTriggerZoneFollowupContractTests`：通过。
- 最终版本布局探针的独立 iPhoneOS 宿主：构建通过，未运行。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux：generic iPhoneOS Debug 无签名构建全部通过。
- `git diff --check`：通过。

通过解析工程确认上述五个品牌均引用本次修改的生产文件。构建直接运行 `xcodebuild -workspace SunSmart.xcworkspace` 并指定对应 scheme、Debug、iphoneos、generic/platform=iOS 和关闭签名，没有使用 shell 包装或重定向日志。构建输出含既有工程警告，如缺少 AppIntents 依赖时跳过元数据提取，未扩展范围处理。

## 实际 UI 验收待执行

遵循用户不使用 Simulator、默认不由 Codex 做真机测试的约定，本轮没有安装或启动设备 App。**当前为生产修改与构建检查完成、实际 UIKit 布局验收待执行，不能视为 UI 全部完成。**

用户可在 Xcode 打开 `/tmp/SiteZoneCandidateValidation/SunSmart.xcworkspace`，选择 SunSmart scheme 和设备，分别以英文、简体中文设置运行：

- 启动参数 `candidate-layout-probe`：执行尺寸、间距、候选布局及交互探针，查看 `candidate-layout-probe-result` 的 PASS 或失败信息。
- 启动参数 `candidate-animation-probe`：执行选中、收起展开、反向动画、Manual 行数变化检查。
- 同时在正常 App 对比 Site → Trigger Zone 与 Site → Space → More → Trigger Zone 的面板底部位置、常规高度及长文案显示。

临时宿主直接引用生产文件与仓库探针，本轮没有修改其工程配置。
