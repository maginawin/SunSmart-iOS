# SLG Sync Plus Content Display 默认值更新方案

## 背景

当前 `Site - Space - More - Content Display` 的两个配置项来自 `SpaceData`：

- `showCCTQuickButtons`：当前全 target 默认 `false`
- `controlType`：当前全 target 默认 `.simple`

这两个字段已经进入本地数据库、Space JSON 导出、云同步、分享和导入合同。设备页和组页读取当前 Space 的字段值决定是否显示 CCT quick buttons，以及使用 Simple / Detailed 控制样式。

## 目标

按 target 区分默认值：

| Target | CCT quick buttons 默认值 | Control style 默认值 |
| --- | --- | --- |
| SunSmart | Disabled | Simple |
| Archipelago | Disabled | Simple |
| SylSmart | Disabled | Simple |
| SLG Sync Plus | Enabled | Detailed |

## 推荐方案

新增一个共享的 Content Display 默认值入口，集中表达品牌差异：

- 非 `SLGSync` 编译条件：`showCCTQuickButtons = false`、`controlType = .simple`
- `SLGSync` 编译条件：`showCCTQuickButtons = true`、`controlType = .detailed`

然后把所有“缺省值来源”改为复用这个入口，而不是在多个文件里继续写死 `false` / `.simple`。

## 计划修改点

1. `SunSmart/Common/Data/SpaceData.swift`
   - 为 `showCCTQuickButtons` 和 `controlType` 引入 target-aware 默认值。
   - 保持 SunSmart / Archipelago / SylSmart 当前行为不变。

2. `SunSmart/Common/Data/Database.swift`
   - 建表默认值改为共享默认值。
   - 旧数据库缺少 `showCCTQuickButtons` / `controlType` 列时，新增列默认值也改为共享默认值。
   - 数据库读取时，未知 `controlType` fallback 改为共享默认值，避免 SLG Sync Plus 遇到异常字符串时退回 Simple。

3. `SunSmart/Common/Data/ImportData.swift`
   - 云端、分享或导入 JSON 缺少 `showCCTQuickButtons` / `controlType` 时，fallback 改为共享默认值。
   - JSON 明确带值时保持使用 JSON 值，不覆盖用户或云端已有配置。

4. `SunSmart/Common/Data/ExportData.swift`
   - 不需要改字段名或 JSON 结构。
   - 继续导出当前 Space 的实际值：
     - `showCCTQuickButtons`: Boolean
     - `controlType`: `"simple"` / `"detailed"`

## 不纳入本轮的行为

- 不修改 Content Display 页面 UI 结构和文案。
- 不修改设备页 / 组页消费逻辑。
- 不 retroactively 覆盖已经保存到数据库或云端的用户配置。

也就是说，SLG Sync Plus 的新默认值只影响：

- 新建 Space
- 首次安装或旧数据库缺少这些列时的迁移默认值
- 云端 / 分享 / 导入数据缺少这两个字段时的 fallback
- 异常 `controlType` 字符串的 fallback

如果需要把 SLG Sync Plus 已存在的 Space 从旧默认值批量改成 Enabled / Detailed，需要额外设计一次数据迁移，并且要避免覆盖用户已经手动改过的偏好；不建议和本轮默认值调整混在一起。

## 验证方案

1. 静态检查
   - 确认 `showCCTQuickButtons = false`、`controlType = .simple`、`defaultValue: false`、`defaultValue: SpaceControlType.simple.rawValue` 不再作为这两个配置的散落默认值存在。
   - 确认 `Config/SLGSync/Debug.xcconfig` 和 `Config/SLGSync/Release.xcconfig` 仍设置 `SLGSync` 编译条件。

2. 构建验证
   - 优先运行：
     `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
   - 若时间允许，再分别构建 `SLG Sync Plus`、`Archipelago`、`SylSmart`，确认 target 差异没有破坏共享代码编译。

## 待确认

请确认采用推荐方案：只更新“默认值 / fallback”，不覆盖已保存的 SLG Sync Plus Space 配置。
