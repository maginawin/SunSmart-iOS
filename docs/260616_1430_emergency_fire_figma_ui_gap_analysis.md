# Emer&Fire Controller Figma UI 差异分析

## 结论

当前代码中的 Emer&Fire Controller 页面已经覆盖了核心业务结构：名称、网关上报、关联组、事件发生配置、事件结束配置、底部操作按钮都存在。但与 Figma 节点 `136:8064` 的 UI 设计相比，仍存在明显差异，主要集中在页面标题拼写、section header 样式、关联组选择区、事件结束 Action 卡片、卡片尺寸和边框圆角。

其中 `Emer&Fire Controler` 拼写错误需要改为 `Emer&Fire Controller`。

> 说明：当 Figma 截图中的默认值与文字需求冲突时，以文字需求为准。例如 Fire Alarm 默认 100%、Set Brightness to 默认 100%，不采用 Figma 截图中的 90%/30%。

## Figma UI 关键结构

- 页面标题：`Emer&Fire Controller`
- 顶部区域：
  - `Name` label + 40pt 高度输入框
  - `Report To Gateway` 单行 cell，右侧红色下划线 `Waiting for setup`
  - `Associate With Group(s)` label + 40pt 高度选择 cell
- `When The Emergency Event Occurs:`：
  - 标题后带冒号
  - 下方说明文案：`Fire emergency take higher priority.`
  - 三个 140pt 高度白色卡片：
    - `Fire Alarm Emergency`
    - `Power Loss Emergency`
    - `Repeatedly Send Emergency Control Every`
- `When The Emergency Event Ends:`：
  - 标题后带冒号
  - 下方说明文案：`Execution will only begin after all emergency events have ceased.`
  - `Action` 卡片高度约 193pt
  - Action 选项为横向排列：`Restore AUTO` / `Set Brightness to` / `None`
  - `Set Brightness to` 的亮度 slider 位于同一张 Action 卡片内部
  - `Resuming in:` 和 `Send Count (5-second interval):` 使用与事件发生配置一致的 140pt 控制卡片
- 底部 CREATE 区域为白色底栏，顶部有分割线。

## 当前代码差异

| 分类 | Figma 预期 | 当前代码 | 影响 | 建议 |
| --- | --- | --- | --- | --- |
| 页面标题 | `Emer&Fire Controller` | `LinkedEmerFireEditVC.swift` 中为 `Emer&Fire Controler` | 明显拼写错误 | 必须修正 |
| Name 输入区 | 40pt 高度、5pt 圆角、浅灰边框 | `EmerFireNameCell` 使用 10pt 圆角白卡，无边框，整体高度更大 | 视觉不一致 | 调整为 Figma 样式；Add 页面不显示多余同步图标 |
| Report To Gateway | 40pt cell、5pt 圆角、浅灰边框，右侧 13pt 红色下划线 | `EmerFireStatusTextCell` 约 44pt、10pt 圆角、无边框，右侧字体偏小 | 视觉密度和边框不一致 | 收紧高度、圆角、边框与字体 |
| Associate With Group(s) | label 在 cell 外，下面是 40pt 选择 cell | `EmerFireSelectionCell` 将 title/value 放在同一张较大的白卡内 | 层级不一致 | 改成外部标题 + 单行选择框 |
| 事件 section 标题 | 背景上直接显示 title + detail，无白卡 | `EmerFireInfoCell` 使用白色卡片包裹 header，且当前 detail 为空 | 与 Figma 明显不同；缺少说明文案 | 新增或调整 header cell，去掉白卡并补充说明 |
| 事件发生标题 | `When The Emergency Event Occurs:` 带冒号 | 当前字符串无冒号 | 文案不一致 | 修正文案 |
| 事件结束标题 | `When The Emergency Event Ends:` 带冒号 | 当前字符串无冒号 | 文案不一致 | 修正文案 |
| Fire/Power Brightness 卡片 | 140pt 高度；中部有 `Set Brightness To:` label | 当前使用 `EmerFireStepperCell`，估高为 84pt，未看到独立中部 label | 卡片高度与信息层级不一致 | 扩展 stepper cell 支持 subtitle/field label，并统一 140pt 高度 |
| Trigger Interval 卡片 | 140pt 高度，无 `Set Brightness To:` label | 当前与其他 stepper 共用 cell | 可能可复用，但高度需统一 | 同一 cell 支持有无 field label |
| Action 卡片标题 | `Action` | `EmerFireRestoreActionCell` 为 `Action type:` | 文案不一致 | 改为 `Action` |
| Action 选项布局 | 三个选项横向排列在浅色背景条内 | 当前 `EmerFireRestoreActionCell` 使用纵向 stack | 明显不符合 Figma | 改为横向 radio group |
| Action brightness slider | `Set Brightness to` slider 在 Action 卡片内部 | 当前 `.restoreBrightness` 是独立 table row | 结构与 Figma 不一致 | 将 restore brightness 控件合并进 Action cell，按 action 状态显示/隐藏或禁用 |
| Resuming/Send Count | 两张 140pt 控制卡片 | 当前估高 84pt | 视觉高度不一致 | 统一控制卡片高度 |
| 圆角与边框 | 小输入/选择 cell 为 5pt 圆角 + 边框；大控制卡片为 10pt 圆角 | 当前多处统一 10pt 圆角且无边框 | 缺少 Figma 区分 | 按组件类型拆分样式 |
| 右侧箭头 | Figma 使用图片箭头资源 | 当前使用 SF Symbol `chevron.right` | 与资源风格可能不一致 | 优先查找并复用项目已有图片资源；缺少资源再确认 |

