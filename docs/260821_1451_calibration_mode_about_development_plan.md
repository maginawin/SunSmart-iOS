# Calibration mode 与 About 开发分析和计划

## 1. 结论

需求整体完整、合理，可以在不改动现有校准业务流程、底部按钮文案和两个 Calibration Point 区域的前提下实现。

本次应只修改共享的 `LightSensorCalibrationViewController` 页面及其新增的局部 UIKit 视图、英文/简体中文本地化。Daylight Group 页的提示按钮与菜单项最终都直接创建同一个 `LightSensorCalibrationViewController(group:)`，因此不需要改入口。

建议将本次新增能力定义为“校准模式说明选择器”，而不是新的校准模式业务能力：

- 默认选中 `Plane Cal.`。
- 切换 `Plane Cal.`、`Sensor Cal.`、`Night Cal.` 时，只更新 About 卡片内容。
- `Sensor Cal.` 和 `Night Cal.` 当前不触发协议命令，不改变现有 ON/OFF 输入、Manual correction 或底部 `CALIBRATION` 按钮行为。
- 右侧 `Active` 表示 Group 当前已经生效的校准模式，与用户当前浏览的说明模式相互独立。
- About 默认展开；展开状态由一份页面内状态维护，切换模式时保持不变。
- 每次重新进入页面仍默认 `Plane Cal.` 且 About 展开，不持久化 UI 选择或折叠状态。

## 2. 已核对的现状

### 2.1 页面与入口

- Group 菜单中的 `Calibrate` 调用 `calibrate()`，创建 `LightSensorCalibrationViewController(group:)`。
- Group 未校准提示区的 `CALIBRATE` 按钮调用 `calibrateBtnAction()`，创建同一个 Controller。
- 因而只更新该 Controller 就能覆盖两个入口，入口本身无需更新。

### 2.2 当前页面布局

当前 `setupUI()` 的纵向顺序是：

1. `LightSensorCalibrationSelectView`
2. ON Calibration Point
3. OFF Calibration Point
4. Manual correction
5. 固定底部 `CALIBRATION` 按钮

目标顺序应调整为：

1. `Select daylight sensor`
2. `Calibration mode`
3. About 卡片
4. ON Calibration Point
5. OFF Calibration Point
6. Manual correction
7. 固定底部按钮（保持原文案和行为）

只重接新增区域附近的约束，不重构整个页面，不调整既有 Calibration Point、Manual correction、底部按钮或导航栏。

### 2.3 Group 校准状态来源

现有 Group 页面将 `group.info.ambientLightSensorNode != nil && group.info.ambientLightSensorNode.sensorCalibrated` 视为已校准；`sensorCalibrated` 同时兼容旧版 `daylightCalibrationValue` 和新版 `sensorCalibrationData.isCalibration`。

建议新 UI 复用同一判定，避免同一个 Group 在 Group 页显示“已校准”，进入 Calibration 页却显示 `Active: None`。

状态映射：

| Group 状态 | Active 文案 | 状态点 |
| --- | --- | --- |
| 已校准 | `Active: Plane Cal.` | 绿色 |
| 未校准 | `Active: None` | 绿色 |

Active 状态需要在以下时机刷新：页面首次加载、成功启用已有校准传感器、校准并启用成功、成功取消/替换当前传感器。刷新应跟随已经落到 Group 的状态，不提前跟随正在 loading 的临时选择。

## 3. Figma 设计提取结果

### 3.1 Calibration Mode Selector

来源：节点 `519:15519`。

- 内容宽度 343 pt，与现有页面左右各 16 pt 的内容宽度一致。
- 标题行约 30 pt 高，左侧 `Calibration mode`，右侧状态组。
- 状态组由 6 pt 圆点、`Active:` 和状态值组成；已校准示例值为 `Plane Cal.`。
- 标题行与选择器间距 8 pt。
- 选择器高 36 pt、圆角 10 pt、内边距 2 pt；选中项圆角 8 pt。
- Figma 排列顺序是 `Night Cal.`、`Sensor Cal.`、`Plane Cal.`，默认选中最右侧 `Plane Cal.`。
- 选中项使用主题色和白字；未选中项使用辅助文字色。

