# 创建 Site 后列表误显示需要同步的原因分析

日期：2026-11-06

工作树：`feat-daylight-saving-261024`；分支：`feat/daylight-saving-261024`；当前版本：`59be4df7`。

## 1. 结论

**11:51 的 Site 13 新样本补充：上一轮修复仍遗漏“创建 Site 后新增 Space”的完整路径。新增 Space 只抬高页面中 Site 的修改时间，没有保存；单 Site 刷新的新版本保护因此拒绝应用已保存的成功结果。已通过当前代码和临时 SQLite 复现，并按用户确认完成补充修复；真实手机仍待验收。原因见第 11 节，实施记录见第 12 节。**

修复前存在一个可以复现的列表状态更新缺陷：**上传已经成功，手机里保存的状态也正确，但 Sites 列表仍使用创建时的旧 Site 对象。** 上传完成后的回调只重新显示这一行，没有把列表使用的数据更新成已上传的状态。因此，同步任务结束后，旧对象又被判断为“需要同步”。

下拉刷新会重新读取 Site 数据并替换列表里的旧对象，所以标记消失。这与用户提供的日志、服务器数据和 App 导出数据相符。

已按用户确认的“单 Site 本地状态更新＋收藏写入保护”完成修复，相关自动检查和 SunSmart 构建通过。修复记录见第 10 节；真实手机页面尚未验收。原始日志没有打印列表对象的上传时间，不能直接还原现场每次画面刷新的时刻，但已定位到足以解释本次现象的确定代码路径。

## 2. 三份文件提供的证据

输入文件：

- [服务器 Site 资料](</Users/maginawin/Desktop/get siteprops from server.txt>)
- [创建 Site 的 Xcode 日志](</Users/maginawin/Desktop/create site xcode logs.txt>)
- [App 导出的 Site 文件](</Users/maginawin/Downloads/Site_Site 12_20261106_103933_109+0800.json>)

三份文件对应同一个 `Site 12`。文档只记录定位问题所需信息，不复制网络密钥或完整原始资料。

### 2.1 创建请求确实成功

创建日志第 17～47 行记录：

- 操作是 `syncSite`，使用 `siteAdd`，提交到 `/sitespace/sync/siteprops`。
- `syncSpaceCount=0`，本次没有附带 Space 上传。
- 网络返回 `status=200`，业务返回 `businessCode=200`。
- 返回了创建 Site 所分配的地址数量。
- App 随后记录 `[CloudSync][Success]`。

这里不只依赖请求成功提示：下面的本地保存内容和服务器实际资料也确认了这次结果。

### 2.2 导出时手机里的状态已经是“无需上传”

导出记录时间为 `2026-11-06T02:39:33Z`，即该文件名所用的 UTC+8 时间 10:39:33。`_debugInspection.rawSite.sites[0]` 中：

| 内容 | 实际值 | 含义 |
| --- | --- | --- |
| `lastUpdateTimestamp` | `1793932740` | 最近修改时间 |
| `lastUploadCloudTimestamp` | `1793932740` | 已确认上传的时间，与最近修改时间相同 |
| `pendingSitePropsMask` | `0` | 没有待上传的编辑项 |
| `pendingSitePropsTimestamp` | `null` | 没有待上传的编辑时间 |
| `syncCloudError` | `null` | 没有记录上传错误 |
| `permission` | `1` | 所有者 |
| `state` | `1` | 正常 Site |

当前 App 的判断是：最近修改时间大于最近上传时间，且不是访客，才需要上传。按这份保存数据计算，结果应当为“不需要上传”。

导出文件中的 `_debugInspection.uploadable=false` 是这类检查文件固定带的标记，表示它用于查看本地资料；**不是这个 Site 尚未上传，也不是上传失败。** `DebugCloudJSONExporter.swift` 创建这段说明时直接设置了此值。

### 2.3 服务器和本地的业务内容一致

逐项比对导出的 `site` 与服务器的 `data`，以下 19 项一致：名称、Site 标识、图标、类型、来源、创建时间、更新时间、纬度、经度、地址、国家、时区、描述、城市、城市编号、邮编、Site 扩展内容、Space 列表、排除记录。

其中国家为 `CN`，时区为 `Asia/Shanghai`；城市及城市编号都为空，双方一致。当前创建流程允许不选择城市，列表的同步标记也不通过“是否填写城市”判断，因此城市为空不能解释这个标记。

本次 Site 没有 Space，服务器也没有网关，因此不能把这个图标解释成下属 Space 上传失败或网关时区尚未更新。

## 3. 代码中的完整触发过程

用“旧对象 A”和“新对象 B”区分内存中的两份 Site。它们的 Site 标识相同，但不是同一个对象，修改 B 不会自动改变 A。

### 第一步：列表保存创建时的对象 A

`SitesViewController.showCreatedSite` 把刚创建的 Site 放入 `allSites`，并把它交给 Site 详情页和上传队列。

此时还没完成上传，A 的最近上传时间为空。如果有时区，创建流程还会把时区记为待上传。

对应位置：

