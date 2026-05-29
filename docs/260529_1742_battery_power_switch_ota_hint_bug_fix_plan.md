# Battery Power Switch OTA Hint Bug 修复计划

## 背景

Battery Power Switch 的 BLE OTA 提示组件已加入 `BleFirmwareTypeUpdateViewCell`。当前发现两个问题：

- 折叠为一行时，新增 details widget 会把整个 Cell 撑得很宽，iPhone 上右侧内容不可见。
- 点击 details widget 后，其他 Cell 宽度恢复正常，但 details widget 高度仍是一行，未按预期多行展示完整内容。

## 根因判断

页面的 `UICollectionViewFlowLayout` 使用 `estimatedItemSize` 自适应 Cell 尺寸，`BleFirmwareTypeUpdateViewCell` 没有固定 self-sizing 计算时的目标宽度。新增提示 label 是一段很长的英文文案，折叠态虽然设置了 `numberOfLines = 1` 和尾部省略，但在 self-sizing 阶段仍可能通过 intrinsic content size 参与横向尺寸计算，从而把 Cell 的自动宽度撑大。

展开态高度没有变成多行，主要风险点在同一套自适应尺寸链路：当前只更新了提示容器的高度约束并 invalidate layout，但没有让 Cell 在自适应计算时固定宽度后重新按该宽度计算多行文本高度。也就是说，文案换行宽度和 Cell 高度计算没有稳定绑定到 collection view 的实际可用宽度。

## 修复目标

- 只影响 Battery Power Switch 类型设备展开后的提示组件。
- 其他设备类型的 Cell UI 和尺寸逻辑保持不变。
- 折叠态：提示展示一行，尾部省略，不撑宽 Cell，右侧按钮图片为 `arrow_fold_down`，按钮 30x30。
- 展开态：提示展示完整内容，自动换行，右侧按钮图片为 `arrow_fold_up`，按钮 30x30。
- iPhone 和 iPad 都按实际 Cell 宽度计算提示高度。

## 推荐方案

1. 在 `BleFirmwareTypeUpdateViewCell` 中固定自适应宽度计算。
   - 覆写 `preferredLayoutAttributesFitting(_:)`。
   - 使用 layout attributes 给出的目标宽度作为固定宽度。
   - 通过 `contentView.systemLayoutSizeFitting(...)` 只让高度自适应，宽度保持 collection view 分配的宽度。
   - 这样能避免长文案把 Cell 横向撑开。

2. 收紧提示 label 的横向压缩规则。
   - 保留 label 的 left/right 约束。
   - 将 horizontal compression resistance 调低到 `.defaultLow`。
   - 确保折叠态长文本优先截断，而不是要求父级扩宽。

3. 让展开态高度按固定宽度重新计算。
   - 当前 `batteryPowerSwitchOTAHintHeight` 已按 `contentView.bounds.width` 计算，保留这个方向。
   - 在点击展开/收起后，先更新状态和约束，再触发 Cell layout，然后通知 collection view invalidate。
   - 如果自适应计算仍不能稳定刷新，再将提示高度计算改为使用固定的 `bounds.width` fallback：`collectionView` 分配宽度或 `SCREEN_WIDTH - SCRXFrom(32)`，避免 0 宽时算出错误高度。

4. 保持改动范围。
   - 不改 controller 的数据结构。
   - 不改其他设备类型 UI。
   - 不重写整页 layout。

## 验证计划

1. 静态检查约束：
   - 折叠态 label 不再能通过 intrinsic width 撑开 Cell。
   - 展开态提示容器高度大于折叠态，并可容纳完整文案。

2. 构建验证：
   - 运行：
     `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

3. 重点人工验证：
   - iPhone：Battery Power Switch 展开后，Cell 右侧内容完整可见。
   - iPhone：提示默认折叠为一行并显示省略号。
   - iPhone：点击提示后完整多行展示。
   - iPad：提示宽度和多行高度符合实际 Cell 宽度。
   - 非 Battery Power Switch 类型设备没有出现提示，原 UI 不变。