实现时建议使用 UIKit 原生 `UISegmentedControl`，配置项目主题色 `Bar_Color`、现有文字颜色和字体，不新增第三方控件。这样可以保留点击、VoiceOver、RTL 和选中状态语义。四品牌 target 会自动使用各自的 `Bar_Color`；SunSmart 下即匹配 Figma 的 `#6667AB`。

### 3.2 About 卡片

来源：

- Plane 展开态：节点 `519:15519` 内 `Info Card / Plane Calibration`
- Sensor 展开态：节点 `519:17793`
- Night 展开态：节点 `530:17816`
- 折叠态：节点 `530:17839`

共同结构：

- 与 Mode Selector 间距 16 pt。
- 背景 `#F0F4FF`，圆角 16 pt。
- Header 水平内边距 16 pt、垂直内边距 12 pt；标题 14 pt。
- 右侧为 30 × 30 pt 点击区域：展开时上箭头，折叠时下箭头。
- 展开时 Header 下方有 `#DDE3F5` 分隔线。
- Body 水平内边距 16 pt，上 12 pt、下 14 pt。
- 主说明 12 pt；`Best for:`、`Avoid if:` 及其内容为 11 pt；各段按 Figma 间距排列。
- 所有正文 Label 使用多行和 Auto Layout 自适应，不写死卡片展开高度。折叠时只保留 Header 高度。
- 整个 Header 都应可点击，不把交互限制在小箭头图标上；箭头图片复用现有 `arrow_up` / `arrow_down` 资源。

About 内容严格采用 Figma 文案：

| 模式 | 标题 | 主说明摘要 | Best for 摘要 | Avoid if 摘要 |
| --- | --- | --- | --- | --- |
| Plane | `About Plane Cal.` | 维持工作平面照度，传感器需检测到受控灯具的反射光 | 中等安装高度的教室、办公室 | 高位安装、位置不当或调光对读数影响很小 |
| Sensor | `About Sensor Cal.` | 保存设备位置处环境光与灯具光合成的传感器读数 | 户外路灯或传感器无法检测反射光的高棚仓库 | 明亮日光下校准可能导致夜间灯具接近满亮 |
| Night | `About Night Cal.` | 在选定亮度保存仅灯具贡献的读数，排除环境光 | 能可靠检测自身灯具反射光的低至中等层高室内空间 | 安装过高、位置错误或户外场景 |

## 4. 需求完整性与确认结果

### 4.1 已经明确的规则

- 只增加 `Calibration mode` 和 About 两个区域。
- 默认选择 `Plane Cal.`。
- 三个选项分别切换对应 About 内容。
- About 默认展开，并在三个模式间共享展开/折叠状态。
- About 高度随当前本地化文字自适应。
- 当前只实现 Plane 的业务校准；Sensor/Night 为说明切换，不增加协议功能。
- 已校准固定显示 `Active: Plane Cal.`，未校准固定显示 `Active: None`。
- 底部按钮文案和行为不更新。

### 4.2 已确认的两个视觉细节

1. 模式顺序严格跟随 Figma，使用 `Night Cal.` → `Sensor Cal.` → `Plane Cal.`，默认选中最右侧 Plane。
2. 未校准状态显示 `Active: None`，同时仍然显示绿色状态点。

以上两项已经确认，开发时按此实现，不再扩大需求。

## 5. 开发方案

### 阶段 1：新增局部展示模型和视图

- 新增一个页面内使用的 `CalibrationMode` 枚举，封装三个模式、显示名和 About 本地化 Key，避免使用易错的整数索引与平行字符串数组。
- 新增 `LightSensorCalibrationModeView`：负责标题、Active 状态和三段选择器。
- 新增 `LightSensorCalibrationAboutView`：负责标题、箭头、分隔线、三段文本和动态高度。
- 两个视图只暴露模式切换、展开切换和 Active 状态配置，不持有 Group、Node 或 Mesh 业务对象。

### 阶段 2：接入现有 Calibration 页面