- `SunSmart/Main/Site/Controller/SitesViewController.swift:660`。
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:49`。

### 第二步：开始上传时换成新对象 B

`CloudSynchronizationHandle.syncOperation()` 在真正开始上传前调用 `SiteData.load(siteId:)`，然后把任务中的 Site 替换为刚读取的对象。

`SiteData.load` 是根据保存记录重新创建一个 `SiteData`，不会返回列表中的原对象。因此从这里开始：列表持有 A，上传任务持有 B。

对应位置：

- `SunSmart/Common/Cloud/CloudSynchronizationManager.swift:1357`。
- `SunSmart/Common/Data/Database.swift:335`，新对象在第 342 行创建。

这段“开始上传前重新读取”的逻辑由 `bc125d6b`（2026-11-05，`fix: don't get and sync space after every tasks`）引入。它使此前可能依靠共享同一对象自动更新的列表路径不再成立。重新读取最新数据本身有必要，不建议为了图标恢复而直接删掉它。

### 第三步：成功结果更新 B 和手机保存记录，A 没有变化

`confirmSiteUpload` 更新任务所持对象 B 的上传时间，清除已确认的时区待上传状态，再保存到手机。

这与导出文件中上传时间已确认、待上传标记为 0 完全相符。但列表中的 A 仍可以是“最近上传时间为空”。

对应位置：`SunSmart/Common/Cloud/CloudSynchronizationManager.swift:1293`。

### 第四步：列表成功回调只重画，没有更新数据

`SitesViewController.cloudSyncManager(...didSyncFinished:)` 收到任务中的 B 后调用 `reloadSiteData(B)`。

但 `reloadSiteData` 只拿 Site 标识去查找行号，再执行 `reloadItems` 或 `reloadData`，没有读取最新保存记录，也没有更新 `allSites`、`favouriteSites` 中的对象。

真正显示这一行时，又从 `allSites` 或 `favouriteSites` 取出了 A，所以仍按旧状态显示。

对应位置：

- 成功回调：`SitesViewController.swift:1464`。
- 只重画列表：`SitesViewController.swift:1078`。
- 从列表数组取值并判断图标：`SitesViewController.swift:1296`、`:1333`。

### 第五步：任务消失后，旧对象触发“未知同步错误”

`SiteData.showSyncCloudError` 不仅在真实上传失败时显示图标，还会在以下两个条件同时成立时返回一个未知错误：

1. 这个内存对象认为自己仍需上传。
2. 当前队列里已经没有对应的同步任务。

上传完成后，管理器正常删除任务。A 的上传时间仍为空，于是满足上述条件。即使它没有记录任何实际网络错误，也会显示同步图标。

还有一个时序细节：管理器先通知成功，再移除任务。如果重画恰好发生在任务移除前，图标可能暂时隐藏；任务移除后的下一次重画又会显示。UIKit 实际何时重新取数也会影响看到图标的时机，所以表现会显得不稳定。

对应位置：

- 判断规则：`SunSmart/Common/Data/SiteData.swift:177`、`:193`。
- 成功通知与移除任务的顺序：`CloudSynchronizationManager.swift:753`。

## 4. 为什么下拉刷新或部分其他操作后好了

下拉刷新成功后，`loadSitesRequest()` 会执行 `setupData()`；后者调用 `SiteData.loadAll()`，重新构造 `allSites` 和 `favouriteSites`。

这次使用的对象读到了已确认上传的时间：`1793932740 == 1793932740`，因此不再需要上传，图标消失。**不是必须再成功上传一次才能消失，而是列表终于读取了已经保存的正确状态。**

其他操作只要触发重新读取保存数据或更新当前页面所持 Site 对象，也可能恢复。单纯返回列表、滚动或调用 `reloadData()` 不保证恢复，因为它们可能仍使用原来的数组。

返回列表还有一条需要覆盖的路径：同步管理器只有一个当前页面回调接收者，Site 详情页和 Sites 列表会在各自出现时接管。上传在详情页完成时，列表不一定收到成功通知；返回列表默认走 `.list` 分支，也只重画而不重新读取。这不是本次唯一根因，但修复时不能只补“列表收到成功通知”这一种情况。

对应位置：

- 下拉刷新后读取数据：`SitesViewController.swift:379`。
- `setupData`：`SitesViewController.swift:224`。
- 返回页面默认只重画：`SitesViewController.swift:130`。
- 详情页接管同步回调：`SiteViewController.swift:231`。

## 5. 最小行为复现

在临时目录建立独立 Swift 检查程序，没有修改仓库业务代码或增加测试工程。

复用了当前生产代码中的：

- `showSyncCloudError`、`needUploadCloud` 判断。
- 上传开始时重新读取并替换 Site 的代码段。
- 完整的 `reloadSiteData` 和 `setupData` 方法。
- `SitePropsEditPolicy.localStateAfterSuccessfulInitialSiteUpload` 的实际确认规则。

检查程序使用简化的存储和列表显示替身，重放“对象 A → 任务重新读取对象 B → 上传确认 → 成功回调 → 移除任务 → 再次显示 → 重新读取”的顺序。确认了：

1. 上传确认后，已保存状态不再需要上传，但 A 的上传时间仍为空。
2. 成功回调没有替换 A；任务移除后再显示，错误图标条件成立。
3. 收藏列表存在同样的旧对象问题。
4. 执行 `setupData` 后，图标条件消失，不需要再次上传。

