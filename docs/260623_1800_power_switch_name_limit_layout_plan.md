# Power Switch 名称长度与 Group 列表布局分析计划

## 背景

用户关注三类 Switch 名称与展示问题：

- AC Power Switch
- Battery Power Switch
- Kinetic Switch

目标需求：

- 新创建和 Edit 保存时，AC Power Switch、Battery Power Switch 名称最大长度限制为 32，与 Kinetic Switch 保持一致。
- 若输入超过 32，App 静默截取前 32 个字符，不弹错误提示。
- Group 页面右上角菜单选择 Switch，再选择 AC Power Switch 后，列表中的 AC Power Switch 名称过长时不能压到右侧 UISwitch。
- AC Power Switch 名称 Label 应单行显示，过长以省略号结尾。
- 名称 Label 右侧与 UISwitch 左侧间隔为 8。

## 当前代码事实

### 创建与 Edit 名称长度

- Battery/AC Power Switch 新建入口在 `DevicesViewController.addAction` 中，分别创建 `PJPreAddEightKeySwitchesVC`，creationKind 为 `.batteryPowerSwitch` 或 `.acPowerSwitch`。
- Battery/AC Edit 入口在主 Switch 列表长按后，如果能转换成 `PJEightKeySwitchData`，进入 `PJPreAddEightKeySwitchesVC(space:switchData:)`。
- `PJPreAddEightKeySwitchesVC.nameDidChange` 目前直接把 `UITextField.text` 写入 `viewModel.deviceName`。
- `PJPreAddEightKeySwitchesViewModel.buildSwitchData()` 目前直接把 `deviceName` 写入 `switchData.name`，未做长度截断。
- `validateEditorInput()` 只检查空名称与重名，未检查名称长度。
- Kinetic Switch 新建入口仍走旧 `DeviceSwitchViewController(space:switchData:nil)`。
- Kinetic Switch 旧 Edit 页 `DeviceSwitchHeaderView` 当前对名称超过 32 字符时会截断为 32，并显示 `text_length_exceeded` 提示；这与本次“32 且静默截取”的预期不一致。

结论：Battery/AC 当前没有 32 字符限制；Kinetic 有旧的 32 字符限制，但超长时会显示提示，行为与新需求不一致。

### Group 页面 AC Power Switch 列表布局

- Group 页面右上角 Switch 菜单在 `GroupViewController.pushToSwitch()` 中分流：
  - Kinetic -> `GroupSwitchsViewController`
  - Battery -> `GroupPowerSwitchesViewController(kind: .battery)`
  - AC -> `GroupPowerSwitchesViewController(kind: .ac)`
- AC/Battery Power Switch 列表 Header 使用 `GroupPowerSwitchHeaderView`。
- `GroupPowerSwitchHeaderView.titleLabel` 当前只设置 left/top 约束，没有设置 right 小于等于 `enableSwitch.snp.left - 8`。
- `titleLabel` 当前也没有显式设置 `numberOfLines = 1` 与 truncation。
- `detailLabel` 已有 `right <= enableSwitch.left - 12`，但本次问题出在名称 `titleLabel`。

结论：AC Power Switch 名称过长压到右侧 UISwitch 的问题真实存在；同一 Cell 也服务 Battery Power Switch，所以建议一并覆盖 Battery/AC。

## 方案选项

### 方案 A：最小共享修复，推荐

名称长度：

- 在 8-key 新编辑流中新增一个共享的名称归一化点，例如在 `PJPreAddEightKeySwitchesViewModel.buildSwitchData()` 保存到 `switchData.name` 前截断为 32。
- 在 `PJPreAddEightKeySwitchesVC.nameDidChange` 中也同步把超过 32 的 textField 文本静默截断，保证 UI、viewModel、保存数据一致。
- 在旧 Kinetic `DeviceSwitchHeaderView` / `DeviceSwitchViewController` 路径保留 32 字符限制，并取消超长提示，只静默截断。

Group 布局：

- 在 `GroupPowerSwitchHeaderView.titleLabel` 设置：
  - `numberOfLines = 1`
  - `lineBreakMode = .byTruncatingTail`
  - right 小于等于 `enableSwitch.snp.left`，offset 为 `-SCRXFrom(8)`
- 给 `enableSwitch` 设置较高 hugging / compression resistance，避免 Switch 被名称挤压。

优点：

- 改动点少，集中在实际入口和实际 Cell。
- 覆盖 Battery/AC 新建、Battery/AC Edit、Kinetic 新建/Edit，以及 Group AC/Battery 列表显示。
- 不改变数据库结构、云同步结构、导入导出结构。

风险：

- 旧 Kinetic 原本 32 字符提示会变成 32 静默截断，属于产品行为变更。

### 方案 B：保存层统一兜底

- 在 `DeviceSwitchData.save()` 或更底层 persistence 前统一截断 `name`。
- UI 输入层也做截断，避免保存后 UI 与数据不一致。

优点：

- 更不容易漏掉未来入口。

风险：

- 影响面更大，可能触及非本需求的 switch 导入、分享、迁移或后台写入路径。
- 与“保持改动聚焦”不完全匹配。

### 方案 C：只改本次报错页面

- 只修 `GroupPowerSwitchHeaderView` 的标题压缩。
- Battery/AC/Kinetic 名称长度暂不处理。

优点：

- 改动最小。

风险：

- 不满足用户提出的名称长度限制建议。
- 长名称仍可能继续进入本地数据和同步数据。

## 推荐方案

推荐采用方案 A。

原因：

- 当前问题有两个真实根因：Battery/AC 输入/保存缺少 32 限制，以及 GroupPowerSwitchHeaderView 名称缺少右侧约束。
- 方案 A 覆盖需求中的三类 Switch，又不会扩大到数据库层或导入导出层。
- 对 Group 列表布局的修复落在共享 AC/Battery Cell，可以同时避免 Battery Power Switch 以后出现同类 UI 问题。

## 开发计划

1. 新增或复用一个小型名称截断工具，常量为 32，供 8-key 新编辑流与旧 Kinetic 编辑流使用。
2. 修改 `PJPreAddEightKeySwitchesVC.nameDidChange`，用户输入超过 32 时静默截断 UI 文本并同步 `viewModel.deviceName`。
3. 修改 `PJPreAddEightKeySwitchesViewModel.buildSwitchData()`，保存前再次截断，作为 Battery/AC 新建与 Edit 的兜底。
4. 修改旧 Kinetic `DeviceSwitchHeaderView` / `DeviceSwitchViewController` 的 32 字符逻辑为静默截断，不再展示超长提示。
5. 修改 `GroupPowerSwitchHeaderView.titleLabel` 的单行、省略号、right <= UISwitch left - 8 约束，并给 `enableSwitch` 设置布局优先级。
6. 自查是否存在与该 Cell 共享的 Battery Power Switch 展示入口，确认同步受益且不破坏展开/使能交互。
7. 验证：
   - `git diff --check`
   - iPhoneOS 构建：`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 已确认点

- 采用方案 A。
- AC Power Switch、Battery Power Switch 的名称长度限制为 32，与 Kinetic Switch 相同。
