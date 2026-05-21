# Scene Settings Group CCT Picker Design

## 背景

在 `Site - Space - Scene` 分类下，长按 Scene 进入 Scene 页面后，通过右上角 Settings 进入 `Scene Settings` 页面。当前页面长按 Group 时会打开场景参数弹窗，但弹窗固定展示亮度与色温，不会根据 Group 是否支持 CCT 调整内容。

现有代码入口如下：

- `SceneSettingsViewController.collectionLongPressAction(sender:)` 负责长按识别。
- `SceneSettingsViewController.updateGroupSceneExecuteData(group:)` 负责打开参数弹窗并保存编辑结果。
- `SceneExecuteDataPickerView` 是当前复用的场景参数弹窗，固定包含亮度 slider 和 CCT slider。
- `Group.effectiveSupportCct` 已存在，表示组内是否存在有效支持 CCT 的设备。

当前 App 在 `Scene Settings` 页面没有现成的“仅亮度”弹窗；Scene 创建页也复用同一个固定展示亮度和色温的弹窗。

## 目标

`Scene Settings` 页面长按 Group 时，按 `group.effectiveSupportCct` 展示弹窗内容：

- 支持 CCT：弹窗展示亮度和色温。
- 不支持 CCT：弹窗仅展示亮度。

## 非目标

- 不调整 Scene 创建页的数据编辑行为。
- 不改动 Scene 数据模型，`ExecuteSceneData` 仍保留 `lightness` 和 `cct`。
- 不改变预览、同步、场景发送消息的现有拆分逻辑。
- 不新增一套独立弹窗样式。

## 推荐方案

扩展现有 `SceneExecuteDataPickerView`，新增是否展示 CCT 的配置参数，并保持默认展示 CCT，以保证已有调用兼容。

`SceneSettingsViewController.updateGroupSceneExecuteData(group:)` 调用弹窗时传入 `group.effectiveSupportCct`：

- `true` 时保持现有 UI 和行为。
- `false` 时隐藏 CCT label 与 CCT slider，弹窗高度收缩到仅亮度内容。

确认或点击遮罩关闭时仍使用现有 `(lightness, cct)` 回调签名。仅亮度模式下，`cct` 使用弹窗初始化传入的原值或默认值，避免引入可选值和额外模型变更。

## 数据流

1. 用户在 `Scene Settings` 页面长按 Group。
2. 控制器读取当前 Group 的 `executeSceneData`、亮度限制范围和 `effectiveCctRange`。
3. 控制器按 `group.effectiveSupportCct` 打开弹窗。
4. 用户调整亮度；支持 CCT 时也可调整色温。
5. 回调保存到当前 Group 的 `executeSceneData`：
   - 支持 CCT 时保存用户选择的亮度和色温。
   - 不支持 CCT 时保存用户选择的亮度，CCT 值沿用初始化值。
6. 刷新当前 Group cell。

## 边界行为

- 空组、离线组、未连接 Mesh、应急场景阻止控制等校验保持现状。
- 混合组只要存在一个有效 CCT 设备，即 `effectiveSupportCct == true`，弹窗展示亮度和色温。
- 不支持 CCT 的 Group 不展示色温控件，但底层数据仍保留 CCT 字段用于兼容现有逻辑。

## 验证计划

- 静态检查 `SceneExecuteDataPickerView.show(...)` 调用点，确认默认参数不影响 Scene 创建页。
- 检查 `Scene Settings` 长按 Group 调用点，确认使用 `group.effectiveSupportCct` 控制 CCT 展示。
- 构建验证：
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