运行结果：

```text
REPRODUCED: success callback redraws old object; after task removal next redraw shows stale warning.
REPRODUCED: favourites also retain old object after reloadSiteData.
VERIFIED: setupData reloads saved state and clears warning without another upload.
```

临时检查程序：`/var/folders/y1/phq8m2pd29jf7bwfcmq1j9j80000gn/T/site-list-stale-analysis-gdy25ixv/Probe.swift`。

验证边界：此程序证明对象分离和列表状态判断的行为，不覆盖真实 SQLite 保存、HTTP 请求、UIKit 重画时机或真机导航。真实保存及服务器结果由本次提供的文件佐证；现场逐帧显示仍需人工重现。没有把本次检查视为完整 App 验收。

## 6. 修复方案比较（已确认方案 A）

**推荐：创建时只上传新 Site；任务状态变化后，只从手机保存记录读取这个 Site，更新它在页面中的状态。新增网络请求为 0。**

“同步全部 Site”和“刷新列表显示”是两件不同的事。当前 `showCreatedSite` 已经只提交 `.syncSite(site: site)`，默认附带 Space 为空。本次无需改变上传目标，也无需为了消除图标再次上传或读取服务器上的 Site 详情。

| 方案 | 具体做法 | 优点 | 缺点与适用范围 |
| --- | --- | --- | --- |
| A：单 Site 本地更新，推荐 | 保留现有创建上传；完成后读取这个 Site 的最新本地记录，更新全部列表及收藏列表中对应的对象和行 | 无新增网络请求；不读取其他 Site；离线结果也能更新；不会因修复图标而上传无关 Site | 要处理页面离开、回调晚到、收藏列表及旧对象保存，不能只调用一次重画 |
| B：重新读取全部本地 Site | 上传完成或返回列表时执行 `setupData()` | 可以清除旧列表对象；实现较直接；不增加网络请求 | `loadAll()` 会重建全部 Site 并加载其 Space，成本随数据量增加；刷新范围超出当前问题；替换列表对象仍不能自动更新详情页原先持有的对象 |
| C：重新拉取服务器列表并检查待上传 Site | 上传完成后调用 `loadSitesRequest()` | 同时取得其他 Site 的服务器变化 | 增加网络等待；断网时不能依靠它纠正显示；当前流程还会为列表中其他待上传 Site 排队上传。把一次创建与全部 Site 的加载、上传关联起来，没有必要 |

用户已确认选择 A，按下面的范围实施。

本次不会改变用户主动下拉刷新、原有启动加载及网络恢复后的补传规则；这些流程可能处理其他确实有待上传内容的 Site。约束是：**不能因为创建 Site A 或纠正 A 的图标，额外发起 Site B 的上传或下载。**

## 7. 推荐方案 A 的具体开发范围

### 7.1 只读取目标 Site 的已保存状态

在现有 Site 数据读取方式上增加或复用一个单 Site 的轻量更新入口：

- 按账号上下文、服务器地区、Site 标识和创建身份匹配目标，确认仍是同一个 Site；切换账号、服务器地区或 Site 已删除时，不应用较早的结果。
- 只查询该 Site 的记录，不调用 `SiteData.loadAll()`，不加载所有 Sites，也不为了显示更新读取该 Site 下的 Mesh/Space 配置。
- 读取名称、图标、位置与时区、修改时间、上传确认时间、待上传编辑项、上传错误及必要的权限、状态、收藏信息，使页面持有的 Site 信息保持一致。
- 从最新保存记录读取结果，不能把上传任务里的旧内容直接覆盖到页面；如果页面对象确实持有更晚的修改，不用较早版本将它覆盖或标为已上传。
- 更新现有 Site 对象中的已保存资料，不整体替换 `spaces`、网关在线信息、Mesh 对象或正在编辑的独立草稿。
- 读取或校验失败时不强行隐藏图标，不回退到请求全部 Site，也不触发额外上传；保留当前内容，由后续正常重试或重新进入恢复。

现有 `persistedPropsState()` 已能只读 Site 属性，但缺少图标判断所需的上传错误和完整身份检查，不能直接作为全部解决方案。实现时沿用它的单记录查询方式，补齐本次所需数据，不另建缓存中心或持久化状态。

### 7.2 创建任务完成后，不依赖“当前在哪个页面”

复用 `addSynchronizationHandle(..., result:)` 已有的每任务回调，为本次创建任务增加独立处理：

1. 开始、成功、失败、取消时，只安排这个 Site 的本地状态更新。
2. 结束状态的处理放到当前同步回调结束后的主线程执行，使已结束任务先从队列移除，再根据最新保存状态和仍在运行的其他任务计算图标。
3. 回调只弱引用页面，保存用于匹配的账号、地区和 Site 身份，避免页面已销毁后仍持有它。
4. 即使列表当前不可见，也更新列表所持目标 Site 的数据；页面可见时刷新对应行，不可见时不操作屏幕上的行，返回后由原来的显示流程呈现最新数据。
5. 同一个 Site 在全部列表、收藏列表及创建后打开的详情页可能共享对象，更新这些实际持有的目标对象；不会只改一个临时副本。对同一个对象重复命中的更新进行合并，避免重复读取和重画。

