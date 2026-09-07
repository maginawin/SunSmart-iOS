# 分享 Space 后 Path / Trigger Zone 丢失：根因分析与待确认修复方案

日期：2026-09-07。分析工作树：`trigger-zone-sep`，HEAD：`d51958a4`。

本轮仅分析、运行只读诊断和既有测试，不修改 App / SDK 业务代码，不操作手机、服务器或 Git 提交。

## 1. 结论与证据边界

手机 A 的初始服务器快照完整保留了 Group Path、Group Trigger Zone、Space Trigger Zone 三种逻辑配置，包括所有空条目、位置和重复出现的设备。问题发生在后续导入应用阶段：拓扑协调器接收了目标 Space 的设备列表，却通过 SDK `group.nodes` 从当前全局网络读取组成员。目标 Space 尚未成为当前网络时，成员可能为空或来自另一网络，于是合法引用被当作无效引用清理。

清理结果又被视为本地编辑，写入数据库并推进云同步时间戳。Editor 的云上传不以设备 Sync 为前提，因此可以在没有配置 L1、L2 的情况下，把空逻辑配置传回服务器。A 随后接收到服务器的新版本，就表现出相同问题。

证据分层：

- **快照事实**：三份 JSON 的完整递归对比已完成；初始配置完整，后续三处引用清空，设备数据完全不变。
- **源码事实**：当前 App 存在上述跨上下文成员读取、自动清理、标记云脏数据的完整调用链；项目锁定 SDK revision 中也确认了全局读取实现。
- **执行复现**：直接编译当前真实拓扑策略与协调算法，使用快照数据验证；错误成员集合导致的三类拓扑输出与 `editor.json` 完全一致。
- **尚未具备的现场证据**：没有 A/B 对应安装包版本、导入运行日志、具体上传请求日志与服务器写审计。因此不能把 B 当时的全局网络内容、具体哪次请求完成覆盖、是否存在其他客户端写入描述成已抓包确认。已定位的是能够完整解释本次现象且可复现的实现缺陷。

## 2. 三份快照对比

输入目录：`/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/new-calibration/tmp/`。

| 配置或状态 | owner_ok.json | editor.json | owner.json |
| --- | --- | --- | --- |
| Group | Group 1，C000 | 不变 | 不变 |
| Group Path 数量 | 32 | 32 | 32 |
| Path 1 items | `[2,5,0]` | `[0,0,0]` | `[0,0,0]` |
| 其余 31 个 Path | 每个 `[0,0,0]` | 不变 | 不变 |
| Group Zone 数量 | 32 | 32 | 32 |
| Group Zone 2 addresses | `[2,5]` | `[]` | `[]` |
| Space Zone 数量 | 32 | 32 | 32 |
| Space Zone 2 items | `(C000,2)`、`(C000,5)` | `[]` | `[]` |
| schema version | 1 | 1 | 1 |
| L1 / L2 归属 | C000，groupState=1 | 完全不变 | 完全不变 |
| L1 已观测状态 | Enabled=true，Relay=2，Neighbors=[5] | 完全不变 | 完全不变 |
| L2 已观测状态 | Enabled=true，Relay=2，Neighbors=[2] | 完全不变 | 完全不变 |
| updateTimestamp | 1788769614 | 1788770193 | 1788770193 |
| 对应 UTC+8 时间 | 16:26:54 | 16:36:33 | 16:36:33 |
| 返回 role | owner | editor | owner |

`2=0x0002=L1`，`5=0x0005=L2`，`49152=0xC000=Group 1`。Path 中 `0` 是空 Point，不是设备地址。

完整递归差异仅包括：Path 1 的两个地址置零、Group Zone 2 两个地址删除、Space Zone 2 两个成员删除、时间戳变化及 role 变化。两份后续快照之间**只有 role 不同**。所有 Node 字段、Model 订阅、Profile 和其他服务器业务字段均未改变。

用户描述 A 再次以 Editor 权限进入；但 `owner.json` 返回的 role 为 owner。这可能对应服务器身份与实际编辑使用权的不同层次，当前资料不足以进一步解释；不影响结论，因为 owner/editor 都允许上传，且两份后续业务数据完全相同。

## 3. 初始上传能否保存全部逻辑配置

可以，且 `owner_ok.json` 已经证明本次服务器保存了这些信息：

