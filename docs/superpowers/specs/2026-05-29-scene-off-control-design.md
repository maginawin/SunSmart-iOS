# Scene OFF Control Design

## 背景

在 `Site - Space - Scene` 中长按 Scene 进入 Scene 页面后，通过右上角菜单进入 Scene Settings 页面。当前页面长按 Group 会展示场景控制弹窗，弹窗已有亮度和色温控制，但没有明确的 OFF 控件。

这次功能需要在该控制弹窗增加 OFF 按钮，并让 Scene Settings、创建场景、添加设备到已关联场景的组、恢复设备、手动同步等场景同步入口都遵守同一套 OFF 语义。

现有相关代码入口：

- `SceneExecuteDataPickerView`：Scene 参数控制弹窗，创建场景和 Scene Settings 复用。
- `SceneSettingsViewController.updateGroupSceneExecuteData(group:)`：Scene Settings 长按 Group 后编辑场景参数。
- `SceneSettingsViewController.previewBtnAction(sender:)`：Scene Settings Preview。
- `SceneAddViewController.previewBtnAction()`：创建场景 Preview。
- `SceneAddViewController.addSceneHandle()`、`SceneSettingsViewController.saveAction()`、`doneAction()`：保存 Group 场景数据。
- `Scene.getSyncMessageHandles(node:data:)`：Scene 同步消息统一生成入口。
- `NodeSyncData.syncScenes`：添加设备入组、设备恢复、手动同步等流程复用的场景同步数据入口。
- `DeviceOperationType.configuration(.scene)`：Sync device(s) 场景同步成功判断入口。

## 已确认方案

采用方案 A：OFF 不新增字段，使用现有 `SceneExecuteData.isOn` 表达 OFF，同时保持 `lightness = 0`。

原因：

- `SceneExecuteData` 当前已经有 `isOn` 字段，使用它不会新增数据库字段，也不需要迁移。
- OFF 与亮度 0% 保持一致，UI、Preview、SAVE、Sync 状态判断都可以统一。
- 不引入新的 `isOff` 字段，避免历史数据、导入导出和同步比较出现双状态不一致。

## UI 设计

Figma 参考：

- Scene settings show control alert page: `ffZ6mSpXLtHi3e7YdEmvMl / 69:4224`
- control alert default: `ffZ6mSpXLtHi3e7YdEmvMl / 69:4294`

OFF 按钮放在控制弹窗左上角。

默认样式：

- 白色背景。
- `#9394C4` 描边。
- `#6667AB` 文本。
- 尺寸约 `52 x 32`，圆角约 `10`。

选中样式：

- `#6667AB` 实心背景。
- 白色文本。
- 无额外描边。

弹窗整体保持现有底部弹窗样式和圆角。亮度、色温滑条继续使用现有 `DeviceSliderFunctionView` 和当前项目图标资源。

## 交互规则

OFF 选中状态与亮度联动：

- 初始 `isOn == false` 或亮度为 0% 时，OFF 按钮选中。
- 点击未选中的 OFF：设置为 OFF，亮度改为 0%。
- 点击已选中的 OFF：取消 OFF，亮度恢复到当前 Group 的 high-end trim；如果没有上限，则恢复到 100%。
- 用户把亮度滑到 0%：自动选中 OFF。
- 用户在 OFF 状态下把亮度滑到大于 0%：自动取消 OFF。

亮度范围：

- Scene 控制弹窗的亮度下限固定允许 0%。
- 不再使用 low-end trim 限制 Scene 控制弹窗亮度下限。
- high-end trim 继续限制 Scene 控制弹窗亮度上限。

色温范围：

- 色温滑条限制继续保留。
- OFF 选中时可以继续显示当前色温值。
- OFF 场景 Preview 和 SAVE 不下发色温。

## 数据语义

不新增存储属性，不修改数据库结构。

Group 场景数据保存规则：

- OFF：`SceneExecuteData.isOn = false`，`SceneExecuteData.lightness = 0`。
- 非 OFF：`SceneExecuteData.isOn = true`，`SceneExecuteData.lightness` 保存用户选择亮度对应的 Mesh lightness 值。
- `cct` 字段继续保存当前 UI 色温或 clamp 后的色温，作为兼容字段；OFF 下发时不使用它。

UI 临时数据 `ExecuteSceneData` 仍表示百分比亮度和色温。实现时需要让它能携带或推导当前 OFF 状态，最终保存到 `SceneExecuteData.isOn`。

历史数据不迁移。已有数据仍按当前字段读取；新保存数据需要保证 `isOn` 与 `lightness` 一致。

## Preview 行为

Scene Settings 和创建场景页面都遵守同一规则。

对每个被控制的 Group：

- OFF 场景：只调用 `MeshAPI.setGroupOnOffState(address:isOn:false)`。
- 非 OFF 场景：
  - 如果 Group 内存在有效 CCT 设备，继续调用 `MeshAPI.setGroupCTLState(...)`。
  - 如果 Group 内存在仅支持亮度的设备，继续调用 `MeshAPI.setGroupLightnessState(...)`。

OFF Preview 不发送 CTL、Lightness 或 CCT 命令。

## SAVE 与同步消息

`Scene.getSyncMessageHandles(node:data:)` 作为统一入口处理 OFF。