这条回调不依赖 `CloudSynchronizationManager.delegate` 当前属于哪个页面，正好覆盖“上传在详情页完成，列表没有收到成功通知”的情况。无需新增全局通知、页面间的持久化刷新标记或每次返回时遍历所有 Site。

### 7.3 修正已有的单 Site 刷新入口

- `SitesViewController.reloadSiteData` 改为先更新目标 Site 数据，再更新对应行；不再仅依靠 Site 标识查行号后重画。
- 全部列表和收藏列表里的同一 Site 都要更新数据，不能仅更新当前可见的一个列表；行位置按各自真实分组计算。
- 普通状态变化只重画目标行。收藏归属、权限分组发生变化时，才更新有关分组和空态；即便需要重画列表布局，也不代表重新读取或同步所有 Site。
- Site 详情页的同类同步回调复用单 Site 更新入口，更新其实际持有的对象；成功、失败及取消都按真实保存状态处理。创建任务回调与现有页面回调重合时合并同一目标的更新。
- Site 详情重新出现时可校准当前这个 Site 的本地状态，不把“返回页面”改成拉取全部服务器列表。列表重建或 App 重启时，继续使用现有首次加载流程。

### 7.4 防止收藏操作把旧上传状态写回

当前收藏回调对列表持有的 `site` 调用完整 `save()`；如果对象过旧，收藏时会一并写入旧的上传时间等内容。只修正显示仍可能留下这条写回路径。

建议将 Site 收藏操作改为：按当前账号、地区及 Site 身份校验，只更新现有的 `favourite` 列，成功后更新对应页面对象和收藏列表。失败时恢复按钮与列表状态，复用已有错误提示；不写名称、位置、时区、上传时间等无关内容，也不发网络请求。

该调整属于当前问题的直接后续操作保护，不修改 Space 收藏，不批量改写通用保存流程。

### 7.5 保留已有上传保护

- 保留 `syncOperation()` 上传前读取最新 Site 的逻辑。
- 保留 `confirmSiteUpload` 只确认本次实际上传版本的规则。
- 不通过“成功后清空所有待上传标记”解决显示问题；上传中新增的编辑、真正失败和取消后的待上传内容必须继续保留。
- 不改变现有正常上传的等待时间、重试规则、请求地址或网络内容。
- 不改变 `showSyncCloudError` 对真实待上传状态的判断，不在界面里直接把图标设为隐藏。

## 8. 文件范围、实施步骤和验收

### 8.1 预计修改文件

| 文件 | 修改目的 |
| --- | --- |
| `SunSmart/Common/Data/Database.swift` | 单 Site 轻量读取所需内容；只更新目标 Site 的收藏字段；复用现有数据库连接与事务方式 |
| `SunSmart/Common/Data/SiteData.swift` | 应用目标 Site 最新已保存资料的共享逻辑，保留页面正在使用的 Space、网关等对象 |
| `SunSmart/Main/Site/Controller/SitesViewController.swift` | 创建任务独立回调、目标 Site 数据刷新、全部与收藏对应行刷新、收藏保存入口 |
| `SunSmart/Main/Site/Controller/SiteViewController.swift` | 当前 Site 的同类结果刷新及重新出现时的本地校准 |
| `SunSmart/Common/Cloud/CloudSynchronizationManager.swift` | 保存成功回执前保留最新收藏值，不改变网络、队列和重试规则 |
| `Tests/Site/SiteStandardPropsPersistenceTests.swift` | 真实保存、重载、较早上传完成及收藏写入的行为检查 |
| `Tests/Site/SitesListSyncStateTests.swift`（必要时新增） | 页面只重画但数据未更新、完成回调跨页面、两个列表对应行等行为检查 |
| `scripts/check_site_hdb_persistence.py` | 接入上述检查，继续复用已有临时 SQLite 测试方式 |

同步管理器仅增加成功回执保存前的收藏值保留；没有修改网络逻辑、队列或回调语义。

### 8.2 实施顺序

- [x] 固定当前版本下的失败复现：保存已经确认上传，列表仍持有旧对象；验证旧代码在目标断言处失败。
- [x] 实现单 Site 本地状态读取与应用，以及只保存收藏字段；用真实临时 SQLite 验证记录不会被旧对象写坏。
- [x] 接入创建任务独立回调及列表、详情的目标刷新；用页面替身验证实际数据对象已更新，不能只断言刷新函数被调用。
- [x] 验证正常、失败、重试、取消、离开页面、较早回调和账号切换；核对 Site B 没有被读取、保存或增加上传任务。
- [x] 运行相关已有回归，再构建一次 SunSmart 的 Debug generic iOS；完成后停止重复验证，交付最短真机操作步骤。

### 8.3 必须覆盖的行为

以下保留为真实 App 验收项，尚未勾选；已完成的自动检查范围见第 10 节。

