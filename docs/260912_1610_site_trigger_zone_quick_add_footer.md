# Site Trigger Zone Quick add 底部提示

## 实现

选中 Site Trigger Zone Item 后，在 Quick add 内容底部展示指定提示。根因为 `GroupPathSequenceQuickAddView.configureBrowse` 原先清空了共用底部标签。

- 复用 `path_quick_add_message`：英文为 `The intersection point is suitable for adding using the Tigger added mode`，简体中文为“交叉点适合使用触发添加模式添加”。保留用户指定英文拼写，不修改本地化资源。
- 沿用现有底部标签的 12pt light 字体、SubText_Color、居中样式及底部 6pt 间距；Site 浏览态允许多行换行。
- 首选高度同时考虑上方筛选提示、居中的 Start 控件或不可用状态消息、底部文案高度。Start 可见时约束其底部至少距提示 12pt；无可用 Space 时隐藏的 Start 不增加该约束。
- 切换 Trigger add / Manually add 或回到未选中 Item 的引导态时，提示随 Quick add 内容一起隐藏。
- 改动限定在 Site 候选浏览配置与对应高度分支；保留 Space 原有配置及文案。没有修改资源、target 配置、依赖、SDK 或添加行为。
- 工作区已有 Site 面板动画改动保留。

## 验证

- SunSmart：直接使用 xcodebuild，Debug / iphoneos / generic/platform=iOS / 关闭签名构建通过。
- `GroupPathSequenceDeviceAddViewContractTests`、`SpaceTriggerZoneFollowupContractTests` 通过；这些为静态契约检查，不代表实际布局测试。
- 在既有 `SiteTriggerZoneCandidateLayoutProbe` 中补充提示文案、样式、模式显隐、底部位置及与 Start / 空状态消息间距检查，沿用多种容器尺寸、各类候选状态和多行文字裁切检查。探针在独立 iPhoneOS 宿主编译通过，未运行。
- `git diff --check` 通过。

按项目约定，本轮未运行真机或 Simulator。**实际 UIKit 布局测试仍待执行，不能视为 UI 全部验收完成。** 后续需运行英文、简体中文布局探针，并检查选中 Item、切换模式、无可用 Space 及窄屏换行。

未提交或推送 Git。
