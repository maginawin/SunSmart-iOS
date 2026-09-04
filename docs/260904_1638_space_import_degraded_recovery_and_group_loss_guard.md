# Space 导入降级恢复与 Group 丢失保护

## 结论

本次进入失败不是 `spaceData` 或 `triggerZones` 本身无法解码，而是服务器的核心 Group/Node 引用已经不一致：服务器 `groups` 中缺少 Group 1（C000），但原 Group 1 的四个 Node 仍声明 `groupState = 1`，同时 `groupAddress` 已变为空字符串。schema v1 预检原先把这类引用异常直接升级为整个 Space 导入失败，因此用户无法进入。

由于恰好只有地址 C000 的 Group 及其 Node 引用一起丢失，而 C007、C00A 保持正常，当前应优先调查服务端是否把 C000 对应的首个 Group/偏移值 0 错当成“无值”。另一种可能是某台客户端先形成了缺少 Group 1 的本地快照再全量上传。仅凭当前 GET 响应不能在两者之间作最终定论，需要最新一次同步请求体与服务端落库结果进行前后对照。

该策略已经调整：Proximity 扩展校验不再决定整个 Space 是否可访问，并增加不完整全量快照的上传保护。

## 证据

### 当前服务器响应

- HTTP 与业务状态均成功。
- `spaceData.proximityLightingSchemaVersion = 1`。
- `spaceData.triggerZones` 可解码，共 25 个 Zone；当前非空 Zone 中的 Group 2、Group 3 引用能够对应 C007、C00A。
- 非虚拟 Group 只剩：
  - Group 2：C007
  - Group 3：C00A
- 以下 Node 仍为 `groupState = 1`，但 `groupAddress` 为空：
  - 008C
  - 008F
  - 0099
  - 009C
- 这些 Node 的 Model Subscription 中仍存在 C000，符合“Group 对象被删除、设备订阅/状态残留”的特征。

### 与旧快照比较

`/Users/maginawin/Downloads/temp/get spaceprops.txt` 中：

- `updateTimestamp = 1788501097`。
- Group 1（C000）、Group 2（C007）、Group 3（C00A）均存在。
- 008C、008F、0099、009C 的 `groupAddress` 都是 C000。

当前用户提供的服务器响应中：

- `updateTimestamp = 1788510411`。
- Group 1 已不存在。
- 上述四个 Node 的 `groupAddress` 已为空。

因此 Group 1 在当前进入请求之前已经从服务器快照中消失。本次日志只有 `/get/spaceprops`，且 App 在预检阶段返回，没有执行本地替换；本次失败不是删除 Group 1 的动作。要确定丢失发生在客户端导出还是服务端转换/落库，需要取得 `updateTimestamp = 1788510411` 前后的 `/sync/siteprops` 或 `/sync/spaceprops` 请求体：

- 如果请求体包含 Group C000，且四个 Node 的 `groupAddress` 也是 C000，则是服务端同步/存储/返回链路丢失 C000。
- 如果请求体已经缺少 Group C000，且四个 Node 的 `groupAddress` 已为空，则是不完整客户端快照覆盖服务器。

## 原失败位置

schema v1 预检要求每个 `groupState = inGroup` 的 Node 同时满足：

1. `groupAddress` 存在且可解析；
2. 该地址存在于服务器返回的非虚拟 Group 集合；
3. Node 可完整解码以计算 Proximity 地址。

当前四个 Node 在第 1 条失败，旧实现直接返回 `invalidProximityLightingPayload`，Site 页面随后显示 `proximity lighting data is invalid and was not imported` 并拒绝进入。

## 修复策略

### 有可用本地快照

- 将缺失/错误的 Node Group 引用记录为诊断 warning，不再直接拒绝整个 Space。
- 若服务器 Proximity/Group 引用存在 warning 或 hard error，保留当前本地 Mesh、Node、Group、Profile、Path 与 Trigger Zone。
- 返回 skipped 而不是 rejected，因此用户仍可进入 Space。
- 不更新本地服务器时间戳，也不执行破坏性 Node/Group 全量替换。

如果本机数据库里仍有 Group 1，新版本进入后应重新显示它。

### 没有可用本地快照

- 尽力导入所有可解码的 Space、Node、Group、Path 和 Trigger Zone 数据，保证项目仍可访问。
- 不执行 Proximity 自动归一化、自动修复或 Mesh 收敛任务，避免基于不完整引用继续改设备。
- 无法从残留订阅安全重建服务器已丢失的 Group 名称、Profile、Path 等业务数据。

### 上传保护

Space 全量导出前新增 Group 完整性检查：

- 如果 Node 仍是 `inGroup`，但不能解析到本次将导出的非虚拟 Group，导出返回失败。
- 不调用 `/sync/siteprops` 或 `/sync/spaceprops` 上传该不完整快照。
- 日志打印 `[SpaceSnapshotExport] rejected orphanedGroupMembership` 及对应 Node 地址。

这可以阻止“Group 对象缺失，但 Node 状态仍在”的本地快照再次覆盖服务器。

## 验证

- Proximity Lighting topology policy：通过。
- Proximity Lighting lifecycle policy：通过，新增 authoritative、preserve local、best-effort 三种导入策略测试。
- Path/Trigger Zone persistence、follow-up、integration、review regression：全部通过。
- Scheduler owner、unknown、read-before-delete、缓存持久化：全部通过。
- `git diff --check`：通过。
- Debug generic iPhoneOS 构建：SunSmart、Archipelago、SLG Sync Plus、SylSmart 全部通过。
- Lumineux 仍受现有 `Pods-Common-Lumineux` target support 文件缺失影响，本次未重复执行。

## 设备复验与恢复顺序

1. 不要卸载 App 或删除该 Space，避免清除可能仍含 Group 1 的本地数据库。
2. 覆盖安装新构建后进入 Space。
3. 预期不再出现 Proximity 导入失败提示，并能进入 Space。
4. 查看日志是否出现四个 `missingNodeGroupAddress` warning 和 `preserved local snapshot`。
5. 检查 Group 1、其 Profile、32 个 Path、32 个 Group Trigger Zone，以及 25 个 Space Trigger Zone 是否仍在本地。
6. 在确认本地 Group 1 完整前，不执行会触发云端全量上传的编辑或同步操作。
7. 如果本地 Group 1 完整，再规划一次受控的三 Group 快照回写以恢复服务器。
8. 如果本地 Group 1 也不存在，应从旧的完整服务器快照或服务端历史版本恢复；不要仅依据 C000 订阅创建一个默认 Group。
