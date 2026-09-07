# Proximity 配置兼容保护：App 实施记录

日期：2026-09-07。工作树：`trigger-zone-july`。基线：`fd520c9`。用户已授权仅修改 App，并建议所有 Editor 手机同步升级。本文记录本次代码修改；尚未提交 Git。

## 1. Profile 切换的明确规则

**正常切换仍然可以保存和同步，包括 Proximity（7/8）切换到 Occupancy（1），以及另一台修复版手机传来的完整切换。** 判断条件不比较前后类型，不用“7/8→1”本身触发拒绝。

保护针对以下情况：

- Profile 身份、类型或必要参数缺失/非法；Photocell 日夜条件、场景内容或引用不完整。
- 已有 Group 的 Profile/Path 加载失败，或已保存的 Space Zone 数据无法解码。
- 配置自相矛盾，例如非 Proximity Profile 仍携带 Group Path；未知拓扑不作为明确清空处理。
- 本机已有 Space Zone 时，无 schema 的旧格式传来空/缺失 Zone 数组，会保留本机并要求核对。这种旧版输出无法证明用户主动清空了新版功能；schema 1 新版明确清空仍正常接受。
- 保存失败、导入尚未完成、升级基线未核对，或上传后的内容没有确认。

正常的显式 Profile 切换仍走原有生命周期：切出 Proximity 时清除相关 Group Path/Zone 与 Space Zone 成员，生成所需设备同步；重新启用时按新的明确配置建立拓扑。完整、合法的远端删除也会接受，避免自动复活已删除配置。

如果旧版已经把错误值写成一份完整且自洽的 type 1 快照，仅靠现有服务端数据无法区分它与合法切换。本次不会猜测改回 type 7；这也是必须建议所有编辑端升级的原因。

## 2. 已实现的修改

### Profile 与 Group 保存

- 已有 Group 加载不到 Profile 时标记失败，阻止该 Space 导出与配置设备，不把默认 Profile 当作已加载的真实数据。Group 页面显示 `Profile unavailable`，不打开默认参数冒充有效配置。
- `GroupInfo.save` 在 App SQLite 同一 savepoint 内保存 Profile 和 GroupInfo，再读回验证。数据库连接不存在、编码失败或写入失败会返回失败。
- Group 改名读回 SDK 中的名称；Profile 保存失败时不进入成功、设备同步或云端上传流程。新建 Group 保存失败会清理此次新建的 Mesh Group，清理不能确认时继续保护。
- 检测真实表结构：仅在历史 `regulatorAccuracy` 列存在时补齐 INSERT 所需值，保留已有值，新行采用该历史版本的 `0x14`。不新增 Accuracy 功能或 Mesh 指令。

### 导入、导出与设备配置

- 导入在删除本地节点/Group 前验证 Profile、解码 Group/Node，并写下原始恢复点与待应用快照。重复 Group、矛盾的 Profile/Path 会进入保护。
- App 业务表使用事务；SDK Mesh 存储使用导入后 Group/Node 回读检查。生命周期提交失败会传回导入失败。
- 两个数据库不能组成现有接口下的单个原子事务。部分应用/中断时保留 `pending-import.json`，禁止该状态导出或配置 Mesh，下次导入先重放已接收的候选快照。成功完成后才解除保护。
- 导入后的设备任务使用此次导入的完整 Group/Space 拓扑，不从当前其他 Space 的全局对象推导目标。
- 导出只检查并序列化，不再调用生命周期 commit 清理业务拓扑。缺失 Profile 或尚未应用的拓扑修复使导出失败。
- 普通同步页、任务生成、缓存任务转指令、Device Restore、延期同步与生命周期提交检查保护状态。改名不会解除导入失败保护。
- 沿用现有 `spaceData` 云端结构与旧顶层格式读取；未双写两个独立可编辑 Zone 副本。

### 升级与云端确认

- 首次受影响操作前，通过 SQLite Backup API 留存 App 和 Mesh 数据库，并验证 `integrity_check`；备份包含 WAL 中的数据，不复制裸主文件充当完整备份。
- 恢复文件按当前用户、服务器区域、Mesh UUID、子网标识隔离，存于 App 的 `Library/Application Support/SpaceConfigurationRecovery`；设置文件保护并排除系统云备份。
- 升级进入 Space 时核对已有完整配置与远端；首次上传仍需核对。关键配置/成员一致时可继续本地名称等修改；不一致时保留本地快照并阻止旧 dirty 直接全量覆盖。
- 保存首次数据库恢复点、最近两次导入前的完整数据库检查点及最近完整的导出快照。重放未完成导入时不覆盖其原有检查点。它们不等于经过人工确认的正确配置；已经损坏的数据不会因为备份成功就变为可信。
- 上传确认绑定实际提交时的时间戳，旧请求完成不会把随后发生的修改标为已上传。
- 已有 Space 上传及 Site 内嵌 Space 上传，在成功响应后 GET 回读，核对 Profile、Group Path/Zone、Space Zone 与成员归属；忽略节点状态缓存。不能确认时保留 dirty 并进入保护，避免自动反复覆盖。首次 Site 创建仍沿用已有资源分配回读流程。
- 回读仅比较当前类型实际使用的配置；普通 Profile 忽略遗留的 Proximity Relay/Photocell 日夜字段，避免正常 7/8→1 切换被服务端保留的无效旧字段误拦截。

