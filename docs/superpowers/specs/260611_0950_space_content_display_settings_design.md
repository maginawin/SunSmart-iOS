# Space Content Display Settings 数据层设计

## 背景

`Site - Space - More - Content Display` 当前已有 `Display device name prefix` 配置。代码中该配置已作为 `SpaceData.displayDeviceNamePrefix` 保存到本地 `spaces` 表，但页面保存只调用 `space.save()`，没有触发 Space 数据变更通知；同时 `SpaceData.export()` 与 `SpaceData.update(spaceJsonData:)` 也没有包含该字段，因此现有配置不会随云同步、分享、导入恢复。

本需求在同一页面的数据层增加两类属性，并要求它们与既有 `Display device name prefix` 一样按 Space 级别保存。不同 Space 可以有不同配置。UI 暂不处理。

## 目标

- 在 Space 级别保存 3 个 Content Display 属性：
  - `displayDeviceNamePrefix`
  - `showCCTQuickButtons`
  - `controlType`
- 本地数据库、内存模型、复制、保存、读取保持一致。
- 普通云同步、分享前上传、分享加入、手动 JSON 导出/导入都携带并恢复这 3 个属性。
- 旧数据库、旧云端数据、旧分享码、旧 JSON 文件保持兼容。

## 非目标

- 不实现 Content Display 页面的新增 UI。
- 不修改色温控制控件 UI，仅预留可读取的数据层字段。
- 不新增 Auth 信息。
- 不调整无关 Space、Group、Device 同步逻辑。

## 方案选择

采用 `SpaceData` 一等字段方案。

备选方案包括：

- JSON 配置字段：新增 `contentDisplaySettings` 统一存储。扩展性较好，但会和现有 `displayDeviceNamePrefix` 结构不一致，并增加迁移复杂度。
- 独立配置表：以 `spaceId` 关联 Content Display 配置。边界清晰，但对当前仅新增两个属性而言过重，导入、导出、删除和查询都要额外维护。

推荐方案直接扩展 `SpaceData`，符合当前 `displayDeviceNamePrefix` 的代码风格，调用方读取简单，也最容易覆盖 Space 级差异和现有同步链路。

## 数据模型

`SpaceData` 保留现有字段：

- `displayDeviceNamePrefix: Bool = true`

新增字段：

- `showCCTQuickButtons: Bool = false`
- `controlType: SpaceControlType = .simple`

`SpaceControlType` 使用本地 enum 表达业务值，对外云端 JSON 使用字符串：

- `simple`
- `detailed`

兼容规则：

- 旧本地数据库没有新增列时，使用默认值。
- 旧云端 Space JSON 没有新增字段时，使用默认值。
- `controlType` 遇到未知字符串时，按 `.simple` 处理。

## 本地持久化

在 `spaces` 表新增两列：

- `showCCTQuickButtons`，Bool，默认 `false`
- `controlType`，String，默认 `"simple"`

需要同步补齐：

- `SpaceData.load(siteId:spaceId:)`
- `SpaceData.load(subNetworkId:)`
- `SpaceData.save()`
- `SpaceData.copy()`
- `SpaceData.initDatabase()` 的旧库增列逻辑

这样每个 Space 会独立持久化 3 个 Content Display 属性，不依赖 Site 或全局设置。

## 保存与同步触发

当前 `ContentDisplayViewController` 的保存行为需要从直接 `space.save()` 调整为复用现有 Space 数据变更链路。

保存任一 Content Display 属性时：

1. 更新当前 `space` 的对应字段。
2. 发送 `spaceDataChangedNotificaitonName`，object 使用 `SpaceChangeDataType.common`。
3. 由 `SpaceViewController` 现有监听逻辑统一更新 `space.lastUpdate`、执行 `space.save()`，并触发 `.syncSpace(level: .slow)`。

这样 3 个属性变化都会让当前 Space 进入 `needUploadCloud` 状态，并进入已有 Space 同步队列。

## 云端 JSON 格式

这 3 个属性放在 Space JSON 根级，与 `uuid`、`spaceName`、`deviceBlinkMode` 等 Space 属性同级。

示例：

```json
{
  "uuid": "space-id",
  "spaceName": "Office",
  "displayDeviceNamePrefix": true,
  "showCCTQuickButtons": false,
  "controlType": "simple"
}
```

字段定义：

| 字段 | 类型 | 默认值 | 允许值 | 说明 |
| --- | --- | --- | --- | --- |
| `displayDeviceNamePrefix` | Boolean | `true` | `true` / `false` | 是否显示设备名前缀 |
| `showCCTQuickButtons` | Boolean | `false` | `true` / `false` | 是否在色温控制控件中展示快捷按钮 |
| `controlType` | String | `"simple"` | `"simple"` / `"detailed"` | 控制控件类型，`simple` 为简单控件，`detailed` 为复杂控件 |

如果后端 `/sitespace/sync/spaceprops` 对 Space 字段存在白名单，需要允许并原样返回这 3 个字段。客户端导入侧会按缺字段默认值兜底。

## 导出路径

在 `SpaceData.export()` 中导出：

- `displayDeviceNamePrefix`
- `showCCTQuickButtons`
- `controlType`

由此自动覆盖：

- `CloudSynchronizationManager` 的 `.syncSpace`
- `.syncSite(site:syncSpaces:)`
- `.addSpaces`
- 分享、解绑前的 `spaceUpload` / `siteUpload`
- 手动导出 Space JSON 文件

## 导入路径

在 `SpaceData.update(spaceJsonData:)` 中读取：

- `displayDeviceNamePrefix`
- `showCCTQuickButtons`
- `controlType`

由此自动覆盖：

- Space 云端拉取
- 分享加入
- 批量加入 Space
- 手动 JSON 文件导入

缺字段按默认值处理，避免旧数据覆盖出异常状态。

## 分享与导入策略

Owner 或 Editor 修改 Content Display 后，Space 会因 `lastUpdate` 变化而进入 `needUploadCloud`。现有分享入口在打开分享前会检查未同步数据并先上传，因此分享码对应的 Space payload 应包含最新配置。

被分享用户获取 Space payload 后，继续走 `SpaceData.import(siteId:meshUUID:spaceJsonData:)` 和 `SpaceData.update(spaceJsonData:)`，配置随 Space 一起落库。

本地 JSON 导出和导入也走同一组 `export/update` 方法，不需要在文档选择器或分享 UI 中额外拼字段。

## 错误处理

- DB 增列失败时保持现有容错风格，不阻断应用启动；读取缺失数据按模型默认值兜底。
- 云端缺字段时使用默认值。
- 云端返回未知 `controlType` 时使用 `"simple"`。
- 云同步失败沿用现有 `syncCloudError` 和重试机制，不新增单独错误状态。

## 验收范围

- 旧数据库升级后，老 Space 默认 `displayDeviceNamePrefix = true`、`showCCTQuickButtons = false`、`controlType = simple`。
- 新建 Space、导入 Space、复制 SpaceData 后，3 个属性值一致。
- `SpaceData.export()` 输出 3 个字段，格式符合本文的云端 JSON 格式。
- `SpaceData.update(spaceJsonData:)` 能读取 3 个字段，缺字段和未知 `controlType` 按兼容规则处理。
- 修改任一属性后，当前 Space 的 `lastUpdate` 更新，`needUploadCloud` 为 true，并进入现有 Space 同步队列。
- 分享前上传、分享加入、手动 JSON 导出/导入能保留 3 个属性。
- `SunSmart` iPhoneOS Debug 构建通过。

## 验证命令

推荐构建命令：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
