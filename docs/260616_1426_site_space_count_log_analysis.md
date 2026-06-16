# Site Space Count Log Analysis

## 结论

仅凭当前日志不能 100% 确认最终数值，因为 `siteInfo` 响应体被截断，关键的顶层 `spaces[0].switches`、`spaces[0].scenes`、`spaces[0].updateTimestamp` 没有完整展示。

但日志和代码已经能定位主要原因方向：Site 页 ALL Spaces 卡片上的 `switches`、`scenes` 不是直接读取接口里的 `deviceCount`，也不是根据 `nodes`、`groups[*].profile.scenes` 或 `groups[*].scenesDatas` 动态统计，而是导入 Space 后保存到 `SpaceData.switchesCount`、`SpaceData.sceneCount` 再展示。

## 证据

- 点击 Site cell 后请求 `/sitespace/get/siteprops`，随后执行导入并进入 `SiteViewController`。
- `SiteViewController` 的 ALL Spaces cell 使用 `allSpaces[indexPath.row]`，然后设置给 `SpacesViewCell.space`。
- `SpacesViewCell` 展示：
  - `switches` 使用 `space.switchesCount`
  - `scenes` 使用 `space.sceneCount`
- `SpaceData.update(spaceJsonData:)` 要求响应里存在顶层 `nodes`、`groups`、`scenes`、`schedules` 数组。
- 导入时：
  - `sceneCount = scenes.count`，其中 `scenes` 来自顶层 `json["scenes"]`
  - `switchesCount = switches.count`，其中 `switches` 来自顶层 `json["switches"]`

## 日志中的可疑点

1. `DeviceParameterNodeProbe` 只证明 `data.spaces[0].nodes` 有 6 个节点，其中能看到两个疑似 switch 类节点：
   - `pid=2A12`
   - `pid=2A11`

   但这不会直接影响 Site 卡片的 `switches` 数。当前代码统计的是顶层 `switches` 配置数组，不是 switch 节点数量。

2. 可见响应片段里有 `groups[*].profile.scenes` 和 `groups[*].scenesDatas`，但这些也不会直接影响 Site 卡片的 `scenes` 数。当前代码统计的是顶层 `scenes` 数组。

3. 如果用户认为 `scenes` 应包含 group profile scene、group scene execute data，或者 switch 绑定的 scene，那么当前展示逻辑和业务预期不一致。

4. 如果顶层 `switches` / `scenes` 在完整响应里本身就是错的或为空，则问题在上传/服务端数据合同或上一次同步数据。

5. 如果完整响应里的顶层 `switches` / `scenes` 是正确的，但 App 仍显示旧值，则需要重点检查 `spaces[0].updateTimestamp`。`SpaceData.update` 只有在 `server updateTimestamp > local lastUpdate` 或初始化时才覆盖本地数据；否则会保留本地旧 count。

## 下一步验证

需要补一条针对 `siteInfo` 导入后的轻量日志，打印每个 space 的：

- `spaceName`
- `updateTimestamp`
- 顶层 `nodes.count`
- 顶层 `switches.count`
- 顶层 `scenes.count`
- 导入后 `space.switchesCount`
- 导入后 `space.sceneCount`
- 是否因为 `updateTimestamp` 不新而跳过更新

这样可以直接区分是服务端返回的顶层数组错误、上传合同错误，还是本地导入被 `updateTimestamp` gate 跳过。

## 260616 新日志结论

新日志已经确认本次 Site 页面刷新没有真正覆盖本地 Space count，原因是两个 Space 的 `serverUpdateTimestamp` 都等于 `localLastUpdate`：

- `Space 1`
  - `serverUpdateTimestamp=1781589312`
  - `localLastUpdate=1781589312`
  - `phase=skipped`
  - `note=serverUpdateTimestampNotNewer`
- `mmmm`
  - `serverUpdateTimestamp=1781589312`
  - `localLastUpdate=1781589312`
  - `phase=skipped`
  - `note=serverUpdateTimestampNotNewer`

因此这次 `/sitespace/get/siteprops` 返回的数据只进入了 `received` 日志，没有进入 `applied` 阶段；页面最终仍使用本地 SQLite 中已有的 `SpaceData` count。

进一步看服务端 payload：