- [ ] 创建 Site A 后立即返回列表，上传成功后自动恢复图标，不下拉刷新。
- [ ] 留在 Site A 详情直到上传成功，再返回列表，图标正确。
- [ ] 全部列表及收藏列表中的 A 一致；滚动或切换列表不会让标记重新出现。
- [ ] 同时存在 Site B 时，A 的状态更新不读取 B 的保存资料，不改变 B 的内存数据，也不发起 B 的网络任务。
- [ ] 真实上传失败仍提示失败；恢复网络后沿原流程重试，成功后清除正确版本的提示。
- [ ] 取消且仍有待上传内容时显示待处理；若已确认保存成功后才收到较早的取消通知，则读取当前状态，不改回失败。
- [ ] 上传版本 1 期间保存了版本 2；版本 1 完成后，版本 2 仍保持待上传。
- [ ] 页面销毁、账号或服务器地区变化、目标 Site 删除后，旧回调不更新其他内容、不使 Site 重新出现。
- [ ] 对旧 Site 对象操作收藏，只修改收藏字段，不回写旧名称、时区、修改时间或上传时间；保存失败时按钮恢复。
- [ ] 单 Site 本地读取失败时不显示虚假的成功，也不增加全量网络刷新。
- [ ] 详情页已有的 Space 对象和网关在线信息不因本次更新被替换或丢失。

### 8.4 自动检查与构建边界

本次已运行：

- `python3 scripts/check_site_hdb_persistence.py /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`：保存与重载、较早上传完成、收藏字段保护及新增目标刷新检查。
- `bash scripts/check_site_props.sh`：编辑状态、上传版本确认等相关已有回归。
- `git diff --check`。
- 一次 SunSmart Debug generic iOS 构建：使用 `SunSmartLocal.xcworkspace`、scheme `SunSmart`、`-sdk iphoneos`、`-destination 'generic/platform=iOS'`、`CODE_SIGNING_ALLOWED=NO`，DerivedData 使用本工作树独立目录。

本次规划已确认本地 workspace 存在，SDK 实际路径为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；实施构建前再核对是否变化。不会修改 SDK。

这是共享 App 逻辑，品牌影响覆盖 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux；预计没有品牌差异路径、资源或工程归属变化，因此先用 SunSmart 代表构建，不机械重复五个品牌。若实际引入品牌配置或资源变化，再按项目规则扩大验证。

页面替身检查不能证明真实 UIKit 的显示时机；临时 SQLite 检查不能替代真实网络上传。最终人工验收最短路径为：创建 A → 立即回列表等待完成 → 打开 A 后返回 → 切换收藏 → 关闭并重开 App，确认 A 的状态一致，并确认 B 不受影响。

## 9. 授权和数据结构边界

- 状态：**方案 A 已实施，相关自动检查及最终 SunSmart 构建通过；等待手机验收。**
- 数据结构变更清单：**无**。不增删或改变数据库表、字段、默认值、字段含义、export JSON Key 或数据格式；只更新收藏字段的写入方式，不改变字段语义。
- 因无数据结构变化，不需要新 demo JSON、旧数据迁移、导入导出兼容处理或服务器发布配套。
- 不新增持久化状态、依赖或全局通知机制；不操作服务器、固件、SDK，也不提交、推送或同步其他工作树。
- 授权：用户已明确回复“确认按‘单 Site 本地状态更新＋收藏写入保护’的方案实施”；按以上范围完成，只有出现实质性范围变化时再次确认。
- 此前的功能测试用例文档保持不变；本分析文档同步记录修复结果。


## 10. 实施及验证记录（2026-11-06）

### 10.1 已完成的改动

- 单 Site 读取复用现有 `load`，增加不加载 Space 的选项，其他使用方默认行为不变。没有增加数据库表、字段或导出内容。
- 列表先读取目标 Site 的保存记录，再更新全部列表与收藏列表实际使用的对象；保留 Space、网关在线信息及较新的编辑。没有为此请求服务器或遍历读取其他 Site。
- 创建任务使用原有任务回调；列表隐藏时也能更新数据。回调结束后再刷新显示，避免任务尚未从队列移除时误判状态；同一页面同一 Site 的重复回调合并处理。任务回调保存 Site 身份，再查找列表当前持有的对象；列表重载并释放原对象后，回调仍然有效。
- 详情页在重新出现、上传开始及结束时校准当前 Site 的本地状态；终止后的旧等待或失败显示依据实际待上传内容更新。
- 收藏只更新 `favourite` 列。保存失败时，页面按未改变的对象恢复按钮，并显示已有错误提示。
- 补充保护：行为测试发现，上传期间点击收藏后，旧上传对象还可能在成功回执保存时改回收藏。现在回执先保留最新保存的收藏值，再执行原有版本确认和保存。仅多复制收藏值，不调整上传或队列规则。

### 10.2 自动检查依据和边界

旧代码已在新增检查中明确失败：列表仍持有旧上传时间、收藏列表仍持有旧上传时间、旧对象收藏写回覆盖最新资料。另两条新增检查也先确认了上传回执覆盖新收藏、原对象释放导致回调遗漏的问题，再验证修复结果。

检查使用真实临时 SQLite，以及直接提取的生产读取、保存、上传确认、列表刷新、收藏操作和主线程延后处理方法。SQL 记录确认刷新只查询目标 Site；列表与详情各查询一次，各页面的重复回调合并；Space 读取计数保持不变。原有两个创建回执样本缺少目前生产代码必需的地址分配信息，已补齐样本，没有放松生产校验。