- `data.groups[0].proximityLightingPath.paths`：Path 列表、顺序、每条 Path 的 Point 顺序和空位。
- `data.groups[0].proximityLightingPath.zones`：Group Zone 列表、顺序和成员。
- `data.spaceData.triggerZones`：Space Zone 列表、顺序及各成员的 Group/Device 地址。
- `data.spaceData.proximityLightingSchemaVersion=1`：格式版本。

导出位置：`SunSmart/Common/Data/ExportData.swift:427`、`:775`。导出不会因为两个来源生成相同邻居，就删除其中一种逻辑配置。

邻居是下发设备的派生结果。Path 的相邻点、Group Zone 的互邻关系、Space Zone 的互邻关系最终合并去重。本例三种配置都生成 L1↔L2：只保留 Space Zone 2 也会得到同一个设备目标，但无法反推出另外 32 个 Path 和 32 个 Group Zone。已用真实策略验证这种多对一关系。

因此，后续修复必须保留三种逻辑配置作为数据源；不能从 Node Neighbor 缓存重建编辑页面，也不能按邻居相同来判断逻辑编辑未发生。

## 4. 手机 B 的故障链路

### 4.1 下载发生在切换目标网络之前

`SiteViewController.loadSpaceReqeust` 在 `SunSmart/Main/Site/Controller/SiteViewController.swift:1211` 请求 Space，随后先执行 `space.update(...)`，完成后才进入 Space 页面。

Site 页面本身会切回 Site 主网络，见同文件 `:236`。真正切换到目标 Space 的操作在 `SpaceViewController.setNetworkConnected()`，见 `SunSmart/Main/Space/Controller/SpaceViewController.swift:683`。因此导入时全局网络可能是 Site 主网络或之前的网络，不能假定已经是 Space 1。

此外，Site 的整体更新也逐个导入 Space，见 `SunSmart/Common/Data/ImportData.swift:763`，不会为每个导入条目切换全局网络。

### 4.2 预检可以正确，但应用阶段重新取错成员

`ProximityLightingImportPreflight.parse` 根据输入 JSON 的 `groupState`、`groupAddress` 和 Node 解码结果建立成员集合，见 `ImportData.swift:170`。本例两个 Node 均为 inGroup，归属 C000，Vendor Model 在主 Element，正确规范化地址为 2、5。

但预检结果没有直接作为最终应用的拓扑快照使用。后面重新构造：

1. `ImportData.swift:2425` 调用 `ProximityLightingLifecycleCoordinator.begin(space:groups:nodes:).prepare()`，传入新导入的 groups/nodes。
2. `ProximityLightingLifecycleCoordinator.swift:121` 的 begin 调用 `makeSnapshot(space:groups:)`，**没有把 nodes 传入成员快照构造**。nodes 仅保留到后续候选节点/同步任务阶段。
3. 同文件 `:230` 的 makeSnapshot 使用 `group.nodes` 生成 `memberAddresses`。
4. SDK 的 `Group+Nodes.swift:34` 实际读取 `MeshNetworkManager.instance.realNodes`，按 `node.group?.address == address` 筛选；既没有使用 group 自己的 network，也没有验证网络/Space 身份。

SDK 证据不是只看本地开发分支：已用 Git 对象读取项目 `Package.resolved` 锁定的 `86f5ec9e40148b9cd93e0512702337fcec41dd40` revision，其实现相同。对应路径为 `Sources/NordicSigMeshSDK/MeshLib/Group/Group+Nodes.swift`。

### 4.3 合法引用被自动清理

`ProximityLightingTopologyReconciler.normalize` 对不在 memberAddresses 中的引用执行：

- `:258` 附近：Path Point 清为 nil，导出变成 0。
- `:275` 附近：Group Zone 地址移除。
- `:313` 附近：Space Zone 成员移除。

容器保留，所以仍然是 32/32/32 个条目，只是内容空了。本例空成员集合产生恰好 6 个 repair：两个 Point、两个 Group Zone 地址、两个 Space Zone 成员。

这些操作被分类为 repair，不是 hard error。Result.isValid 只检查 hardErrors 为空；导入预检的 hasValidationIssues 也只检查 warnings/hardErrors，不包含 repairs。更关键的是，预检和应用阶段成员来源不同，缺少两次快照的一致性断言。因此保护逻辑没有发现“合法远端数据在本地应用时被改变”。

