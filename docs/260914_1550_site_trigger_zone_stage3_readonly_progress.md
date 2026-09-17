# Site Trigger Zone 阶段三：只读规划开发与 3A 测试环境清单

日期：2026-09-14。测试设备：`MtestiPhone15`。用户指定测试 Site：`Sep 11 site trigger zone`；目标 Spaces：`Space 1`、`Space 2`。状态：**3B 只读目标及任务预览已实现，3A 实物协议关卡未通过，尚无设备写入或正式 Site 同步入口。**

## 已实现

- `SiteTriggerZoneTopologyPolicy` 在稳定 `(spaceID, nodeUUID)` 身份上合并 Group Path、Group Trigger Zone、Space Trigger Zone 与全部 Site Zones。先判断 Space 级 Primary 模式，再投影节点元素地址。某 Space 任一节点已有该 Site Primary AppKey，或 Site Zone 需要该 Space 参与时，该 Space 全部邻近照明目标改用 Primary；非 Site 成员缺少 Primary NetKey、AppKey 或 Vendor Model Bind 也标记为需配置。删除 Site Zone 后，仍有 Primary 的 Space 不回退到 Space Key。
- `SiteTriggerZoneTopologyReader` 从现有 Mesh/Space 数据构造只读快照，不切换全局 Mesh、不安装 Key、不发送命令。只接受 `pending == nil`、无冲突、无拒绝回读且本地 `data` 与 `serverData` 完全一致的云确认状态。Primary AppKey 必须是绑定到唯一 Primary NetKey 的唯一 AppKey；歧义或缺失时停止规划，不使用 SDK 的兜底 getter。
- `SiteTriggerZoneSyncPlanningPolicy` 根据旧、新完整目标生成只读 `Remove` 与 `Configuration` 行，按选中 Zone 的新成员顺序、旧成员顺序和 Site Space 顺序排 Space。旧关系消失时 `Remove` 只记录过时邻居，最终 `Configuration` 仍保留其他 Path/Zone 的邻居。此处是**任务预览**，不代表设备读回、发送策略或成功回执；真实命令、TTL、持久账本和重试仍待 3A 后开发。
- 对重复 Space/设备/地址、失效成员、主地址或元素地址变化、Key 证据未知、组拓扑不完整、184 邻居上限等情况阻断可执行目标。新增脚本用例覆盖双 Space 关系合并、删除后 Key 保留、非 Site Path 成员绑定任务、按 Space 排序及共享邻居不误删。

## MtestiPhone15 只读清单

通过 `devicectl` 从已安装的 SunSmart 应用临时复制 `Documents` 快照，只查询本次 Site 的数据库元数据、关系与 Key **索引**；未读取或记录 Key 值、设备密钥、账号凭据。临时副本分析后已删除。快照时间约 2026-09-14 15:40，可能晚于/早于后续云端或设备实际状态，不能代替设备 Config Readback。

| 项目 | 只读结果 |
| --- | --- |
| Site | `Sep 11 site trigger zone`，本地有 4 个 Space；Space 1、2 均为 Owner 且状态正常。 |
| Space 1 | 3 台设备；Profile 7 的邻近照明 Group 1 个，另有非邻近照明 Group 1 个。三台节点只记录 Space NetKey/AppKey 索引 1；Vendor Model Bind 为 `[1]`。 |
| Space 2 | 3 台设备；Profile 7 的邻近照明 Group 1 个。三台节点只记录 Space NetKey/AppKey 索引 2；Vendor Model Bind 为 `[2]`。 |
| Site Primary | Mesh Key 表有索引 0 的 Primary NetKey 和绑定于它的唯一 AppKey；上述六台节点的本地清单均未安装/绑定索引 0。 |
| Group Path | 两个邻近照明 Group 的 `proximityLightingPath` 均为空；**目前缺少“原有 Group Path 在迁移中仍正常”的实物回归样本**。 |
| 云确认 Site Zone | 本地缓存的云端版本有 2 个 Zone；第 1 个 Zone 含 Space 1 的 3 台、Space 2 的 3 台、Space 3 的 2 台，共 8 台。若直接部署这个 Zone，实际写入范围还包括 Space 3。 |
| 云冲突 | Site Zone 本地状态 `conflict = true`，有未确认 `pending`；本地目标为 4 个 Zone，缓存的云端版本为 2 个。旧 pending base 的第 1 个 Zone 为空，云端后来已有 8 个成员；本地目标的第 1 个 Zone 与云端这 8 个成员一致，另外还修改了第 2 个 Zone 并新增 2 个 Zone。现有状态机仍判定冲突，不能把本地 4-Zone 目标当成云确认数据。 |

