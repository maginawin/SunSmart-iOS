# Calibration mode 与 About 实现记录

## 1. 实现结果

已在共享的 `LightSensorCalibrationViewController` 中完成 `Calibration mode` 和 About 两个 Section，因此从 Daylight Group 页面提示入口和菜单 `Calibrate` 入口进入时均生效，入口代码本身未修改。

- 模式顺序为 `Night Cal.`、`Sensor Cal.`、`Plane Cal.`，默认选中最右侧 `Plane Cal.`。
- 模式切换仅切换对应的 About 标题和说明内容，不触发校准、传感器启停或 Mesh 消息。
- About 默认展开；展开/收起状态在三个模式间共享，切换模式不会重置状态。
- About 使用多行文本和 Auto Layout 自适应高度，展开时显示分隔线和向上箭头，收起时只保留 Header 并显示向下箭头。
- 已校准 Group 固定显示绿色状态点与 `Active: Plane Cal.`；未校准 Group 固定显示绿色状态点与 `Active: None`。
- Active 状态读取 Group 当前已落地的 Ambient Light Sensor 校准状态，不随当前浏览的模式变化。
- 原有 ON/OFF Calibration Point、Manual correction、底部 `CALIBRATION` 按钮文案与业务行为均未修改。

## 2. 文件范围

- 修改 Calibration 页面 Controller，在 Select daylight sensor 下方接入两个新 Section，并复用现有 Group 校准状态。
- 新增 Calibration Mode Selector 视图。
- 新增自适应 About 卡片视图。
- 同步新增 English 和简体中文用户可见文案。
- 两个新增 Swift 文件均加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
- 未修改 NordicSigMeshSDK、依赖、Auth、入口页面、资源文件或其他业务模块。

## 3. 自动验证结果

- `git diff --check`：通过。
- English 与简体中文 `Localizable.strings` 语法检查：通过。
- 四个品牌 target 的新增文件 Sources 归属检查：通过。
- `SunSmart` Debug iPhoneOS generic build：通过。
- `Archipelago` Debug iPhoneOS generic build：通过。
- `SLG Sync Plus` Debug iPhoneOS generic build：通过。
- `SylSmart` Debug iPhoneOS generic build：通过。

构建使用真机 SDK、关闭代码签名，未使用 Simulator。构建日志仍包含工程原有的资源重复或 AppIntents metadata 提示，不影响构建成功，也不是本次改动引入。

## 4. 待人工验收项

自动验证无法替代真机 UI 验收，仍需确认：

- English、简体中文及四品牌主题下的布局和文字换行。
- 三种模式切换时 About 文案、高度与滚动位置表现。
- About 展开/收起按钮、箭头和共享状态。
- 已校准与未校准 Group 的 Active 文案及绿色状态点。
- 校准或取消传感器后的 Active 状态刷新。
- 切换模式和折叠 About 时没有产生 BLE/Mesh 消息。
