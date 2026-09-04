# Lumineux Common Retina 资源接入设计

## 目标

把用户提供的 6 组 Lumineux Common Retina PNG 接入 `Lumineux/Assets-Lumineux.xcassets`，覆盖构建期合并 catalog 中的同名公共资源。只处理已确认的一一对应素材，不改业务逻辑、布局约束、其他品牌资源或服务器区域功能。

## 接入范围

| 用户文件 | Lumineux 资源名 | 逻辑尺寸 |
| --- | --- | ---: |
| `Property 1=filter@2x/@3x.png` | `filter_selected` | 30 × 30pt |
| `images/select@2x/@3x.png` | `menu_select` | 30 × 30pt |
| `Property 1=order_down@2x/@3x.png` | `order_down` | 30 × 30pt |
| `Property 1=order_up@2x/@3x.png` | `order_up` | 30 × 30pt |
| `images/select_2@2x/@3x.png` | `server_select` | 30 × 30pt |
| `images/user@2x/@3x.png` | `user_big` | 88 × 88pt |

明确不接入：

- `value_buoy`：本批未提供。
- `images/select_3@2x/@3x.png`：不在已确认的缺失资源映射中，保留在用户附件目录，不复制进工程。

## 源文件与 Catalog

- 将 12 份原始 PNG 以最终资源名保存到 `Lumineux/DesignAssets/Provided/Common`，2x/3x 文件字节必须与用户附件完全一致。
- 在 `Lumineux/Assets-Lumineux.xcassets/Common` 新增 6 个同名 `.imageset`。
- 每个 `Contents.json` 保留 universal 1x 空槽位，只引用 2x 和 3x 文件；不生成、放大或缩小任何 1x 图片。
- Catalog 内的 2x/3x 文件与留档源文件逐字节一致，不重绘、不改色、不压缩。
- 在 `Lumineux/DesignAssets/asset-groups.json` 中把 6 个资源登记为 `Common`，保持当前分组验证链有效。
- Lumineux target 继续通过现有 `Merge Lumineux Assets` 构建阶段将公共 catalog 与品牌 catalog 合并；不修改合并脚本或 Xcode target 资源引用。

## 验证设计

实施遵循测试先行：

1. 先扩展素材测试，让测试因 6 组源文件、分组映射及 imageset 尚不存在而按预期失败。
2. 接入最小资源文件后，验证：
   - 12 份源 PNG 的 SHA-256 与附件一致；
   - 30pt 资源为 60/90px，`user_big` 为 176/264px；
   - `Contents.json` 的 1x 不含 filename，2x/3x 文件完整；
   - Catalog 的 2x/3x 与源文件逐字节一致；
   - 6 组资源均位于 Common 且无同名重复。
3. 运行合并器测试，确认生成 catalog 使用 6 组 Lumineux 图片覆盖公共同名资源，未改变其他品牌和公共资源。
4. 使用真实 UIKit 使用点验证 `TitleSelectView`、`UserSettingsViewController`、`ServerSelectionViewController` 以及筛选/排序按钮的图片加载、逻辑尺寸和约束结果；截图按 iPhone 与 iPad 代表尺寸人工审阅。资源改动不以仅编译成功作为完成依据。
5. 更新 `docs/lumineux-missing-assets.md` 与 `Tests/Branding/README.md`：Common 待补从 7 组降为 1 组，只剩 `value_buoy`；总待补从 57 组降为 51 组。

## 工作区边界

- 保留当前未提交的 Europe-region 及其他用户修改，不覆盖、不回退、不混入本次资源映射。
- 不修改 SunSmart、SLGSync、Archipelago、SylSmart 的 asset catalog。
- 本次不安装或控制真实设备，不发起网络、账号、Mesh 或服务器操作。