### 4.4 导入的清理被当成本地编辑上传

`ProximityLightingLifecycleCoordinator.commit` 在 `:153` 比较原始/规范化快照，在 `:170` 调用 `markLocalChangePendingCloudSync()`，再保存改写后的 GroupInfo/Space Zone。`isImportApplication=true` 仅放宽导入期间保护门禁，不会阻止推进云脏时间戳。

`SpaceViewController.swift:72`、`:129` 对 owner/editor 推进 lastUpdate；`SpaceData.swift:126` 据此判断 needUploadCloud。

云上传可由 Site 导入后的待上传检查触发（`SiteViewController.swift:626`），也可由退出 Space 等流程触发（`SpaceViewController.swift:1650`、`:1559`）。它与用户是否执行 L1/L2 的 Mesh Sync 是独立操作。

现有导出保护只检查“当前待导出数据是否还需要 repair”。导入已经把引用清完，之后合法的空列表自然能通过。上传回读校验则比较“提交数据与服务器返回是否一致”（`CloudSynchronizationManager.swift:876`），只能验证空配置成功保存，不能识别它在导入时已经被错误修改。

## 5. 为什么出现 Group 同步、Path sequence 和三处提示

进入 Space 1 后，全局网络切换正确，Group 1 又能找到 L1、L2。但此时逻辑拓扑已为空，设备观测缓存还是原来的互邻状态。

| 设备 | 当前缓存 | 空逻辑配置生成的目标 | 生成任务 |
| --- | --- | --- | --- |
| L1 | Enabled=true，Relay=2，Neighbors=[5] | Enabled=true，Relay=2，Neighbors=[] | Neighbor Set，空邻居 |
| L2 | Enabled=true，Relay=2，Neighbors=[2] | Enabled=true，Relay=2，Neighbors=[] | Neighbor Set，空邻居 |

空 Path/Zone 不会让仍属于 Proximity Group 的设备自动 Disabled。Profile 仍要求 enabled=true，Relay 仍为 2，变化的是邻居列表。

调用链：

- `Node+SyncData.swift:1621` → 真实拓扑策略 mutation，比对逻辑目标与 Node 已观测缓存。
- `Node+SyncData.swift:717` 将该差异纳入 Group needSync。
- `SyncDevicesViewController.swift:1661` 将 `.proximityLightingNeighbor` 步骤和任务统一显示为 `path_sequence`，因此名字是 **Path sequence**，实际任务会清空邻居；它并不意味着正在恢复 Path 1，也不代表远端漏传了一个设备专属 Path 字段。
- Group Path/Group Trigger Zone 共用父页同步状态，见 `GroupPathSequencePageController.swift:70`、`:172`；Space Zone 使用同一完整拓扑预览，见 `SpacePathTriggerZoneController.swift:213`。所以多个入口同时提示不一致。

本次用户没有执行设备 Sync，后续快照的全部 Node 数据也没有变化；这与“仅逻辑配置被覆盖”的解释一致。快照是 App 的设备观测记录，不等同于现场重新读取的设备状态；本轮未进行 BLE 操作。

## 6. 为什么 A 再次进入也异常

服务器版本从 1788769614 增加到 1788770193。`ImportData.swift:1686` 的更新规则会在远端较新、初始化或恢复等情况下应用服务器数据。A 原有的完整 GroupInfo/Space Zone 被新版本中的显式空数组覆盖。

此后 A 的逻辑目标也是空邻居，Node 缓存仍然为互邻，于是产生同样的同步任务。`owner.json` 与 `editor.json` 除 role 外完全相同且时间戳相同，说明无需假设 A 又单独制造了一次新清理，即可解释最后的现象。

当前 schema=1 的显式空配置本身也可能来自用户合法删除。不能仅凭“空配置+非空设备缓存”自动判断损坏并回滚，否则会撤销合法的离线编辑。

## 7. 其他同类问题及风险分级

