# EFC Action Cell 文案与间距修复计划

## 背景

目标页面是 EFC 设备 Edit 页面，在 `When The Emergency Event Ends:` 下方的 Action Cell 中：

- `Set Brightness to` 需要统一为 `Set Brightness To`。
- EFC 页面底部弹窗/展开选项中也不能再出现 `Set Brightness to`。
- 选中 `Set Brightness To` 后，亮度滑条与亮度 Value Label 的视觉间隔需要收紧到与 `Repeatedly Send Emergency Control Every` cell 一致。

## 当前代码事实

- Action Cell 选项来自 `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift` 的 `restoreActionOptions`，当前写死为 `Set Brightness to`。
- 同一区域的 restore brightness stepper 配置来自 `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditState.swift`，当前 `.restoreBrightness` title 也是 `Set Brightness to`。
- Action Cell 内部亮度控件在 `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireSelectionCell.swift` 的 `EmerFireRestoreActionCell` 中，标题和值 label 到 slider 控件的布局独立于普通 `EmerFireStepperCell`。
- `Repeatedly Send Emergency Control Every` 使用 `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireStepperCell.swift`，其 field/value 行到控件区的主要约束是 `fieldTitleLabel.snp.bottom + SCRYFrom(12)`，同时由卡片高度和底部 inset 控制整体视觉间距。
- 状态列表字符串 `set_brightness_to_value` 当前为 `Set Brightness to %@`，`scripts/check_efc_status_content_list.sh` 也固定了旧文案。如果严格按“App 中只使用 Set Brightness To”，这里也需要同步改为 `Set Brightness To %@`。

## 推荐方案

采用小范围 UI 文案与布局收口，不重构 EFC Edit 页面结构。

1. 统一 EFC restore action 文案。
   - 将 `LinkedEmerFireEditVC+Table.swift` 中 Action 选项改为 `Set Brightness To`。
   - 将 `LinkedEmerFireEditState.swift` 中 `.restoreBrightness` 的 title 改为 `Set Brightness To`。
   - 将 `SunSmart/en.lproj/Localizable.strings` 中 `set_brightness_to_value` 改为 `Set Brightness To %@`。
   - 同步更新 `scripts/check_efc_status_content_list.sh` 中的 contract，避免后续回归到小写 `to`。

2. 收紧 Action Cell 选中亮度时的垂直间距。
   - 在 `EmerFireRestoreActionCell` 中将亮度控件布局对齐 `EmerFireStepperCell` 的节奏。
   - 保持 `brightnessFieldTitleLabel` 与 `brightnessValueLabel` 同行，slider 控件区距离该行使用与 stepper cell 相同的 `SCRYFrom(12)` 约束。
   - 收紧 `brightnessHeight` / `selectedCardHeight` 或相关 bottom 约束，避免卡片内部多余空白把 slider 推远。
   - 不改 slider 交互逻辑、范围、保存配置或协议 payload。

3. 增加轻量 contract 防回归。
   - 在 `scripts/check_efc_controller_flows.sh` 或现有 EFC contract 中新增断言：
     - EFC Edit/Action 相关 Swift 源码不包含 `Set Brightness to`。
     - EFC status content contract 期望 `Set Brightness To %@`。
   - 不对历史 docs 做批量替换，避免污染已有分析记录。

## 备选方案

方案 A：只改两个 Swift 硬编码文案和 Action Cell 布局。

- 优点：改动最小。
- 缺点：状态列表仍可能显示 `Set Brightness to 100%`，不满足“App 中只使用 Set Brightness To”的完整口径。

方案 B：把所有 `Set Brightness To` 文案改为本地化 key，并顺手整理 EFC Edit 页面所有硬编码英文。

- 优点：长期更整洁。
- 缺点：触及面明显扩大，容易混入无关本地化/target 风险，不适合这次 UI 微调。

推荐采用上面的“小范围 UI 文案与布局收口”方案。

## 验证计划

1. 运行 EFC contract：

   `bash scripts/check_efc_controller_flows.sh`

2. 运行 status content contract：

   `bash scripts/check_efc_status_content_list.sh`

3. 搜索确认没有新的旧文案来源：

   `rg -n "Set Brightness to" SunSmart scripts -g '!Pods/**'`

   预期：不再命中 App 源码、strings 或 contract 脚本；历史 docs 可以保留。

4. iPhoneOS 构建验证：

   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 影响范围

- 只影响 EFC Edit 页面 Action Cell、EFC status content 文案格式，以及对应 contract。
- 不修改 mesh 同步、保存逻辑、AppKey、vendor payload 或 EFC 配置模型。
- 不修改中文文案，当前中文没有大小写问题；如后续要求，也可以同步核对 zh-Hans key 是否需要补齐 `set_brightness_to_value`。