页面绘制、导航、网络和 Mesh 分配仍由测试替身承担。回调顺序以现有管理器的“通知完成后移除任务”方式重放；这不能替代真实 UIKit、HTTP 或设备验证。未操作真机，也未修改 SDK、服务器或固件。

### 10.3 检查记录

- `python3 scripts/check_site_hdb_persistence.py /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`：通过，包含真实保存与重载、旧回执保留新编辑、单 Site 读取、收藏写入保护、失败重试、取消、账号/地区变化、删除、页面释放及列表重载后原对象释放等检查。
- `bash scripts/check_site_props.sh`：通过，包含属性解析、编辑、失败恢复及进入 Site 的时区更新规则。
- `python3 scripts/check_space_recovery_receipts.py`：通过。由于成功回执增加了收藏值保留，同步为它的测试替身补上收藏属性，并验证原有回执保护。
- SunSmart Debug generic iOS：首轮 **BUILD SUCCEEDED**；补充列表对象释放保护后，再次执行相同配置的增量构建，退出码 **0**。最终代码已完成编译验证。
- `git diff --check`：通过。
- 检查输出仍有既有的未使用变量、不会进入的分支及原服务器选择页面引用方式等编译警告，没有因此扩大本次修改范围。
- 本地 workspace：`SunSmartLocal.xcworkspace`。SDK 实际路径：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- 本次未提交或推送代码；未修改工程配置、依赖、资源及数据库/export JSON 结构。
- DerivedData：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024`。

### 10.4 手机验收（尚未执行）

以下勾选只代表真实手机操作结果，不用自动检查代替：

- [ ] 创建 A，立即回到 Sites 列表，等待上传结束；不下拉刷新，A 的同步提示自动消失。
- [ ] 创建 A 后停留在详情页，等待上传结束再返回；全部列表和收藏列表的提示一致。
- [ ] 上传期间收藏 A；上传结束后，收藏状态仍保留；重复切换收藏没有重复条目。
- [ ] 断网制造失败，恢复网络后重试；成功后提示消失，真正失败时仍能看到提示。
- [ ] 上传期间继续编辑城市或时区，较早上传完成后，新编辑仍正常保留并继续等待自己的同步结果。
- [ ] 上传期间重新加载列表，再进入其他 Site；A 完成后返回列表，其状态正确。滚动列表、切换收藏及重开 App 后也一致。
- [ ] 已有 B 不因创建 A 增加上传任务，详情内原有 Space 和网关在线信息没有丢失。


## 11. Site 13：新增 Space 后仍显示需要同步（2026-11-06 补充分析）

### 11.1 结论及直接证据

输入文件：[Site 13 导出](</Users/maginawin/Downloads/Site_Site 13_20261106_115106_328+0800.json>)，记录时间为 2026-11-06 11:51:06（UTC+08:00）。

**这次的直接原因是同一个 Site 的页面修改时间与数据库修改时间不一致。Space 已经确认上传；上一轮修复为保护较新编辑而保留页面版本，碰到了新增 Space 只修改内存、不保存父 Site 时间的旧行为。**

| 数据位置 | 数值 | 含义 |
| --- | --- | --- |
| `site.updateTimestamp` | `1793937049`（11:50:49） | 导出时页面持有的 Site 修改时间 |
| `_debugInspection.rawSite.sites[0].lastUpdateTimestamp` | `1793937047`（11:50:47） | 数据库保存的 Site 修改时间 |
| 同一 Site 行的 `lastUploadCloudTimestamp` | `1793937047` | 数据库已确认上传的 Site 版本 |
| 同一 Site 行的 `pendingSitePropsMask` / `pendingSitePropsTimestamp` | `0` / `null` | 没有待上传的 Site 属性编辑 |
| 同一 Site 行的 `syncCloudError` | `null` | 没有保存上传错误 |
| Space 1 的 `lastUpdateTimestamp` / `lastUploadCloudTimestamp` | 均为 `1793937048` | Space 1 已确认上传 |
| Space 1 的 `status.pendingUpload` / `pendingImport` | 均为 `false` | 没有等待完成的上传或导入 |
| Space 1 的 `status.lastConfirmedTimestamp` | `1793937048` | Space 完成状态与数据库一致 |

这里不能只看数据库里的 Site 行。导出包含两种来源：`site.updateTimestamp` 取自页面对象的副本，`rawSite.sites` 直接读取数据库。已核对 `site_extensions` 的保存内容：没有 `pending`，也没有冲突，因此 `1793937049` 不是待提交扩展内容临时抬高的导出值，而是页面对象自身的修改时间。

导出依据：`DebugCloudJSONExporter.Snapshot.init` 复制页面 Site；`SiteData.copy()` 保留其 `lastUpdate`；`ExportData.swift` 使用该值生成 `updateTimestamp`。`DebugCloudJSONRecords.readSite` 单独读取保存记录。

### 11.2 完整触发链

1. 创建 Site，页面与数据库最初都是 `1793937047`。Sites 列表和新打开的详情页持有同一个 Site 对象。
2. 新增 Space：`SiteData.addSpace()` 创建并保存 Space，把它加入 `site.spaces`；随后执行 `lastUpdate = 当前时间`，但没有保存这个 Site。
3. 这份样本中，Space 创建时间是 `1793937048`，方法结束时页面里的 Site 时间已到 `1793937049`；数据库中的 Site 仍为 `1793937047`。Space 建立包含分配、保存步骤，两个取时间的位置可能跨秒。
4. 上传前，`CloudSynchronizationHandle.syncOperation()` 重新读取数据库 Site，任务使用的是 `1793937047`。上传成功后，保存的 Site 确认时间也是 `1793937047`，Space 则确认自己的 `1793937048`。
5. 上一轮新增的 `applyPersistedDisplayState()` 为保护较新的编辑，要求“保存版本不早于页面版本”。此时 `1793937047 >= 1793937049` 不成立，所以跳过修改时间、上传确认时间等内容的更新。
6. 页面 Site 继续认为自己存在较新的修改。任务移除后，`showSyncCloudError` 可以返回“未知同步错误”，Sites 行因此显示同步图标。

关键代码位置（以本次分析时工作树为准）：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:89–112`：真实新增 Space 入口；第 110–111 行追加 Space 后，只改变内存 Site 时间。
- `SunSmart/Common/Cloud/CloudSynchronizationManager.swift:1359–1361`：上传前重新读取 Site。
- `SunSmart/Common/Data/SiteData.swift:266–283`：保存版本较旧时，保留页面版本。
- `SunSmart/Main/Site/Controller/SitesViewController.swift:1390`：Site 自身或任一个 Space 需要同步时显示提示。

