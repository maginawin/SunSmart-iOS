# AC/Battery Power Switch Select Scene 顶部标题设计

## 背景

AC Power Switch 与 Battery Power Switch 的 Scene Panel 从 Switch 页面进入 Edit 页面，再进入 Select Scene 页面时，顶部分页标题当前显示为：

- Scene A
- Scene B
- Scene C
- Scene D

但 AC/Battery Power Switch 的 Scene Panel 实际按数字位置展示 Scene：

- Scene 1
- Scene 2
- Scene 3
- Scene 4

本次目标是让 AC/Battery Power Switch Edit -> Select Scene 页顶部标题与 Scene Panel 一致，显示 `Scene 1`、`Scene 2`、`Scene 3`、`Scene 4`。

## 代码事实

Select Scene 顶部标题由 `SwitchSelectScenePageController` 控制：

- `SwitchSceneData.SceneType.title` 当前固定返回 `switch_key_sceneA`、`switch_key_sceneB`、`switch_key_sceneC`、`switch_key_sceneD`。
- `menuView(_:titleAt:)` 直接使用 `sceneDatas[index].type.title`。
- AC/Battery Power Switch Edit 页面通过 `PJPreAddEightKeySwitchesVC.selectScenesAction()` 进入 `SwitchSelectScenePageController`。
- Group Power Switch 和旧 DeviceSwitch/Kinetic 流程也会复用 `SwitchSelectScenePageController`。

AC/Battery Power Switch 的 Scene Panel 实际数字展示由 `PJEightKeySwitchMonitorViewModel.keyItems` 提供：

- Scene A 对应 panel 上的 `1`
- Scene B 对应 panel 上的 `2`
- Scene C 对应 panel 上的 `3`
- Scene D 对应 panel 上的 `4`

已有可复用本地化 key：

- `neightkeyswitches_scene_1`
- `neightkeyswitches_scene_2`
- `neightkeyswitches_scene_3`
- `neightkeyswitches_scene_4`

这些 key 在 English 和简体中文中都已存在，不需要新增本地化文案。

## 方案比较

### 方案 A：为 Select Scene 页面增加标题显示风格

在 `SwitchSelectScenePageController` 中增加标题显示风格参数，默认保持现有 `Scene A/B/C/D`；AC/Battery Power Switch Edit 入口显式传入数字风格，显示 `Scene 1/2/3/4`。

优点：

- 只影响本次指定的 AC/Battery Edit -> Select Scene 入口。
- Group Power Switch、旧 DeviceSwitch/Kinetic 流程默认保持现状。
- 不改变 `SwitchSceneData.SceneType` 的数据语义，仍用 `.sceneA/.sceneB/.sceneC/.sceneD` 对应存储字段。
- 复用已有 `neightkeyswitches_scene_1` 到 `neightkeyswitches_scene_4` 本地化 key。

缺点：

- `SwitchSelectScenePageController` 会多一个标题风格参数。

### 方案 B：全局修改 `SwitchSceneData.SceneType.title`

把 `.sceneA/.sceneB/.sceneC/.sceneD` 的 title 全局改为 `Scene 1/2/3/4`。

优点：

- 实现最少。

缺点：

- 会影响所有 `SwitchSelectScenePageController` 调用方。
- Group Power Switch 和旧 DeviceSwitch/Kinetic 流程也会改变顶部标题，超出本次需求范围。

### 方案 C：直接修改 `switch_key_sceneA/B/C/D` 本地化值

把现有 `switch_key_sceneA/B/C/D` 的翻译改成 `Scene 1/2/3/4`。

优点：

- 代码改动极少。

缺点：

- 这些 key 还被 panel fallback 文案复用，会改变多个非目标页面。
- 会破坏 key 名与含义的一致性。
- 影响面不可控，不适合本次修复。

## 推荐设计

采用方案 A。

设计要点：

1. 在 `SwitchSelectScenePageController` 中增加标题显示风格，例如：
   - `.lettered`：默认值，显示 `Scene A/B/C/D`。
   - `.numbered`：显示 `Scene 1/2/3/4`。
2. `SwitchSceneData.SceneType` 保留现有 `.sceneA/.sceneB/.sceneC/.sceneD` 枚举和数据语义。
3. `menuView(_:titleAt:)` 改为根据标题显示风格返回对应 title。
4. `PJPreAddEightKeySwitchesVC.selectScenesAction()` 创建 `SwitchSelectScenePageController` 时传入 `.numbered`。
5. 其他入口不传参数，继续使用默认 `.lettered`。
6. 不修改 `switch_key_sceneA/B/C/D` 本地化值。
7. 不新增本地化 key。

## 影响范围

直接覆盖：

- AC Power Switch Edit -> Select Scene 顶部标题
- Battery Power Switch Edit -> Select Scene 顶部标题

保持不变：

- Group Power Switch -> Select Scene
- 旧 DeviceSwitch/Kinetic -> Select Scene
- Panel fallback 文案中的 `Scene A/B/C/D`
- Scene 选择、取消选择、回调、保存字段和同步逻辑

## 验收标准

1. 从 AC Power Switch Edit 进入 Select Scene，顶部标题显示 `Scene 1`、`Scene 2`、`Scene 3`、`Scene 4`。
2. 从 Battery Power Switch Edit 进入 Select Scene，顶部标题显示 `Scene 1`、`Scene 2`、`Scene 3`、`Scene 4`。
3. 选择和取消选择 Scene 的行为不变。
4. 选择结果仍正确写回 `sceneANumber`、`sceneBNumber`、`sceneCNumber`、`sceneDNumber`。
5. 其他复用 `SwitchSelectScenePageController` 的入口默认仍显示 `Scene A/B/C/D`。
6. 不新增或遗漏本地化文案。

## 验证计划

- 静态验证：
  - 确认 `SwitchSelectScenePageController` 默认标题风格仍为 lettered。
  - 确认 `PJPreAddEightKeySwitchesVC.selectScenesAction()` 显式传 numbered。
  - 确认 Group Power Switch 与旧 DeviceSwitch/Kinetic 入口没有传 numbered。
  - 确认没有修改 `switch_key_sceneA/B/C/D`。
- 构建验证：
  - 运行 SunSmart iPhoneOS Debug 构建。
- 可选手动验证：
  - AC Power Switch Edit -> Select Scene。
  - Battery Power Switch Edit -> Select Scene。
  - Group Power Switch -> Select Scene，确认标题仍保持原样。

## 自查结论

- 本设计只改变 Select Scene 顶部标题显示，不改变数据模型和业务流。
- 本设计不新增本地化 key，复用现有 English 和简体中文 key。
- 本设计不会全局替换 `Scene A/B/C/D`，避免影响旧入口和 panel fallback 文案。