- 在 `sensorSelectView` 下方按 16 pt 间距插入 Mode View。
- 在 Mode View 下方按 16 pt 间距插入 About View。
- 将 ON Point 顶部约束从 `sensorSelectView.bottom` 改接到 About View 底部。
- 保持 OFF Point、Manual correction 和底部按钮的现有相互关系与文案不变。
- Controller 初始化为 Plane + 展开。
- 模式切换只配置 About 内容，不调用现有 `calibrationBtnAction()`、`sensorEnabled()`、`sensorDisable()` 或 SDK。
- 折叠切换只更新 About Body 可见性、箭头、分隔线和布局；页面滚动内容高度由 Auto Layout 自动重算。

### 阶段 3：接入 Active 状态生命周期

- 新增统一的 `updateActiveCalibrationMode()`，使用 Group 页既有的“当前 Ambient Light Sensor 存在且 `sensorCalibrated`”规则。
- 在首次加载，以及现有传感器启用、校准成功启用、取消选择成功等 Group 状态已确定的回调后刷新。
- 不根据 segmented control 当前选择更新 Active；用户浏览 `Sensor Cal.` 或 `Night Cal.` 说明时，已校准 Group 仍显示 `Active: Plane Cal.`。

### 阶段 4：国际化与四 target 同步

- 在 `SunSmart/en.lproj/Localizable.strings` 与 `SunSmart/zh-Hans.lproj/Localizable.strings` 同步新增所有用户可见文本。
- 英文严格使用 Figma 文案与标点；简体中文提供完整对应翻译。
- `Localizable.strings` 已被四个 target 共用；新增 Swift 视图文件需加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 Sources 阶段。
- 不新增或修改 Auth、依赖、SDK、本地化语言集合、资源主题或现有 target 配置。

## 6. 预计修改范围

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
- `SunSmart/Main/Group/View/LightSensorCalibrationModeView.swift`（新增）
- `SunSmart/Main/Group/View/LightSensorCalibrationAboutView.swift`（新增）
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `SunSmart.xcodeproj/project.pbxproj`（仅新增两个文件并加入四个 target）

不会修改：

- Group 页两个入口及菜单文案
- 现有 ON/OFF Calibration Point 内容与逻辑
- Manual correction 行为
- 底部按钮文案与校准动作
- NordicSigMeshSDK 或任何 Mesh 协议流程
- 其他页面、资源或依赖

## 7. 验证计划

### 7.1 静态与布局验证

- 检查英文和简体中文 `.strings` 语法、Key 完整性及重复 Key。
- 检查新文件均属于四个品牌 target。
- `git diff --check`。
- 以长文本为重点检查 About 展开高度、折叠高度、滚动内容高度以及无约束冲突。

### 7.2 状态回归矩阵

| 场景 | 期望 |
| --- | --- |
| 未校准 Group 首次进入 | Plane 默认选中；About 展开；`Active: None` |
| 已校准 Group 首次进入 | Plane 默认选中；About 展开；`Active: Plane Cal.` |
| Plane → Sensor → Night | About 标题和三段正文对应切换；Active 不变 |
| 展开后切换模式 | 新模式保持展开且高度自适应 |
| 折叠后切换模式 | 新模式保持折叠，只显示对应标题与向下箭头 |
| 页面退出后重进 | 重置为 Plane + 展开 |
| 成功校准并启用 | Active 刷新为 Plane |
| 成功取消当前传感器 | Active 刷新为 None |
| 切换失败或校准失败 | Active 不提前改变，现有错误流程不变 |
| 中文环境 | 无截断、无英文硬编码、About 高度正确 |

### 7.3 构建验证

按项目规则使用 iPhoneOS generic destination、禁用签名并串行构建：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

构建只能证明编译和资源集成；最终仍需真机确认滚动、点击区域、动态高度、状态刷新和四品牌实际视觉效果。本次不需要 BLE/Mesh 协议新增验证，但应回归确认模式切换和 About 折叠不会触发任何 Mesh 消息。

## 8. 风险控制

- 最大风险是把“当前浏览的模式”误当成“当前 Active 模式”；两者必须分离。
- Active 必须读取 Group 已落地状态，不能使用 `selectSensor` 的临时 loading 状态，否则传感器切换失败时会显示错误结果。
- About 不应使用固定展开高度，否则英文、中文和较小屏幕会截断。
- 新文件若漏加任一 target，会出现部分品牌无法编译；需要同时检查四个 Sources 阶段。
- 只复用现有箭头和颜色体系，不下载 Figma 临时资源，不新增无关资产。
