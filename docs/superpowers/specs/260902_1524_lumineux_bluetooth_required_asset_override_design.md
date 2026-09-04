# Lumineux Bluetooth Required 插图覆盖设计

## 目标

仅为 Lumineux target 覆盖 `BluetoothRequiredViewController` 使用的 `bluetooth_required` 图片，公共资源和其他品牌保持不变。

## 输入资源

- `/Users/sr/Documents/SunSmart/assets/new3/images/empty_1@2x.png`：480 × 388
- `/Users/sr/Documents/SunSmart/assets/new3/images/empty_1@3x.png`：720 × 582

两张图片与公共 `bluetooth_required` 的对应 Retina 画布尺寸一致，因此保留当前 UIImage 原生尺寸和页面约束关系。

## 实现设计

在 `Lumineux/Assets-Lumineux.xcassets/Space/` 新增 `bluetooth_required.imageset`，其中：

- `empty_1@2x.png` 复制并命名为 `bluetooth_required@2x.png`；
- `empty_1@3x.png` 复制并命名为 `bluetooth_required@3x.png`；
- `Contents.json` 声明 universal 的 2x、3x 资源，1x 保持空缺，与公共 imageset 结构一致。

Lumineux 构建阶段的 `merge_assets.rb` 会按 asset set 名称覆盖公共 catalog 中的同名 set，因此页面仍使用 `UIImage(named: "bluetooth_required")`，无需增加品牌条件代码。

同时把 `bluetooth_required` 登记到 `Lumineux/DesignAssets/asset-groups.json` 的 `Space` 分组，并更新 Lumineux 资源契约测试中对应的资源映射和总数，避免品牌 catalog 校验把新增资源判定为未知项。

## 范围边界

- 不修改 `SunSmart/Assets.xcassets` 公共资源。
- 不修改 `BluetoothRequiredViewController` 或 `EmptyDataView`。
- 不影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart 等其他 target。
- 不修改或还原当前工作区已有的 `space_empty@2x.png`、`space_empty@3x.png` 变更。
- 不提交或推送 Git。

## 验证

1. 先让新增的聚焦资源契约在缺少 Lumineux 覆盖时按预期失败，再增加资源使其通过。
2. 运行 Lumineux 合并器到 `/private/tmp`，确认派生 catalog 只存在一个 `bluetooth_required.imageset`，且其 PNG SHA-256 与两张输入资源一致。
3. 检查 `Contents.json`、2x/3x 像素尺寸和透明通道，并运行 Lumineux 资源/配置检查。
4. 执行签名关闭的 Lumineux 构建，确认 Asset Catalog 编译无 duplicate asset 或 actool 错误。
5. 通过 UIKit/模拟器页面布局验证确认标题、插图和提示文字的约束仍成立，并检查实际显示的是 Lumineux 覆盖图片。

当前完整 `LumineuxAssetTests` 存在与本任务无关的既有失败：工作区未提交的 `space_empty` 图片不符合原画布契约。最终结果会把该基线与本次聚焦验证分开报告。