## 与业务需求相关的确认点

以下行为应继续以文字需求为准，而不是完全照 Figma 截图数值：

- Fire Alarm Emergency 默认值：100%，范围 10%-100%，step 1%
- Power Loss Emergency 默认值：10%，范围 1%-100%，step 1%
- Repeatedly Send Emergency Control Every 默认值：5s，范围 1-10s，step 1s
- Event Ends 默认 Action：`Restore AUTO`
- `Set Brightness to` 默认值：100%，范围 1%-100%
- `Resuming in:` 默认 2s，范围 0-120s，step 1s
- `Send Count` 默认 2，范围 1-5，step 1

## 建议修改范围

### 必须修正

1. 将页面标题统一改为 `Emer&Fire Controller`。
2. 调整事件 section header，补齐 Figma 文案和冒号，移除白卡样式。
3. 将 Action 区域改为 Figma 的横向 radio group，并将 `Set Brightness to` slider 合并到 Action 卡片内。
4. 将关联组选择区改为外部 title + 单行选择框。
5. 调整 Name、Report、Group 这些 40pt 小 cell 的圆角、边框和字体。

### 视觉对齐优化

1. 统一大控制卡片高度为 140pt。
2. 为 Fire Alarm / Power Loss 亮度卡片增加 `Set Brightness To:` 中部 label。
3. 检查底部 CREATE / LINK / LINKED 区域高度和分割线是否与 Figma 一致。
4. 查找项目已有箭头、加减按钮资源，优先复用，缺少资源时再向用户确认上传。

## 涉及代码位置

- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireNameCell.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireStatusTextCell.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireSelectionCell.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireInfoCell.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireStepperCell.swift`

## 推荐实施顺序

1. 先修正文案和 section header，风险最低。
2. 调整小 cell 样式：Name、Report、Associate With Group(s)。
3. 调整 stepper card 高度和 `Set Brightness To:` label。
4. 重构 Action cell 的内部布局，把 restore brightness 控件移入 Action card。
5. 检查 Add 虚拟设备、Edit 虚拟设备、Edit 真实设备三种底部状态是否都保持正确：`CREATE` / `LINK` / `LINKED`。
6. 运行 iPhoneOS `xcodebuild` 验证。