## 3. 恢复能力与限制

有一份完整远端配置时，重新进入并成功导入可恢复配置、解除保护；被中断的导入会先完成已保存的候选快照。未完成导入保留两个原始数据库备份作为排障依据。

Space 的云端失败图标提供“重新加载云端数据”和“使用本机数据”。本机恢复仅在当前本机快照完整、一致、没有导入中断且具有编辑权限时提供；二次确认明确说明它会替换云端整个 Space。确认后再次核对本机配置未变化，先备份本机和远端数据，再允许正常上传与回读确认。不会静默选择某一端胜出。

本次没有替换运行中的 Mesh 数据库来回滚，因为这可能回退 Sequence Number。恢复入口使用当前可验证的本机逻辑数据，并非任意历史数据库的一键还原；从其他历史备份恢复某一份配置仍需明确哪份副本正确。全库中的非 Proximity 附属记录没有因此获得跨库原子事务保证。

没有可信的修改前基线时，无法确认旧 dirty 只改了名称。因此不同基线上的待上传内容保留在恢复资料中，不自动把旧名称或 Profile/拓扑覆盖回最新远端。缺失所有完整副本时，已丢失的参数、Path 顺序和 Zone 分组仍需人工重建。

客户端 GET/回读不是服务端 CAS；另一台未升级手机仍可能在回读后覆盖云端或设备邻居。不得把本次改动解释为对旧版任意操作、任意并发的无损承诺。

## 4. 验证记录

| 验证 | 结果与证据范围 |
| --- | --- |
| `bash scripts/check_path_topology_persistence.sh` | 7 组通过，包含既有拓扑/生命周期回归与本次完整 Profile 切换、缺字段、非法类型、Photocell 场景及回读比较测试 |
| `bash scripts/check_configuration_database_safety.sh <resolved SDK checkout>` | 真实 SQLite 测试通过：WAL 备份、备份独立性、备份失败、保存失败回滚、无连接返回失败，以及历史 NOT NULL 列保留和完整 7→1 保存 |
| 本地化 | English 与简体中文共用资源新增同一 Key，`plutil -lint` 通过；五个品牌均引用共用资源 |
| 相邻流程回归 | Auto Min 兼容、Restore 过渡时间和 Site/Space 上下文检查通过；修正了上下文契约中在基线就已失效的单行方法定位，并增加导入使用明确拓扑的检查 |
| `git diff --check` | 通过 |
| generic iPhoneOS Debug 构建 | 最终代码的 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 均退出 0；未签名通用 iOS 设备构建 |

测试使用工程实际解析的 Nordic SDK `86f5ec9` 中的 SQLite 源码；SQLite 用例执行生产 savepoint、Backup 与历史列兼容代码。测试不代表真实云端或 Mesh 已收敛。

构建直接运行 `xcodebuild -quiet -workspace SunSmart.xcworkspace -scheme <品牌> -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`，未使用 Simulator。中途发现新辅助类型与 Foundation `Expression` 命名冲突，已限定为 `SQLite.Expression`；Lumineux 的沙盒文件访问失败经授权后重试。

## 5. 尚需双手机/真实设备验收

已请求确认 A/B 对应设备及独立测试 Space，尚未取得测试对象。本次没有安装到用户手机、改变真实 Space、发送 Mesh 指令或上传真实配置。

需要在修复版 A/B 上完成：

1. 覆盖安装保留旧本地数据，旧格式 Group Profile/Path/Zone 正常导入，新增 Space Zone 后四类配置均正确。
2. A/B 交替改名、切换完整 Profile、切出/切回 Proximity、清空 Zone、删除成员；云端回读、重进、重启后结果正确，合法删除不复活。
3. 注入缺失 Profile、孤立引用、损坏 Zone、保存失败和导入中断；不出现默认 Profile 上传或 Disable/邻居缩减，失败状态不被当成同步成功。
4. 上传过程中再次编辑，核对后续 dirty 保留；回读缺字段、超时以及 Site 嵌套操作不能绕过保护。
5. 读取真实设备 Enabled、Relay、Neighbors，验证 Group 与 Space 拓扑合并、Restore 和延期同步。
6. iPhone/iPad 检查失败提示、`Profile unavailable` 标签、原有 Profile 保存与恢复确认完整交互。恢复使用现有 `SRAlertView`，没有新增布局约束；实际显示、导航和 Mesh 结果仍待验收。

上述验收通过之前，应称为“代码及本地验证交付”，不能称为双端兼容问题已经完成实机闭环。