下拉刷新会重新读取 Site，页面时间回到已保存并确认的 `1793937047`，所以提示消失。只有跨秒才容易暴露这条路径；若两个时间相同，版本保护不会挡住更新，这也解释了看起来不稳定的表现。

### 11.3 本轮验证及上一轮遗漏

用临时脚本直接提取并执行当前生产代码中的 `SiteData.add`、`SiteData.addSpace`、Site 数据库保存/读取、`confirmSiteUpload`、`reloadSiteData`、`applyPersistedDisplayState` 和同步提示判断。

Site 使用真实临时 SQLite；创建后跨过一秒再新增 Space，确认了：

```text
REPRODUCED: addSpace advances only memory; successful Site SQL receipt is rejected by display version guard; badge remains.
Site stored version=1793937419, confirmed=1793937419, page version=1793937420, Space pending=false
CONTROL: identical saved/page version applies confirmed state and removes badge, with no network request.
```

对照步骤仅在临时程序中将页面 Site 时间校准到保存时间，用来确定造成提示的条件；**不是建议在生产代码里无条件回退时间或清空待上传内容**。

临时脚本：`/var/folders/y1/phq8m2pd29jf7bwfcmq1j9j80000gn/T/site13-timestamp-probe-kva4o88t/probe.py`。

验证边界：Mesh 分配、HDB 和 Space 保存使用替身；Space 已完成的状态由用户导出提供。真实 Site 保存、上传确认保存及页面版本比较都执行了生产代码。未重放真实 HTTP、完整 Space 保存或 UIKit 显示，也没有安装或构建 App。本轮不需要修改业务代码来复现。

上一轮的列表测试用简化 Space 对象验证“保留 Space 引用和网关信息”，没有调用真实 `addSpace()`，因此遗漏了这次仅抬高内存 Site 时间的行为。此前通过的检查证明原覆盖范围，不证明“创建 Site → 新增 Space → 上传 → 返回列表”完整链路已经正确。

### 11.4 补充修复方向（已确认并实施）

继续保持单 Site 范围。需要在新增 Space 的共享入口统一 Site 修改时间的处理，让页面与保存记录一致；不能靠同步全部 Sites 或直接隐藏图标解决。

建议沿用当前 `addSpace()` 已表达的“新增 Space 同时更新父 Site 时间”的行为，把父 Site 的新时间正确保存，并让新增 Space 的成功/失败结果保持一致。保存时只处理必要的版本内容，避免用旧 Site 对象完整写回其他新资料；同时保留真正较新的 Site 编辑，不能简单删除现有版本保护。该方向不改变字段含义，不需要新增数据库或 export JSON 字段，也不需要迁移旧数据。

补充回归应执行真实新增 Space 入口，覆盖跨秒、同秒、Site 已上传/未上传、上传期间继续编辑，以及保存失败后重试；同时核对实际上传请求采用的 Site 版本和已确认版本一致。

- [x] 确认并实施新增 Space 时父 Site 版本的一致性修复。
- [x] 加入执行真实新增 Space 入口的持续回归，覆盖上述时序与失败条件。
- [ ] 手机验收创建 Site → 新增 Space → 上传完成 → 返回 Sites，无需下拉刷新。

第 11 节记录分析阶段，之后用户明确回复“按建议修复”，已进入第 12 节所述实施阶段。


## 12. Site 13 补充修复结果（2026-11-06）

### 12.1 已实施内容

