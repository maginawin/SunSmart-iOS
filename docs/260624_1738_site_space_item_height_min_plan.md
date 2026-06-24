# Site Space Item iPad 最小高度修复计划

## 背景

上一轮修复只处理了 `SpacesViewCell` 内部 `Schedules` 与日期之间缺少垂直约束的问题，但没有修改 Site 页面给 Space item 分配的高度。

当前代码仍然在 `SiteViewController.collectionView(_:layout:sizeForItemAt:)` 中返回 `SCRYFrom(192)`。在 iPad 8 / iPad 9 上，`SCREEN_HEIGHT / iPadStandardSize.height` 小于 1，导致实际 item 高度小于 192pt。你的判断成立：如果设计要求 Space item 至少保持 192pt，则需要在 item size 层加最小高度，而不是只依赖 cell 内部压缩布局。

## 开发目标

在 iPad 上，Space item 高度继续遵循现有缩放逻辑，但实际高度不得小于 192pt。iPhone 暂不改变，避免影响手机端列表密度。

## 改动范围

1. `SunSmart/Main/Site/Controller/SiteViewController.swift`
   - 修改 `collectionView(_:layout:sizeForItemAt:)`。
   - 保留现有宽度计算逻辑。
   - 将高度从单纯 `SCRYFrom(192)` 调整为 iPad 使用 `max(SCRYFrom(192), 192)`，iPhone 仍使用 `SCRYFrom(192)`。

2. `scripts/check_site_space_item_layout.sh`
   - 扩展现有静态布局回归脚本。
   - 增加对 `SiteViewController` item 高度下限的检查。
   - RED 阶段应能在当前代码上失败，因为现在还没有 192pt 下限。
   - GREEN 阶段在 `SiteViewController` 修改后通过。

3. `SunSmart/Main/Space/View/SpacesViewCell.swift`
   - 保留上一轮的内部约束修复，不继续扩大改动。
   - 不新增本地化、资源、target 配置或 Auth 信息。

## 实施步骤

1. 更新回归脚本
   - 在 `scripts/check_site_space_item_layout.sh` 中加入 `SiteViewController.swift` 检查目标。
   - 检查 `sizeForItemAt` 中存在 iPad 最小高度逻辑。
   - 运行脚本确认当前失败。

2. 修改 item 高度
   - 在 `SiteViewController.collectionView(_:layout:sizeForItemAt:)` 中增加高度变量。
   - iPad 使用缩放高度与 192pt 的较大值。
   - iPhone 保持原逻辑。
   - 返回 `CGSizeMake(itemW, itemH)`。

3. 验证
   - 运行 `bash scripts/check_site_space_item_layout.sh`。
   - 运行 `git diff --check`。
   - 运行 iPhoneOS 构建：
     `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

4. 文档更新
   - 在本文件补充实施记录和验证结果。

## 风险与边界

- iPad 8 / iPad 9 上每屏展示的 Space item 会变高，这是本次需求预期。
- iPad Air (5th) 上 `SCRYFrom(192)` 本身大概率已经接近或高于 192，视觉变化应很小。
- iPhone 不跟随 192pt 下限，避免小屏手机列表突然变高。
- 该改动只影响 Site 页面 All Spaces / Favourites 两个 tab，因为它们共用同一个 `sizeForItemAt` 和 `SpacesViewCell`。

## 待确认

建议按此方案执行：保留上一轮 `SpacesViewCell` 内部约束修复，并新增 iPad Space item 高度下限 192pt。

## 实施记录

已按确认方案执行：

- `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - `sizeForItemAt` 中新增 `itemH`。
  - iPad 使用 `max(SCRYFrom(192), 192)`，保证缩放后不低于 192pt。
  - iPhone 继续使用 `SCRYFrom(192)`，不改变手机端高度。

- `scripts/check_site_space_item_layout.sh`
  - 扩展检查范围到 `SiteViewController.swift`。
  - RED 阶段：当前代码缺少高度下限时脚本失败。
  - GREEN 阶段：新增高度下限后脚本通过。

## 验证结果

- `bash scripts/check_site_space_item_layout.sh`：通过。
- `git diff --check`：通过。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`：通过。

未做 Simulator 校验；仍建议在 iPad 8 / iPad 9 实机或同尺寸环境确认 Site 页面 Space item 高度和内容间距。