| 场景 | 当前实现风险 | 证据程度 |
| --- | --- | --- |
| 新 Editor、重新登录、首次导入、从 Site 页进入非当前 Space | 读取全局空成员，三类引用被清理并可能上传 | 源码链路确认，策略复现 |
| Site 批量导入多个 Space | 所有导入共享当前网络，结果依赖 UI 所在位置 | 同一实际调用链确认 |
| 另一个 Space 恰有相同 Group 地址 | group.nodes 只比 Group 地址；成员不重合则全清，部分重合则部分清；偶然完全重合会掩盖缺陷 | 源码确认，部分重合策略复现 |
| 非当前 Space 导出/批量导出 | ExportData 虽从目标数据库加载 nodes，校验仍由 group.nodes 取全局成员；通常误判 repairs 并拒绝有效导出 | 当前保护逻辑确认；本轮未跑完整 App 导出 |
| 非当前网络生成拓扑同步任务 | Planner.makeGroupSnapshot 同样调用 group.nodes；可能生成错误空目标，缺少 target 时可生成 Disable | 源码风险确认，本次未观测执行 Disable |
| 导入的悬空引用、成员异常或旧格式迁移 | destructive repairs 与正常清理未分离，可能被当作本地编辑 | 共享策略确认；应按来源区分语义 |
| 更新非当前 Space 摘要 | markLocalChangePendingCloudSync 内 refreshSummaryCountsFromCurrentMesh 读取全局网络，可能错写设备/组等统计 | 源码确认，本次三份快照统计未变 |
| 自动展示导入修复同步任务 | 导入结束发通知，Space 页可能使用先前生成的任务并自动启动；需检查目标 Space/版本有效性，防止错误任务传播到设备 | 源码潜在风险，本次无证据说明已触发 |

`reconcileLegacyProximityLightingTopology()` 在每次 Space 网络加载后都会执行，并没有只针对 legacy schema。其使用隐式当前上下文，也需要完整性/作用域保护；不能把未知成员当作用户已删除成员。

现有配置备份、事务和上传回读解决的是存储失败或传输一致性，不会自动识别“成功写入了错误业务内容”。导入完成时目前主要验证 Group 地址集合、Node 是否可读回，未验证三类逻辑配置与输入一致，是本次防线缺口。

服务器并发覆盖、旧 App 兼容属于仍需验收的系统边界，三份快照不足以认定本次是服务器并发冲突或服务器丢字段。当前无须先扩展协议或改服务器才能修复已定位的 App 缺陷。

## 8. 建议修复方案（待用户确认）

### P0：统一目标 Space 上下文，阻止合法导入被改写

1. 建立显式拓扑输入，包含目标 Space/网络身份、完整 Groups/Nodes、Group Path/Zone、Space Zones 与成员映射；生命周期协调器和 Planner 共享该输入。显式传入 nodes 的入口必须实际用于成员解析，不能退回 group.nodes 或当前单例。
2. 以目标快照的归属、groupState、Model 订阅建立并交叉校验成员映射；处理 Vendor Element 地址规范化、exitFailure、缺失/冲突归属与多 Group 异常。在线编辑只在边界捕获当前 Space 的完整快照，核心算法不依赖全局对象。
3. 预检、应用、读回和同步任务使用同一份已验证的导入拓扑，或进行严格一致性比对；避免预检正确、应用重新计算错误。
4. 区分操作来源：正常权威导入只更新服务器基线，不创建本地编辑时间戳；用户编辑与明确生命周期删除才创建待上传变更。
5. 对导入产生的引用删除、Profile 清空等 destructive repairs，不自动提交或上传：有完整本地快照时保留；首次导入时保存原始输入并按现有保护机制隔离不可验证配置。无害且等价的重复项规范化应与实际删除分开定义。
6. 提交后验证完整逻辑配置：Path/Zone 数量、顺序、空位、成员、归属、Profile 等与已验证输入一致，再解除导入保护、确认基线、生成任务。失败时保留恢复信息，禁止以错误配置继续上传或下发。

### P1：修复同源路径与回归防线

1. 非当前 Space 导出、批量 Site 导入/导出、离线任务预览全部采用相同作用域的成员数据；不要仅调整入口调用顺序，也不要靠临时切换全局网络修补。
2. 云脏标记与摘要刷新分离，摘要使用目标快照计算，不能读取另一个 Space 的当前全局列表。
3. 导入修复任务在展示/发送前验证 Space/网络身份与配置版本；上下文不一致时重新生成，不消费旧任务。保留现有用户 SAVE 的同步行为，限制修改范围。
4. 优先在 App 内修复明确上下文接口，不全局改变 SDK `Group.nodes` 的行为，以减少其他业务风险。若实施时确需 SDK 修改，再在现有 `one-dev` 路径审查并验证全部引用 target。
5. `Path sequence` 是共享 Neighbor 任务的命名歧义。功能根因修复不依赖改名；若一并改名，优先用已有通用邻近照明本地化 Key，并同步检查英文/简体中文及品牌 target。

