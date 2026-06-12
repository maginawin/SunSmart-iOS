# Content Display UI Settings 设计

## 背景

`Site - Space - More - Content Display` 当前已有 `Device name display` 模块。数据层已经包含 3 个 Space 级字段：

- `displayDeviceNamePrefix`
- `showCCTQuickButtons`
- `controlType`

这 3 个字段已经进入本地数据库、Space JSON 导出和导入流程。本轮需求是在 Content Display 页面按 Figma 设计补齐两个 UI 模块：

- `CCT quick buttons`
- `Control style`

本轮只实现设置页展示、交互、本地保存和云同步触发，不修改 Device / Group 控制页实际如何消费 `showCCTQuickButtons` 和 `controlType`。

## 目标

- 在 Content Display 页面展示 `CCT quick buttons` 模块，并读取 `SpaceData.showCCTQuickButtons` 作为初始状态。
- 在 Content Display 页面展示 `Control style` 模块，并读取 `SpaceData.controlType` 作为初始状态。
- 用户修改任一设置后，立即保存到本地数据库，并沿用 `.common` 变更链路进入云同步队列。
- 所有 UI 文字使用国际化。
- 图片资源中已有文字不做国际化处理。
- 使用用户已提供的 4 组 Control style 图片资源：
  - `detailed control type image`
  - `purple selected`
  - `purple unselected`
  - `simple control type image`
- 未提供图片的 UI 元素使用代码实现。

## 非目标

- 不修改 Device / Group 控制页中 CCT 快捷按钮或 slider 样式的实际展示逻辑。
- 不修改 `SpaceData` 字段定义、数据库列、导入导出字段，除非实现时发现现有数据层有遗漏。
- 不新增 Auth 信息。
- 不调整无关 Space、Group、Device 同步逻辑。
- 不重写 Content Display 页面导航和现有 `Device name display` 模块。

## 当前代码事实

- `ContentDisplayViewController` 目前只包含 `.deviceNameDisplay` 选项。
- 现有 `Display device name prefix` 开关更新后会发送 `spaceDataChangedNotificaitonName`，object 为 `SpaceChangeDataType.common`。
- `SpaceViewController` 收到 `spaceDataChangedNotificaitonName` 后会更新 `space.lastUpdate`、调用 `space.save()`，再根据变更类型触发同步。
- 当前 `.common` 变更走 `.slow` 同步，即本地立即保存，云端同步任务等待 10 秒后执行。同一个同步 operation 重复加入队列时会取消旧 handle 并重新计时，因此该路径具备 debounce 效果。
- `SpaceData.showCCTQuickButtons` 默认值为 `false`。
- `SpaceData.controlType` 默认值为 `.simple`，允许值为 `.simple` 和 `.detailed`。

## 方案选择

采用“在现有页面内扩展模块类型”的方案。

备选方案：

- 重写整个页面为静态布局：视觉可控，但改动大，容易影响现有 `Device name display`。
- 只补普通开关/选项行，不做 Figma 卡片样式：改动小，但不符合已提供 Figma 和图片资源的设计目标。

推荐方案继续使用现有 `ContentDisplayViewController` 入口和 table/cell 结构，按模块类型拆分最小必要 cell。这样能保留既有页面行为，并把新增 UI 控制在 Content Display 范围内。

## UI 结构

页面模块顺序：

1. `Device name display`
2. `CCT quick buttons`
3. `Control style`

### Device name display

保持现有视觉和交互。初始状态读取 `space.displayDeviceNamePrefix`，用户切换后保存并触发同步。

### CCT quick buttons

新增一个白色圆角模块，包含：

- 标题：`CCT quick buttons`
- 说明：`Show CCT preset quick buttons on device and group pages with color temperature capable devices.`
- 开关行标题：`Show CCT quick buttons`
- 右侧 `UISwitch`

初始状态读取 `space.showCCTQuickButtons`。用户切换后更新该字段。

### Control style

新增一个白色圆角模块，包含：

- 标题：`Control style`
- 说明：`Choose how slider control are displayed on device and group pages.`
- 两个选择卡：
  - `Simple`
  - `Detailed`

每张卡包含：

- 顶部预览图
- 主标题
- 副标题
- 底部选中/未选中状态图

`Simple` 卡使用：

