# Site Space Item iPad 布局重叠分析与修复计划

## 问题结论

iPad 8 / iPad 9 上 Site 页面 Space item 中 `Schedules` 与下方日期重叠的问题真实存在，根因是 Space item 的高度和图片区域高度随 iPad 屏幕高度缩放变小，但右侧文本区域没有用完整垂直约束串联，`Schedules` 和日期之间缺少最小间距约束。

iPad Air (5th) 未复现，主要因为它的逻辑高度更接近当前 iPad 设计基准，`SCRYFrom(192)` 得到的 item 高度更大，暂时保留了足够的视觉间距。

## 代码证据

- `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - `itemRowCount` 在 iPad 上固定为 2。
  - `sizeForItemAt` 固定返回 `CGSize(width: itemW, height: SCRYFrom(192))`。
  - iPad 8 / iPad 9 逻辑高度约 1080pt，相对 `iPadStandardSize.height = 1210` 的缩放系数约 0.893，因此 item 高度约 171pt。
  - iPad Air (5th) 逻辑高度约 1180pt，缩放系数约 0.975，因此 item 高度约 187pt。

- `SunSmart/Main/Space/View/SpacesViewCell.swift`
  - `iconImageView.top = SCRYFrom(48)`，`iconImageView.bottom = SCRYFrom(-24)`，图片高度由 cell 高度反推。
  - 右侧文本中 `luminaires/switches/groups/scenes/schedules` 依次用 `top = previous.bottom + spacing` 排列。
  - `timeLabel` 没有跟 `schedulesLabel` 串联，而是 `bottom = iconImageView.bottom`。
  - 因此当 cell 高度被压缩时，`schedulesLabel` 会继续向下排，`timeLabel` 固定贴在图片底部，两者会互相侵入。

- `SunSmart/Common/Macro/MacroDefinition.swift`
  - iPad 竖向尺寸使用 `SCREEN_HEIGHT / 1210` 缩放。
  - 字体初始化走 `FontFit`，且只有 `kSafeAreaBottomHeight > 0` 时才按高度缩放字体。
  - iPad 8 / iPad 9 是 Home button 机型，底部 safe area 通常为 0，字体不会随 cell 高度一起缩小，这会进一步放大重叠风险。

## 推荐修复方案

推荐采用“修复 Space item 内部垂直约束”的方案，不按机型特判，不扩大到其他页面。

1. 在 `SpacesViewCell` 中让右侧信息成为完整的垂直约束链。
   - 保留 `luminaires -> switches -> groups -> scenes -> schedules` 的现有顺序。
   - 将 `timeLabel.top` 约束到 `schedulesLabel.bottom + 最小间距`。
   - 将 `timeLabel.bottom` 保持小于等于或等于 `iconImageView.bottom`，避免与图片区域底部脱节。

2. 对日期 label 使用抗压缩策略。
   - `timeLabel` 保持单行。
   - 必要时允许尾部截断，避免日期过长时把布局撑坏。
   - 不新增用户可见文案，不涉及本地化。

3. 保持 Site 页面 item 高度暂不调整。
   - 不建议第一步就把 `SCRYFrom(192)` 改大，因为这会影响 iPad 上每屏展示密度和滚动体验。
   - 如果约束链修复后仍不够，再考虑把 iPad item 高度提升到一个最小值，例如 `max(SCRYFrom(192), 180)`，但这应作为备选方案。

## 备选方案

如果你希望视觉间距更接近 iPad Air (5th)，可以直接给 iPad item 高度加下限：

- 在 `SiteViewController.sizeForItemAt` 中对 iPad 使用最小高度。
- 优点：改动小，风险低。
- 缺点：没有修复 cell 内部约束缺口，未来如果字体、语言或内容变化，仍可能在其他尺寸上重现。

## 验证计划

1. 静态检查
   - 确认 `SpacesViewCell` 中 `Schedules` 和日期之间存在明确约束。
   - 确认没有新增硬编码文案、本地化 key、资源或 target 配置改动。

2. 构建验证
   - 运行 iPhoneOS 构建：
     `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

3. 视觉验证
   - 在 iPad 8 / iPad 9 实机或同尺寸环境查看 Site 页面 Space item。
   - 覆盖 All Spaces 与 Favourites 两个 tab，因为两者复用同一个 `SpacesViewCell`。
   - 覆盖普通 Space、带 gateway 状态图标、带 sync failed 图标、带权限 label 的 Space，确认顶部 stack 不影响右侧统计信息布局。

## 待确认

建议按“推荐修复方案”执行：只改 `SpacesViewCell` 内部右侧信息的垂直约束链，不改 item 高度，不做 iPad 8/9 机型特判。

## 实施记录

已按推荐方案执行，改动范围保持在 Space item：

- `SunSmart/Main/Space/View/SpacesViewCell.swift`
  - `timeLabel` 固定为单行，并使用尾部截断。
  - `timeLabel.top` 约束到 `schedulesLabel.bottom + SCRYFrom(4)`，明确建立 `Schedules` 与日期之间的垂直顺序。
  - `timeLabel.bottom` 优先贴齐 `iconImageView` 底部；当 iPad 8 / iPad 9 高度不足时，允许日期在 card 底部安全边距内下移，避免和 `Schedules` 重叠。

- `scripts/check_site_space_item_layout.sh`
  - 新增静态布局回归脚本，锁住 `Schedules` 与日期之间必须存在显式间距约束。
  - RED 阶段：修改前脚本失败，能捕获当前约束缺口。
  - GREEN 阶段：修改后脚本通过。

## 验证结果

- `bash scripts/check_site_space_item_layout.sh`：通过。
- `git diff --check`：通过。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`：通过。

未做 Simulator 校验；仍建议在 iPad 8 / iPad 9 实机或同尺寸环境做一次 Site 页面视觉确认。
