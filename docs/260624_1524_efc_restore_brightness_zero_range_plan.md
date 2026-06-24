# EFC Restore Brightness 0% Range 分析与方案

## 需求结论

在 EFC Edit 页面中，当 `When The Emergency Event Ends:` 的 `Action` 选择 `Set Brightness To` 时，Action 卡片下方的亮度控件需要允许 `0%...100%`。当前实现只能到 `1%...100%`，问题真实存在。

本需求只应影响恢复动作的亮度值，也就是 `restoreSettings.brightness`。不应改变 `When The Emergency Event Occurs:` 下 Power Loss / Fire Alarm 的触发亮度范围，也不应扩展到 Action preset、Enabled、Report To Gateway、关联组订阅、AppKey bind 或 publish group 行为。

## 代码事实

- UI 入口在 `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift`：
  - `.restoreAction` 使用 `EmerFireRestoreActionCell`。
  - 当前传入 `brightnessRange: 1...100`，所以 Action 卡片内部 slider / +/- 不可能选择 `0%`。
- 状态层在 `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditState.swift`：
  - `normalizeStepperValues()` 会把 `restoreBrightness` 夹到 `1...100`。
  - `setStepperValue(for: .restoreBrightness, value:)` 也会把输入夹到 `1...100`。
  - `stepperConfiguration(for: .restoreBrightness)` 仍返回 `1...100`，虽然当前 `.restoreBrightness` 独立 row 不在 `visibleRows` 中，但保留一致性更安全。
- Action cell 在 `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireSelectionCell.swift`：
  - `EmerFireRestoreActionCell` 完全依赖外部传入的 `brightnessRange` 做 clamp、minus/plus guard 和 slider 位置计算。
  - 因此外部改成 `0...100` 后，cell 本身可以自然支持 0。
- 配置/同步层允许 0：
  - `LinkedEmerFireConfig.lightness(from:)` 已将百分比夹在 `0...100` 后转成 mesh lightness。
  - `.setBrightness` 的 restore action 使用 `restoreSettings.brightness` 生成 `.lightness(...)`。
  - `DeviceEmerFireData+Sync.swift` 会把 `configuration.actionConfig(for: .restore, ...)` 下发为 EFC action config。
  - Monitor mock restore 也直接读取 `configuration.restoreSettings.brightness`。

## 根因

问题不是协议转换层不支持 0，也不是同步 planner 不支持 0。根因是 Edit UI 与 Edit state 的恢复亮度范围沿用了 `1...100` 的普通亮度下限，导致用户无法输入、保存或重新打开已有 `0%` 配置。

如果只改 `LinkedEmerFireEditVC+Table.swift` 的 `brightnessRange`，用户当场可以拖到 0，但回调进入 `LinkedEmerFireEditState.setStepperValue` 后仍会被压回 1。下一次保存或重新打开也会回到 1。因此必须同时修改状态层 clamp。

## 候选方案

### 方案 A：最小聚焦修复，推荐

只放宽 restore brightness：

- `LinkedEmerFireEditVC+Table.swift`：`.restoreAction` 配置 `EmerFireRestoreActionCell` 时将范围改为 `0...100`。
- `LinkedEmerFireEditState.swift`：
  - `normalizeStepperValues()` 的 `restoreBrightness` 下限改为 0。
  - `setStepperValue(for: .restoreBrightness, value:)` 的下限改为 0。
  - `stepperConfiguration(for: .restoreBrightness)` 的 range 改为 `0...100`，保持隐藏/历史 row 的状态一致。
- `scripts/check_efc_controller_flows.sh`：增加 contract，锁住 restore brightness 允许 0，同时避免误改 Power Loss / Fire Alarm 触发亮度范围。

优点：改动面最小，符合当前 EFC Edit 页保持 brightness-only 的既有边界；不会碰同步架构或其他入口。缺点：如果未来还有别的页面复用 restore brightness 规则，需要再抽常量。

### 方案 B：抽 shared range 常量

在状态层或 config 附近增加恢复亮度范围常量，例如 restore brightness range 与 trigger brightness range 分开，然后 UI 和 state 都引用同一处。

优点：长期可读性更好。缺点：当前只有少数调用点，新增抽象收益有限，容易把小修扩成结构调整。

### 方案 C：只改 UI range

只把 `EmerFireRestoreActionCell` 的传入 range 改成 `0...100`。

不推荐。状态层仍会把 0 压回 1，用户看到的 UI 行为和实际保存结果会不一致。

## 推荐实施计划

采用方案 A。

1. 修改 `LinkedEmerFireEditState.swift`，只放宽 `.restoreBrightness` 的 clamp 与 range 到 `0...100`。
2. 修改 `LinkedEmerFireEditVC+Table.swift`，让 Action 为 `Set Brightness To` 时传给 `EmerFireRestoreActionCell` 的 `brightnessRange` 为 `0...100`。
3. 修改 `scripts/check_efc_controller_flows.sh`，新增断言：
   - `LinkedEmerFireEditVC+Table.swift` 必须包含 restore action 的 `brightnessRange: 0...100`。
   - `LinkedEmerFireEditState.swift` 必须允许 restore brightness 下限 0。
   - Power Loss 和 Fire Alarm 的既有范围不应被顺手放宽。
4. 运行验证：
   - `bash scripts/check_efc_controller_flows.sh`
   - `git diff --check`
   - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与边界

- 当前 worktree 已有未提交改动，且涉及 EFC sync 相关文件；实施时需要只触碰本方案列出的文件，避免混入现有改动。
- 不新增本地化 key；用户可见文案不变。
- 不修改 SDK；当前 App 层 `0...100` 到 mesh lightness 的转换已经允许 0。
- 不修改 `restoreActionType`、`restoreResumingSeconds`、`restoreSendCount` 或关联组订阅策略。
- 不修改 Power Loss / Fire Alarm 触发亮度范围：Fire Alarm 仍是 `10...100`，Power Loss 仍是 `1...100`。

## 待确认点

请确认是否按“方案 A：最小聚焦修复”执行。