当目标 `SceneExecuteData.isOn == false` 时：

- 只生成 `GenericOnOffSet(false)`。
- 随后生成 `SceneStore(sceneNumber)`。
- 不生成 `LightCTLSet`。
- 不生成 `LightLightnessSet`。
- 不下发 CCT。
- 不做“无 OnOff model 时降级 Lightness”的 fallback；当前业务认定不会存在有 Light Lightness 但没有 OnOff 的设备。

当目标 `isOn == true` 时：

- 保持现有逻辑。
- 支持 CCT 的设备下发 CTL。
- 不支持 CCT 但支持亮度的设备下发 Lightness。
- 仅支持 OnOff 的设备下发 OnOff。
- 然后保存 SceneStore。

## 入口覆盖范围

OFF 同步逻辑必须放在 `Scene.getSyncMessageHandles(node:data:)`，不能只放在页面控制器中。

这样可以覆盖：

- Scene Settings 页面保存已关联场景。
- 创建场景后同步到组内设备。
- 新设备直接添加到已有关联场景的 Group。
- 恢复设备时，如果设备所在 Group 关联了场景。
- 手动重新同步 Scene / Group 时的场景同步。
- 其它复用 `NodeSyncData.syncScenes` 的场景同步入口。

## 成功失败判定

因为 OFF 场景实际下发的命令类型从 Lightness / CTL 变成 OnOff，同步成功判断必须跟实际命令一致。

Sync device(s) 成功响应处理：

- 场景同步时，除了现有 `LightLightnessStatus`、`LightCTLTemperatureStatus`、`LightCTLStatus`、`LightHSLStatus`，还需要识别 OnOff 成功回包。
- 收到 OnOff 状态时更新节点本地开关状态，避免后续 SceneStore 缓存场景时使用旧状态。
- 设备恢复的 deferred restore 成功响应处理也需要同样识别 OnOff 回包。

Operation success 判断：

- OFF 场景：判断设备已保存该 scene，且设备缓存的 `SceneExecuteData.isOn == false` 即可；不再用 lightness 或 CCT 判断失败。
- 非 OFF 场景：继续使用现有 `SceneExecuteData.isSynced(with:for:)`，按设备有效 CCT 能力比较 `isOn`、lightness、CCT 和状态。

这样可以避免 OFF 场景已经正确下发 `GenericOnOffSet(false)` 和 `SceneStore`，但因为没有 Lightness / CTL 状态而被误判失败。

## 边界行为

- low-end trim 大于 0% 时，Scene 控制弹窗仍能选择 0% OFF。
- high-end trim 小于 100% 时，取消 OFF 恢复到 high-end trim，而不是 100%。
- 色温范围仍按 Group 或设备有效 CCT range 处理。
- 不支持 CCT 的设备继续跳过 CCT 比较和 CCT 下发。
- 空组保存本地场景数据即可，不需要同步。
- 离线或 Mesh 未连接时，现有联网校验保持不变。
- 不修改资源 target 配置或依赖。

## 非目标

- 不新增数据库字段。
- 不新增 `isOff` 属性。
- 不迁移历史 Scene 数据。
- 不调整普通 Group 控制页的 low-end trim 行为。
- 不改变非 OFF 场景的 CCT / Lightness 下发策略。
- 不重构 Scene、Group 或 Sync device(s) 的整体架构。

## 验证计划

UI 与交互：

- OFF 默认样式和选中样式符合 Figma。
- 点击 OFF 后亮度变为 0%，OFF 选中。
- 再次点击 OFF 后亮度恢复到 high-end trim 或 100%，OFF 取消。
- 亮度滑到 0% 后 OFF 自动选中。
- OFF 状态下亮度滑到大于 0% 后 OFF 自动取消。
- low-end trim 大于 0% 的 Group 仍可滑到 0%。
- high-end trim 仍限制最大亮度。
- 色温滑条范围保持不变。

Preview：

- Scene Settings 中 OFF 只发 group OFF，不发 CTL / Lightness / CCT。
- 创建场景页面中 OFF 只发 group OFF，不发 CTL / Lightness / CCT。
- 非 OFF Preview 行为保持原逻辑。

SAVE / Sync：

- OFF 场景保存为 `isOn = false`、`lightness = 0`。
- OFF 场景同步消息为 `GenericOnOffSet(false)` + `SceneStore`。
- OFF 场景同步成功判断不依赖 Lightness / CCT 状态。
- 新设备添加到已有关联 OFF 场景的 Group 后，同步按 OFF 逻辑执行。
- 恢复设备时，已关联 OFF 场景按 OFF 逻辑执行。
- 手动重新同步 Scene / Group 时，OFF 场景按 OFF 逻辑执行。
- 非 OFF 场景保持现有设备级 CCT clamp 和同步状态判断。

构建：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 自审结果

- 无未决需求。
- 范围聚焦在 Scene 控制弹窗、Scene Preview、Scene 同步消息、成功失败判定。
- 已明确使用现有 `SceneExecuteData.isOn`，不新增字段、不改数据库结构。
- 已明确 OFF 时不下发亮度和色温。
- 已覆盖添加设备入组、设备恢复和手动同步入口。
- 已明确 OFF 成功失败判断按实际 OnOff 命令处理。