- `Space 1` 服务端顶层数据是 `nodes=0, switches=0, scenes=0, groups=1, schedules=0`，但本地旧值是 `device=0, switches=4, scenes=0, groups=1, schedules=0`。如果页面显示 Space 1 的 switches 为 4，那么来源就是本地旧 count，而不是本次服务端返回。
- `mmmm` 服务端顶层数据是 `nodes=6, switches=4, scenes=6, groups=16, schedules=0`，本地旧值是 `device=7, switches=4, scenes=6, groups=9, schedules=0`，同样被 skip，所以 groups/device 等差异没有被刷新。

当前最明确的问题点不是 UI 计算，而是 `updateTimestamp` gate：服务端内容已经和本地 count 不一致，但 `updateTimestamp` 没变，客户端按现有规则认为“不需要覆盖”。后续修复需要先决定业务规则：

- 如果服务端 `spaces[*]` 内容变化时必须刷新 Site 简介，则服务端同步/保存时需要递增对应 Space 的 `updateTimestamp`。
- 如果服务端无法保证递增，则客户端需要对 count 这类摘要字段增加更细的变化检测或轻量覆盖策略，避免 `updateTimestamp` 相等时保留旧简介。

## 260616 修复执行

已采用客户端方案 C：

- 在 `SpaceData.update(spaceJsonData:initialize:)` 中增加 Space 顶层摘要比较。
- 当 `serverUpdateTimestamp == localLastUpdate`，且服务端摘要和本地摘要不一致，且导入前 `space.needUploadCloud == false` 时，允许继续执行现有 full import。
- 当导入前 `space.needUploadCloud == true` 时继续 skip，避免覆盖本地未上传改动。
- DEBUG 日志继续使用 `[PJSpaceCountProbe]`：
  - `note=serverSummaryDiffers` 表示 timestamp 相等但摘要不同，已允许导入。
  - `note=serverSummaryDiffersButLocalNeedsUpload` 表示摘要不同但本地有未上传改动，仍然跳过。

摘要比较字段为 `deviceCount/groupCount/sceneCount/scheduleCount/switchesCount`。其中 `deviceCount` 使用顶层 `nodes.count`，`groupCount` 使用非虚拟 group 数量，和 full import 最终 count 口径一致。

## 260616 验证结果

- `git diff --check` 通过。
- 已运行 iPhoneOS 构建命令：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build`
- 构建仍被既有 FireAlarm/SDK 编译问题挡住，当前明确错误为：
  - `LinkedEmerFireConfig.swift:18:21: cannot find type 'EmergencyControllerMode' in scope`

下一步需要在 App 现场重新进入目标 Site，查看 `[PJSpaceCountProbe]`：

- `Space 1` 应从 `received` 继续进入 `applied`。
- `applied` 的 `note` 应包含 `serverSummaryDiffers`。
- 如果本地有未上传改动，则应继续 `skipped`，且 `note=serverSummaryDiffersButLocalNeedsUpload`。

## 260616 后续日志分析

用户反馈：Site 页 Space 1 显示 `Switches=4`，进入 Space 后 Switches 为 0。

这份日志仍然显示：

- `Space 1` 服务端顶层摘要：`nodes=0, switches=0, scenes=0, groups=1, schedules=0`
- `Space 1` 本地摘要：`device=0, switches=4, scenes=0, groups=1, schedules=0`
- `phase=skipped`
- `note=serverUpdateTimestampNotNewer`

因此 Site 页 Space 1 显示 4 的来源是本地 `SpaceData.switchesCount` 旧值。进入 Space 后 Switches 为 0，则来自当前 Space 加载后的真实 `MeshNetworkManager.instance.switchs.count`，说明真实开关列表已经是 0，只有 Site 卡片摘要没有刷新。

更关键的是，当前源码中的方案 C 在这种数据下不应继续输出 `note=serverUpdateTimestampNotNewer`：

- 如果本地无未上传改动，应进入 `phase=applied`，`note=serverSummaryDiffers`。
- 如果本地有未上传改动，应继续 `phase=skipped`，但 `note=serverSummaryDiffersButLocalNeedsUpload`。

所以这份日志不是运行方案 C 后的结果。最可能原因是当前 App 仍在运行旧构建；此前 iPhoneOS build 被 `EmergencyControllerMode` 缺失挡住，导致新代码尚未成功编译安装。

结论：当前问题不是方案 C 判断失败，而是现场 App 没有跑到方案 C 新代码。需要先解决编译阻塞并安装新包，再重新采集 `[PJSpaceCountProbe]`。