### 恢复本次数据

修复程序不能从邻居自动重建已丢失配置。`owner_ok.json` 可作为本次明确的恢复依据；确认修复及恢复范围后，先读取最新服务器数据，核对成员/设备身份与是否有后续合法编辑，只恢复本次三类逻辑配置，再做双端回读验证。

不能整体回滚 Mesh 数据库或无差别重导旧 JSON，以免回退序列号、地址资源、密钥或后来配置。本轮不执行服务器恢复；如果设备状态仍与原始逻辑配置相符，恢复后应无需新的邻居配置任务，最终以设备回读为准。

## 9. 回归与验收计划

| 验证层次 | 必须覆盖的场景 / 判定 |
| --- | --- |
| 真实导入集成 | 当前网络为空、Site 主网、另一 Space、目标 Space 四种情况导入同一完整快照，结果完全一致 |
| 地址碰撞 | 两 Space 的 C000 相同，Node 地址无重合/部分重合/全部重合，目标配置不受另一 Space 影响 |
| 无损往返 | 32 Path + 32 Group Zone + 32 Space Zone；空位、空条目、重复设备跨 Path/Zone、不同 Point 顺序全部保留 |
| 逻辑与派生结果分离 | 仅新增/改变某个重复拓扑来源但邻居不变，仍持久化/上传逻辑编辑，且不产生多余 Mesh 任务 |
| 导入无副作用 | 合法远端快照导入不推进本地编辑时间戳、不触发意外云回写，Node 缓存正确时不出现 Path sequence 任务 |
| 生命周期 | 真正移除成员、Profile 降级、删除 Group/Device、地址迁移仍执行应有清理与对端同步 |
| 异常数据 | 字段缺失/null/显式空数组、legacy/schema=1/未知版本、成员冲突、容量超限，保护行为符合定义 |
| 持久化与重入 | 原始输入与持久化逻辑快照一致；中断重启/待恢复导入不重复清空、不误标新编辑 |
| 导出 | 非当前 Space 和多 Space 导出，与目标数据库语义相同，不依赖打开哪个页面 |
| 多 target | 按项目要求直接运行 generic iPhoneOS xcodebuild，覆盖所有受影响品牌，不使用 Simulator |
| 双手机真实流程 | A 配置并回读服务器 → B Editor 进入且不 Sync/不 SAVE → B 退出/重启 → A 重新进入；三类配置全保留，服务器无意外清空，两端无异常任务 |

若修改任务文案或页面交互，还需实际设备布局和完整交互测试；源码检查和编译不代替 UI 验收。

## 10. 本轮验证结果

- 完整递归 JSON 对比已完成，差异见第 2 节。
- 临时探针 `/tmp/proximity_snapshot_probe.swift` 直接编译当前 `ProximityLightingTopologyPolicy.swift`、`ProximityLightingTopologyReconciler.swift`，未复制或修改业务算法。
- 正确成员输入：32/32/32 配置完整；0 repairs、0 hardErrors；两台设备 0 邻近照明任务。
- 空成员输入：6 repairs、0 hardErrors；三类拓扑与 editor.json 精确一致。
- 返回正确成员上下文后：两台设备均生成 Relay=2、Neighbors=[] 的 Neighbor Set 任务。
- 部分重合成员输入：仅保留 L1，3 处 L2 引用删除，证实部分丢失风险。
- 只保留 Space Zone 2 与三种配置同时存在时，设备目标相同，验证邻居不可逆推完整逻辑。
- `bash scripts/check_path_topology_persistence.sh` 的 7 组检查全部通过。现有契约主要检查源码连接点，纯策略测试显式提供正确成员，未覆盖实际导入与全局网络不同的集成场景。
- 未运行 iOS 构建（本轮没有业务代码修改），未验证安装包/真实设备/实时服务器链路。

待确认：按 P0+P1 实施本次根因及同源路径修复，并补充真实导入上下文回归；本次配置恢复在修复后单独核对最新数据再执行。
