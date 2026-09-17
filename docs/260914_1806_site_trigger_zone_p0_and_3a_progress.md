# Site Trigger Zone P0 实施与 3A 只读核对进度

日期：2026-09-14。状态：P0 代码、聚焦测试与多 target 构建完成；真机页面目视验证尚未完成。3A 云端回读与本机协议/设备缓存盘点完成，实物配置与联动关卡尚未执行。已追加 3B 的 Zone 级只读成员变更预览，尚非完整设备任务归属。依据为已确认的 [修复执行计划](260914_1748_site_trigger_zone_device_sync_repair_execution_plan.md)。

## P0 已实施

- 不再用 `!zone.isEmpty` 直接宣称设备待同步：有已知成员/地址变更时保留 pending，既有非空 Zone 缺少可信设备证据时为 unknown，空 Zone 且无旧清理依据时为 settled。纯旧字段迁移若稳定设备身份、分组、主地址和地址一致，仅从“已知差异”降为“未验证”；它**不是**设备已配置的证明，也不删除 `deviceSyncChanges`。
- `unknown` 有可见的问号状态按钮与完整无障碍标签，区别于 pending 的同步图标。最初所有状态入口共用全 Site 只读预览，现已进一步改为 Zone 级成员变更预览；弹窗明确写明“设备同步尚未开放”及共享拓扑限制。云保存 Toast 依据 pending / unknown / settled 区分提示。
- 英文、简体中文同步补充文案；增加旧字段迁移、实际地址变化、新成员、unknown 可见状态等聚焦测试。没有新增认证数据、设备配置发送或 SDK 改动。

