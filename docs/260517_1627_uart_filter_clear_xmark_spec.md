# UART 筛选清空按钮图标设计

## 背景

UART 消息页面有两个筛选输入框：

- Contain
- Ignore

两个输入框右侧都有一个清空按钮，当前共用 `SpaceDebugUARTViewController.configureFilterClearButton(_:action:)` 配置。现有图标为 SF Symbol `xmark.circle.fill`。

现在需要将这两个按钮的图标改成 SF Symbol `xmark`。

## 目标

- 将 UART 消息页面两个筛选输入框右侧清空按钮的图标统一改为 `xmark`。
- 保留现有按钮尺寸、布局、颜色和点击清空行为。
- 保留现有输入框、筛选逻辑、消息刷新逻辑和本地化文案。

## 非目标

- 不改 `UITextField` 布局结构。
- 不把按钮迁移到 `UITextField.rightView`。
- 不调整按钮点击热区。
- 不修改 UART 消息过滤、清空消息、分享或接收逻辑。
- 不新增资源图片。

## 确认方案

采用最小图标替换方案：

在 `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift` 中，只修改 `configureFilterClearButton(_:action:)` 的图标名：

- 原图标：`xmark.circle.fill`
- 新图标：`xmark`

两个筛选清空按钮都调用该配置函数，因此只需修改一处即可同时影响 Contain 和 Ignore 两个输入框右侧按钮。

## 风险与处理

`xmark` 是线性图标，相比 `xmark.circle.fill` 视觉面积更小。为了不改变点击体验，本次保留现有按钮宽高约束，只替换图标，不缩小按钮。

如果后续需要调整视觉大小，应单独评估按钮 image inset 或 symbol configuration，不纳入本次改动。

## 验证计划

- 静态检查 `SpaceDebugUARTViewController.swift` 中 `configureFilterClearButton(_:action:)` 使用 `UIImage(systemName: "xmark")`。
- 静态检查不再出现 `xmark.circle.fill`。
- 构建 `SunSmart` Debug iOS target，确认无编译错误。
- 手动检查 UART 消息页面：
  - Contain 输入框右侧按钮显示为 `xmark`。
  - Ignore 输入框右侧按钮显示为 `xmark`。
  - 点击 Contain 右侧按钮仍清空 Contain 筛选并刷新消息列表。
  - 点击 Ignore 右侧按钮仍清空 Ignore 筛选并刷新消息列表。