## 3A 后续关卡

1. 保全现有本地 4-Zone 草稿，先用云端实时 GET 核对上述缓存版本，再确定可审查的冲突合并目标；不得直接选择“使用服务器版本”丢弃本地改动，也不得凭 POST 回显宣布云保存成功。
2. 为 Space 1、2 建立并读回可恢复的真实 Group Path；当前六台设备都未具备 Primary Key/Bind，需用现有可控工具验证安装容量、Vendor 转发 AppKey/TTL、Path 迁移前后行为、双向跨 Space 感应、STOP/部分失败与重启。若沿用云端第 1 个 Zone，Space 3 也必须纳入现场和权限检查；否则创建仅覆盖 Space 1、2 的独立测试 Zone。
3. 实物确认单遍按 Space 部署的过渡状态是否损伤原 Path/Zone；若会损伤，改用预安装 Key 或两轮连接。通过后才开发显式设备写入、持久任务回执、Save 后自动同步页以及旧 Path/Zone 写入口统一策略。完整验收前保持正式同步入口关闭。

## 16:12 补充：用户选择与真机云回读阻断

用户确认**保留本地 4-Zone 目标并安全合并**，3A 另建只含 Space 1、Space 2 的测试 Zone，不把已有 8 成员 Zone 中的 Space 3 一并下发。为此补入保守重基线：仅当云端相对旧基线的每项变化都已被本地目标逐项、原样包含，且云端 Zone 相对顺序仍被保留时，才更新 pending 基线；真正同 Zone/未知字段冲突仍阻断。重基线时记录已被云端确认的旧成员差异。另修复非空 Zone 删除后的 `deviceSyncChanges` 遗漏，保留旧成员供将来 `Remove` 规划；相关纯逻辑测试通过。

已在 `MtestiPhone15` 原位安装本工作树签名 App，用一次性 `DEBUG` 探针通过 App 原有认证上下文执行只读回读和现有 Site 协调器。结果：

- `SiteTriggerZoneCoordinator.synchronize()` 在**首个 GET 的 `SiteTriggerZoneStore.receive`** 发生顶层 `DecodingError.dataCorrupted`，返回 `storage`；尚未进入 POST，因此没有提交 4-Zone 目标。
- 该 GET 的 `siteInfo.data.extensionData` 被存成拒绝回读，确认为**空字符串**，不是可解析的扩展对象。
- 独立调用 `/sitespace/retrieve/siteprops`，其 `data.props.extensionData` 也是不可解析的字符串。此次探针只记录类型，没有留存完整响应或密钥；不能用该接口确认 4-Zone 目标。
- 真机本地仍是 `conflict = true`、`pending` 存在、`data` 为 4 Zones、历史 `serverData` 为 2 Zones。历史 2-Zone 缓存**不等于当前实时云端状态**。设备命令、Group Path 配置和新测试 Zone 均未执行。

一次性探针及诊断代码已从源码移除，重新签名构建、原位安装并正常启动无探针 App。临时数据库副本仅用于本机只读核对，结束后删除。下一步需要服务端让 Site GET 或 `/retrieve/siteprops` 返回**可解析且反映已持久化目标的完整 `extensionData`**，或明确权威读取接口的契约；随后才可进行三方合并、POST 后 GET 确认，再创建两 Space 测试 Zone 和实物配置。不能用 POST 回显或本地缓存绕过这个关卡。

## 验证

- `bash scripts/check_site_trigger_zones.sh`：全部通过。
- 直接 `xcodebuild` 的 generic iPhoneOS Debug：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 均构建成功。
- `git diff --check`：通过。没有修改 SDK、设备配置、云端数据或 UI，因此尚无实物联动/布局验收结论。