验证：`bash scripts/check_site_trigger_zones.sh` 全部通过；两种 `Localizable.strings` 的 `plutil -lint` 通过；`git diff --check` 通过。Zone 级预览追加后，直接 `xcodebuild` 的 generic iPhoneOS Debug 对 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`、`Lumineux` 均成功。最新 `SunSmart` 签名真机构建成功，已在允许的 `MtestiPhone15` 原位安装、启动，进程列表确认新安装包仍在运行。项目 `AGENTS.md` 随后新增“禁止使用 Computer Use 控制电脑”，后续不再使用该通道。旧的隔离真机 UI 宿主因缺少新引入的 `SiteTriggerZoneTopologyReader` 源文件而未能构建，不能用它宣称新页面已验收；需要更新宿主或人工目视核对卡片、问号按钮、长提示和约束日志。编译及启动不能代替这一 UI 验收。

## 3B 已开始的只读范围纠偏

每个卡片及 Space 状态按钮现在携带所点 `zoneId`，弹窗标题标注 Zone 序号，正文只计算该 Zone 已记录的成员新增、移除、地址/分组变更数。旧字段迁移但成员身份及地址未变时显示“设备状态未验证”。这不是设备命令数：共享设备、Group Path、其他 Zone 和转发 Key 迁移仍需要完整 Site 目标与现场证据，弹窗明确说明这一点。删除 Zone 后可能保留的旧清理任务尚缺 Site 级入口，完整来源归属仍属于 3B 后续工作。新范围通过策略测试、字符串 lint、`SunSmart` generic iPhoneOS 构建；尚未完成真机页面目视验证。
若云目标还存在 pending、冲突或未能与服务器回读一致，预览明确显示“云端目标尚未确认”，不拿旧的成员变更记录冒充本次 Save 的设备影响。此保护追加后再次通过全部聚焦测试、双语字符串 lint、`git diff --check` 与五个品牌 target 的直接 generic iPhoneOS Debug 构建。

## 3A 当前权威云目标

在用户日志所示 Site 上，用与应用相同的只读 `get/siteprops` 请求重新读取实时服务器对象，并与从 `MtestiPhone15` 临时复制的本机 SQLite 快照比较；只输出统计信息，不记录账号密钥、Mesh Key 值或完整响应。服务器业务码 200，Site 身份正确，`extensionData` 是可解析的 schema 2 对象；服务器与本机 `serverData` 的时间戳和内容一致。当前服务器有 5 个 Zone，成员数依次为 **8、2、2、2、3**；本机 `data == serverData`、无云 pending、无冲突。故先前“GET 返回空字符串”的旧诊断不再代表当前这个 Site 的实时状态；本次云目标已确认，但没有任何设备完成证据。

本机仍留有 5 条 `deviceSyncChanges`。第 1 条旧/新均为 8 个相同设备身份，分组与主地址相同，旧 `triggerElementAddress` 与新 `deviceAddress` 在这 8 个成员上一一相等，属于本次可判定的元数据迁移；P0 把该 Zone 显示为“未验证”。其余四条分别从 0 个成员增加到 2、2、2、3 个，仍属于已知待处理变化。服务器第 1 个 Zone 跨 `Space 1` 三台、`Space 2` 三台、`Space 3` 两台；其余四个 Zone 都只含 `Space 1`。**当前不存在仅覆盖 Space 1/2 的独立 Site 测试 Zone**，不能直接拿跨 Space 3 的既有 Zone 作为两 Space 试验对象。

## 3A 当前设备缓存与协议边界

- Site 有 4 个 Space。`Space 1`、`Space 2` 的本机 Mesh 缓存分别有 3 台节点；前者三台均为 PID `2502`、VID `0003`，后者为两台 `2502`、一台 `1502`，VID 均为 `0003`。这些是本机清单，不是实物读回。
- Site Mesh 清单有 Primary NetKey/AppKey 索引 0，AppKey 绑定 Primary NetKey；`Space 1` 三台只记录索引 1 的 NetKey/AppKey/Vendor Model Bind，`Space 2` 三台只记录索引 2。缓存中六台均未安装或绑定索引 0。Key **值**未读取、输出或保存。
- `Space 1`、`Space 2` 的 `groupInfos.proximityLightingPath` 均为空，尚无“原 Group Path 迁移前后保持正常”的实物基线。建立基线后必须先确认可恢复，才测试 Primary Key/Bind 迁移。
- 本地 SDK 的 `SunricherVendorSet` 支持邻近照明 `0x41/0x02` 写入转发 AppKey 索引、TTL 和邻居，`SunricherVendorStatus` 支持 RET 成败；`SunricherVendorGet` 没有邻近照明配置 Get。项目协议文档 `SunSmart/sunricher_protocol_vendor.md` 的 0x41 表也只列 Set 与 RET。**因此当前没有按设备读回邻居/TTL/转发 Key 的已知接口**；Vendor Set 的成功 RET 可作为命令回执，但不能单独证明 App 断开后的跨 Space 联动。3A 必须用受控实物触发、原 Path 回归及失败后现场状态验证；若固件另有 Get，需要先拿到其协议并补足 SDK 读回。
- 标准 Mesh Config 层已有 `ConfigNetKeyGet/List`、`ConfigAppKeyGet/List`、`ConfigVendorModelAppGet/List`，可为设备上的 Key 索引和 Vendor Model Bind 提供读回路径；它们不能代替 Vendor 邻居/TTL/转发 Key 读回。SDK `VendorServerDelegate` 在收到邻居 Set 时只把 enable、relay 和邻居写进本机 Node 缓存，**没有缓存该 Set 的 TTL 或转发 AppKey 索引**，因此现有缓存对这两项没有证据价值。
- SDK `MeshMessageManager` 的控制消息队列在按地址发送时总使用 `manager.currentApplicationKey`；`MeshMessageHandle` 不保存显式传输 AppKey。底层 `MeshNetworkManager.send(... using: ApplicationKey)` 已有显式 Key 接口。3C 若走现有队列，必须最小扩展句柄/发送路径并做 Key 身份预检；不能只把目标转发索引填进 Vendor payload，也不能依靠页面当前 Space 推测传输 Key。

下一步：完成 P0 真机页面目视检查；在不扩大到 Space 3 的测试范围下建立原 Group Path 与独立两 Space 测试 Zone，执行可回退的 Key/Bind、Vendor 转发和断线联动实物关卡。关卡未通过前不实现或开放正式 Site 设备写入。3B 的只读目标/来源归属可继续独立推进，但不能把本机 Node 缓存当成设备已同步。