- `simple control type image`
- `purple selected` 或 `purple unselected`
- 主标题：`Simple`
- 副标题：`Slider only`

`Detailed` 卡使用：

- `detailed control type image`
- `purple selected` 或 `purple unselected`
- 主标题：`Detailed`
- 副标题：`Label + value`

选中卡边框使用主题紫色，未选中卡边框使用灰色。点击任一卡片后更新 `space.controlType`。

## 保存与同步设计

沿用现有 `SpaceChangeDataType.common` 变更链路，不新增 `SpaceChangeDataType.contentDisplay`。

任一 Content Display 设置变化后：

1. 更新当前 `space` 的对应字段。
2. 发送 `spaceDataChangedNotificaitonName`，object 使用 `SpaceChangeDataType.common`。
3. `SpaceViewController` 监听到通知后：
   - 更新 `space.lastUpdate`
   - 调用 `space.save()`，确保本地立即持久化
   - 对 `.common` 使用 `.slow` 调用 `syncSpace`

如果当前 site 尚未上传云端，继续沿用 `syncSpace(level:)` 内部已有逻辑，由 `.syncSite(site:syncSpaces:)` 兜底。

`.slow` 的等待时间为 10 秒。用户短时间连续修改 3 个 Content Display 属性时，同一 Space 同步 operation 会被重新加入队列并重置等待时间，最终倾向于合并成一次云端上传。

## 国际化

新增国际化 key 覆盖以下文字：

- `CCT quick buttons`
- `Show CCT preset quick buttons on device and group pages with color temperature capable devices.`
- `Show CCT quick buttons`
- `Control style`
- `Choose how slider control are displayed on device and group pages.`
- `Simple`
- `Slider only`
- `Detailed`
- `Label + value`

需要同步更新：

- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`

图片资源内已有英文文字不进入国际化。

## 资源策略

使用已提供并位于 `SunSmart/Assets.xcassets/Common` 的 4 组 imageset。

实现时需要检查：

- 资源名与 `UIImage(named:)` 调用完全一致。
- 资源已被主 app target 引用。
- 不修改图片内容。

未提供图片的部分用 UIKit/SnapKit 代码实现，包括背景、圆角、边框、说明文字、卡片布局、点击区域和分隔线。

## 权限与错误处理

- Owner 和 Editor 可以更新这 3 个 Content Display 属性。
- Visitor 不允许更新这 3 个属性。
- 页面入口仍可沿用现有 Space More 展示规则，但 Visitor 进入页面后应看到不可编辑状态，不能通过 switch 或选择卡修改值。
- `SpaceViewController` 现有通知监听仍作为最终保护：只有 owner/editor 会执行保存和同步。
- 云同步失败沿用现有 Space 同步失败状态和重试入口，不新增单独错误 UI。
- 若图片资源缺失，Control style 卡片预览区域应保持布局稳定；实现前优先检查资源，缺失时先停止并请求补充资源。

## 验收标准

- Content Display 页面按顺序展示 3 个模块。
- `CCT quick buttons` switch 初始状态等于 `space.showCCTQuickButtons`。
- `Control style` 初始选中卡等于 `space.controlType`。
- 切换 CCT switch 后，本地 `space.showCCTQuickButtons` 更新并保存。
- 切换 Control style 后，本地 `space.controlType` 更新并保存。
- 任一新增设置变化后，Space 使用 `.common` 变更链路进入 `.slow` 云同步队列。
- Visitor 进入页面时不能修改 `displayDeviceNamePrefix`、`showCCTQuickButtons`、`controlType`。
- 现有 `Display device name prefix` 仍可正常展示、切换、保存和同步。
- 所有新增文字从国际化文件读取。
- 4 组已提供图片资源被正确使用。
- `SunSmart` iPhoneOS Debug 构建通过。

## 验证计划

- 源码检查：
  - 确认新增 UI 只影响 Content Display 相关文件。
  - 确认新增国际化 key 在英文和简体中文中都存在。
  - 确认新增设置沿用 `.common` 变更类型和 `.slow` 同步等级。
  - 确认 Visitor 不可编辑，Owner/Editor 可编辑。
- Git 检查：
  - 确认不改动无关文件。
  - 确认用户已提供的图片资源不被重写。
- 构建验证：
  - 使用项目指定的 iPhoneOS `xcodebuild` 命令构建 `SunSmart` scheme。