- `SiteData.addSpace()` 改为在 Space 保存和父 Site 时间更新都完成后，才把新 Space 加入页面。移除了只修改内存中 Site 时间的步骤。
- 新增 `saveNewSpace()`，沿用已有数据库事务方法：Space 保存和 Site 版本更新一起提交；Space 写入、Site 写入或最终提交任一步失败，都撤销这次数据库改动。随后继续使用已有 Space 清理入口清理本次分配的内容。
- 父 Site 只写修改时间及必要的待上传属性版本，不用旧页面对象完整保存名称、城市、时区、收藏等资料。
- 复用已有版本增长规则。同一秒连续添加，或系统时间落后于保存版本时，新版本仍比上次大，避免把后一次添加误认为已上传。
- 已有待上传属性的内容与标记保留，版本随父 Site 一起前进。创建时的时区可以在正确版本完成后清除等待标记；较早的上传结果不会清掉新版本的编辑。
- 保存前确认仍是原 Site、仍有创建权限；如果页面持有真正尚未保存的新编辑，不用数据库内容覆盖它。成功后再使用最新保存的 Site 资料校准页面。
- 在分配新 Space 内容之前拒绝重复 Space 标识，避免错误处理清理到已有 Space。

本轮生产代码只增加 `Database.swift` 的单 Site 保存入口，并调整 `MeshNetwork+SunSmart.swift` 的新增 Space 方法。不改同步管理器的网络、队列、等待和重试规则，不添加其他 Site 的同步任务。

数据结构变更清单：**无**。表、字段、类型、默认值、导出 JSON 及字段业务含义均不变，不需要 demo JSON、迁移或服务器配套。保留工作树里其他任务的已有修改；没有修改 SDK、提交或推送代码。

### 12.2 新增的有效验证

新增 `Tests/Site/SiteSpaceCreationPersistenceTests.swift`，接入原有 `check_site_hdb_persistence.py`。本次调用真实新增 Space 入口，并执行生产的 Site/Space 建表、保存、重载和确认结果写入代码，使用实际临时 SQLite，不再把 Space 的保存仅替换成返回成功。

已经覆盖：

- [x] Site 创建与新增 Space 跨秒：页面与数据库的 Site 版本一致，上传确认后两者均不再显示需要同步。
- [x] 已上传 Site 再添加 Space，以及连续添加、时钟尚未前进时版本仍递增。
- [x] 创建时待上传时区随新版本完成；保存过的新名称、城市、时区和收藏不会被旧页面写回覆盖。
- [x] 添加 Space 后较早上传结果返回，新的修改和待上传内容仍保留。
- [x] 页面确有较新未保存内容时拒绝覆盖；权限被收回时不保存新 Space。
- [x] 分别制造 Space 写入失败、Site 时间写入失败及数据库最终提交失败：数据库与页面均不留下半完成数据，重新打开数据库仍一致。
- [x] 失败后重试正常；重复 Space 标识被拒绝且原记录不被清理；其他 Site 数据保持不变。
- [x] 同步完成后重新打开数据库，Site 和 Space 的已确认状态仍正确。

验证边界：普通空 Space 的 SQL 保存/读取/回退和新增入口是真实代码；Mesh 分配、Keychain、可选 HDB/Zone 内容和网络、界面仍使用替身。HDB 初始化、正常删除、失败清理和重试另由原有 HDB 创建回归覆盖，其数据库与 SDK 仍为替身。本轮没有把这些检查视为真机、服务器或完整 Mesh 验收。

### 12.3 检查与构建记录

- `python3 scripts/check_site_hdb_persistence.py /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`：通过。
- 补充重复标识前置检查后，以 `--space-creation-only` 再次运行受影响的真实数据库创建检查：通过。
- `python3 scripts/check_hdb_space_creation.py`：通过，最终前置检查修改后再次通过。
- `bash scripts/check_site_props.sh`：通过。
- SunSmart Debug generic iOS 首轮构建通过；最终前置检查修改后的增量构建也通过，退出码为 0。
- workspace 和 SDK 路径与第 10 节相同；没有依赖或品牌资源修改，使用 SunSmart 代表共享逻辑编译验证。

本轮中途出现独立的 Git 环境问题：共享仓库 `/Users/maginawin/Developer/iOS/YKH/sun-smart/.git` 无法读取 HEAD 和若干历史对象，`git status` / `git diff` 报 `fatal: bad object HEAD` 或 `unable to read`。只读检查时可见大量临时 pack 文件，但没有据此推断具体原因，也没有清理、重打包或修复仓库。

因此本轮完整 `git diff --check` 受阻。已对本轮两个生产改动片段作独立文件对照，未发现新增空白格式问题；新增测试文件与脚本没有行尾空白。这个对照不等于仓库差异检查已经恢复。自动检查与编译直接使用工作树源码，不依赖上述缺失对象。

### 12.4 最短手机验收

- [ ] 安装本分支新构建，创建 Site，等待至少 1 秒后创建 Space，上传完成后返回 Sites；不下拉刷新，提示应自动消失。
- [ ] 在已上传 Site 中连续新增两个 Space，完成后切换收藏列表、退出重进，状态保持正确。
- [ ] 上传过程中编辑 Site 城市或时区，较早的上传完成后，新编辑仍保留并等待自己的同步结果。
