# Lumineux 八键开关面板示例图覆盖设计

## 目标

只为 Lumineux target 覆盖八键开关 Create 与 Select Panel 页面使用的两张面板示例图。SunSmart 公共资源、其他品牌资源和生产 Swift 代码保持不变。

## 输入与映射

| 输入文件 | Lumineux 同名资源 | 像素尺寸 |
| --- | --- | --- |
| `/Users/sr/Documents/SunSmart/assets/new3/8 keys2@2x.png` | `Scene Panel (8 key)` 2x | 686 × 640 |
| `/Users/sr/Documents/SunSmart/assets/new3/8 keys2@3x.png` | `Scene Panel (8 key)` 3x | 1029 × 960 |
| `/Users/sr/Documents/SunSmart/assets/new3/button/8 keys@2x.png` | `Brightness Panel (8 key)` 2x | 686 × 640 |
| `/Users/sr/Documents/SunSmart/assets/new3/button/8 keys@3x.png` | `Brightness Panel (8 key)` 3x | 1029 × 960 |

## 接入方式

在 `Lumineux/Assets-Lumineux.xcassets/EightKeySwitches1.5/` 下新增两个与公共资源同名的 imageset。每个 imageset 只声明 universal 2x 和 3x 文件，1x 槽位保留为空；输入 PNG 原样复制，不缩放、不重编码。

同时把 `EightKeySwitches1.5` 及两个资源名登记到 `Lumineux/DesignAssets/asset-groups.json`，并同步维护 Lumineux 静态资源合同，使后续工程校验不会把新增资源判定为未知项。Lumineux 构建期合并器会按资源名覆盖公共 catalog 中的同名 imageset，因此现有 `UIImage(named:)` 调用无需改变。

## 范围边界

- 不修改 `SunSmart/Assets.xcassets` 中的原图。
- 不影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart 等其他 target。
- 不处理或生成 1x 图片。
- 不修改、清理、暂存或提交当前工作区已有的其他改动。
- 不提交或推送 Git。

## 验收边界

按用户要求，本次接入后不运行测试、模拟器、构建或真机验证。只报告实际新增和修改的文件；最终显示效果由用户在真机上验证。
