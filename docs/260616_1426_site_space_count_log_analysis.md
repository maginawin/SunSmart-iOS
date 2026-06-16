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
