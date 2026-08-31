# Lumineux Asset Catalog 分组设计

## 背景

`SLGSync/Assets-SLGSync.xcassets` 使用 `Common`、`Device`、`Energy`、`FireAlarm1.5`、`Firmware`、`Group`、`Path`、`Profile`、`Scene`、`Site`、`Space`、`Timed` 十二个物理目录分组；`AppIcon` 保留在 catalog 根目录。

`Lumineux/Assets-Lumineux.xcassets` 当前包含 75 个 asset set，全部平铺在根目录。虽然 Xcode 和现有 Lumineux 合并器可以递归识别资源，但资源生成器、静态素材测试、配置检查和临时 XCTest reference catalog 仍假设资源位于根目录。只移动现有文件会导致后续重新生成时再次产生根目录资源。

## 目标

- Lumineux 使用与 SLGSync 相同的十二个物理分组目录。
- `AppIcon` 和 Lumineux 独有的 `AccentColor` 保留在 catalog 根目录。
- SLGSync 存在同名资源时，Lumineux 放入完全相同的分组。
- SLGSync 不存在同名资源时，只参考 SunSmart 同名资源的业务目录确定分组；图片仍使用 Lumineux 自己的文件，不复制 SunSmart 图片。
- 资源生成器以后重新运行时继续写入正确分组，不会重新在根目录生成重复 imageset。
- 移动前后资源名称、`Contents.json`、PNG/PDF 来源和图片字节保持不变。

## 非目标

- 不修改 `SunSmart/Assets.xcassets`、`SLGSync/Assets-SLGSync.xcassets` 或其他品牌 catalog。
- 不修改共享 UIKit 业务代码、图片调用、主题色、Bundle ID、签名或服务器配置。
- 不改变构建期合并策略，也不引入运行时品牌判断或图片染色。
- 不补充新的 Lumineux 图片资源。

## 目录结构

Lumineux catalog 根目录最终结构为：

```text
Assets-Lumineux.xcassets/
├── Contents.json
├── AppIcon.appiconset/
├── AccentColor.colorset/
├── Common/
├── Device/
├── Energy/
├── FireAlarm1.5/
├── Firmware/
├── Group/
├── Path/
├── Profile/
├── Scene/
├── Site/
├── Space/
└── Timed/
```

每个分组目录包含与 SLGSync 相同形式的 `Contents.json`，不启用 `provides-namespace`。当前没有 Lumineux 资源的 `Energy`、`FireAlarm1.5`、`Path` 仍保留为空分组，使两份 catalog 的一级分组保持一致。

## 完整资源映射

| 目标位置 | 数量 | 资源名称 |
| --- | ---: | --- |
| 根目录 | 2 | `AppIcon`、`AccentColor` |
| `Common` | 13 | `add`、`favourite_normal`、`favourite_selected`、`hud_loading`、`import`、`launch_logo`、`launch_logo_120`、`loading`、`loading_big`、`lumineux_launch_logo`、`navigation_back`、`reset`、`select` |
| `Device` | 19 | `device_add`、`device_add_disable`、`device_add_setting`、`device_add_waiting`、`device_all_off`、`device_all_on`、`device_control_off`、`device_control_off_big`、`device_control_on`、`device_control_on_big`、`device_identify`、`device_restore`、`device_restore_disable`、`device_scan`、`device_select`、`light_value_add`、`light_value_minus`、`slider_point`、`slider_point_disable` |
| `Firmware` | 3 | `firmware_delete`、`firmware_history`、`server_download` |
| `Group` | 13 | `auto`、`group_control_disable`、`group_control_disable_big`、`group_empty`、`group_off`、`group_off_big`、`group_on`、`group_on_big`、`sensor_move`、`sync_failed_small`、`sync_loading_small`、`sync_success_small`、`sync_waiting_small` |
| `Profile` | 1 | `profile_chart_occupancy_daylight` |
| `Scene` | 6 | `scene_data_value_add`、`scene_data_value_minus`、`scene_empty`、`scene_group_disable`、`scene_group_off`、`scene_group_on` |
| `Site` | 4 | `menu_icon`、`more_vertical`、`no_Internet`、`site_empty` |
| `Space` | 13 | `space_add`、`space_empty`、`space_energy_data`、`space_group`、`space_group_selected`、`space_main`、`space_main_selected`、`space_more`、`space_more_selected`、`space_scene`、`space_scene_selected`、`space_timed`、`space_timed_selected` |
| `Timed` | 1 | `schedule_target_select` |
| `Energy`、`FireAlarm1.5`、`Path` | 0 | 保留空分组 |

总计仍为 75 个 asset set，不因分组增加或减少资源。

## 分组数据来源

新增一份 Lumineux 专用的分组清单，逐项记录 75 个 asset set 的目标分组；根目录资源使用明确的 root 标记。该清单是物理目录、生成器输出和测试断言的唯一分组来源。

分组清单不引用图片文件，也不改变现有 `icon-manifest.json` 中的 Figma 节点、源文件和逻辑尺寸。这样可以避免把现有 `Buttons`、`Navigation`、`Status` 等设计来源标签误当成 Xcode 业务分组。

## 生成与测试适配

### 资源生成器

- `prepare_lumineux_icons.swift` 根据分组清单计算 imageset 输出目录，并在写入前创建对应分组目录。
- `prepare_lumineux_assets.swift` 使用相同分组清单处理 Logo 和其他派生资源。
- 生成器发现资源缺少分组、分组名称不在批准集合内或同名资源出现多个位置时立即失败，避免生成隐性重复项。

### 素材与配置测试

- `LumineuxAssetTests.swift` 改为按分组清单定位资源，不再拼接根目录 imageset 路径。
- 测试断言 75 个资源全部且仅出现一次，根目录不能残留 `.imageset`，并验证十二个分组目录及其 `Contents.json` 完整。
- `check_lumineux_configuration.rb` 按新路径检查 `Common/lumineux_launch_logo.imageset`。
- `make_lumineux_test_workspace.rb` 递归统计并复制 75 个 asset set，不能把一级分组目录误计为 asset set。

### 合并器

现有 `merge_assets.rb` 已按资源名称递归索引。公共 catalog 存在同名资源时仍覆盖到公共资源原位置；Lumineux 独有资源使用 Lumineux 自身相对路径。合并算法不需要修改，只增加回归测试确认分组后行为不变。

## 数据完整性与错误处理

- 移动前记录全部 75 个 asset set 内文件的 SHA-256 清单；移动后按资源名称和相对文件名重新计算，必须完全一致。
- 分组目录不能启用 namespace，否则 `UIImage(named:)` 的现有名称会改变。
- 任一资源遗漏、重复、落入未批准目录或重新生成到根目录时，静态测试失败。
- 当前工作区已有 Lumineux 未提交改动全部保留；整理只改变 Lumineux catalog 内的物理位置及为此必需的生成器、测试和文档。

## 验证标准

1. 分组结构与 SLGSync 一级目录一致，`AppIcon`、`AccentColor` 位于根目录。
2. 75 个 asset set 名称集合及所有文件哈希与移动前一致。
3. 两个资源生成器重新运行后，仍保持同一目录结构且没有根目录 `.imageset`。
4. Lumineux 素材、配置、合并器和 NordicSigMeshSDK 依赖检查通过。
5. Lumineux 真机目标 Debug 构建与签名校验通过，合并后的 75 个 Lumineux asset set 与源 catalog 逐文件一致。
6. SunSmart iPhone 16 模拟器 Debug 构建回归通过，证明其他 target 未受影响。
7. 不安装或启动用户真机 App，不提交或推送资源实施改动，除非用户后续明确要求。
