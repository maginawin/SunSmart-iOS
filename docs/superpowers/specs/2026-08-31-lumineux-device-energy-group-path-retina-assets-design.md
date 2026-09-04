# Lumineux Device、Energy、Group、Path Retina 资源接入设计

## 背景

用户在 `/Users/sr/Documents/SunSmart/assets/new2` 提供了 Device、Energy、Group、Path 的一部分 Lumineux 品牌 PNG。工程继续沿用此前 Common Retina 资源的接入方式：原始 2x/3x 文件逐字节保存，asset catalog 的 universal 1x 槽位保留但不填写文件名，不生成 1x 图片。

本轮只增加 Lumineux 同名资源覆盖，不修改共享 Swift、公共资源、SLGSync 资源、资源合并器或其他 target。当前工作区中的 Common Retina 与 Europe 未提交改动必须完整保留。

## 接入范围

| 分类 | 用户文件 | Lumineux 同名资源 | 逻辑尺寸 |
| --- | --- | --- | --- |
| Device | `Frame 133@2x/@3x.png` | `switch_proxy_instructions_1` | 310 × 328pt |
| Device | `Frame 132@2x/@3x.png` | `switch_proxy_instructions_2` | 287 × 312pt |
| Energy | `images/Hard-Drive20@2x/@3x.png` | `energy_device` | 20 × 20pt |
| Energy | `images/csv@2x/@3x.png` | `energy_csv` | 20 × 20pt |
| Energy | `images/phone20@2x/@3x.png` | `energy_phone` | 20 × 20pt |
| Group | `images/press@2x/@3x.png` | `switch_press` | 30 × 30pt |
| Group | `images/press_long@2x/@3x.png` | `switch_press_long` | 30 × 30pt |
| Group | `images/save@2x/@3x.png` | `switch_save` | 40 × 40pt |
| Path | `箭头左@2x/@3x.png` | `path_direction_left` | 15.5 × 6pt（2x）／约 15.67 × 6pt（3x） |
| Path | `箭头右@2x/@3x.png` | `path_direction_right` | 15.5 × 6pt（2x）／约 15.67 × 6pt（3x） |
| Path | `images/add@2x/@3x.png` | `path_item_add` | 9 × 9pt |

上述映射由文件语义、像素尺寸、SLGSync 同名资源尺寸及生产调用点交叉确认。

## 明确排除

- `new2/icon/路径@2x/@3x.png` 本轮不处理。
- 不接入尚未提供的 `energy_light`、`auto_big`、`member_add`、`switch_save_un`。
- 不生成任何新的 `@1x` 文件。
- 不修改源 PNG 的像素、颜色、透明度、文件格式或元数据。

## 文件组织

原始用户文件按最终业务分类和资源名保存到：

- `Lumineux/DesignAssets/Provided/Device`
- `Lumineux/DesignAssets/Provided/Energy`
- `Lumineux/DesignAssets/Provided/Group`
- `Lumineux/DesignAssets/Provided/Path`

对应 imageset 保存到 `Lumineux/Assets-Lumineux.xcassets/<分类>/<资源名>.imageset`。每个 Contents.json 只为 2x/3x 指定文件名，1x 条目不含 `filename`。

`Lumineux/DesignAssets/asset-groups.json` 增加 11 项映射。Lumineux 原始 catalog 由 81 组增至 92 组，其中 90 个 imageset、AppIcon 和 AccentColor。由于 11 个资源名都已存在于公共 catalog，合并后总数仍应为 695 组。

## 运行时路径

- Device：`SwitchProxyInstructionsViewController` 加载两张开关代理说明图。
- Energy：`EnergyTimeSeriesDataImportView` 与 `EnergyTimeSeriesDataExportView` 加载设备、手机和 CSV 图标。
- Group：`GroupSwitchPanelViewCell` 与 `GroupPowerSwitchCell` 加载短按、长按和保存图标。
- Path：`GroupPathSequencePathViewCell` 加载左右方向箭头和新增路径项图标。

现有生产代码继续使用 `UIImage(named:)`，通过 Lumineux 构建期合并 catalog 自动覆盖同名公共资源。

## 测试与验收

实施遵循测试先行：

1. 先扩展静态素材契约到 92 组，固定 22 个源 PNG 的 SHA-256、像素尺寸、业务目录、空 1x 槽位及 catalog 与源文件字节一致性，并确认测试因生产资源尚不存在而失败。
2. 增加真实 UIKit 测试，使用独立编译的 Lumineux reference catalog 验证上述控制器和视图加载品牌图片，检查图片 bounds、父视图包含关系及页面快照；先确认缺图时失败。
3. 最小接入 11 组资源后运行静态素材、分组、合并器、生成器、工程配置与 SDK 依赖回归。
4. 在 iPhone SE 3、iPhone 16、iPad Pro 11 M4 的英文和简体中文环境运行目标 UIKit 矩阵并人工检查截图。
5. 使用正常 `DerivedData3` 路径构建 `SunSmart.xcworkspace` 的 Lumineux 真机 Debug，验证签名、合并 catalog 数量和 92 组品牌资源零差异覆盖；只构建，不安装或启动真机 App。

## 文档与数量更新

完成后更新 `docs/lumineux-missing-assets.md` 与 `Tests/Branding/README.md`：

- SLGSync 范围内已覆盖资源由 43 组增至 54 组。
- 待提供资源由 51 组减至 40 组。
- Device 待补由 2 组减至 0，Energy 由 4 组减至 1，Group 由 6 组减至 3，Path 由 3 组减至 0。
- 已提供资源总数由 76 组增至 87 组。
- Lumineux catalog 由 81 组增至 92 组；合并 catalog 预计保持 695 组。

## Git 边界

本轮资源、测试、脚本和文档实施改动保持未提交，除非用户后续明确要求提交。设计文档按 brainstorming 工作流单独提交。不得暂存、提交、清理或覆盖当前工作区的 Common Retina、Europe 或其他既有改动。
