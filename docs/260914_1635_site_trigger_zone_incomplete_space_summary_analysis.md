# Site Trigger Zone 全部显示空间信息不完整的原因

日期：2026-09-14。依据：用户提供的 `get/siteprops` 响应、页面日志和当前工作树源码。未读取或记录 Mesh Key、设备密钥及账号凭据。

## 结论

本次响应的 Site 级 `extensionData.schemaVersion` 是当前 App 认识的 `2`，但第一个 Zone 的 8 个成员均使用 `triggerElementAddress`，没有当前解析器必需的 `deviceAddress`。`SiteTriggerZoneMember.init?(value:)` 因缺字段返回 `nil`；一个 Zone 只要有任一成员解析失败，`zone.members` 就为 `nil`，进而使这份云端 `extensionData.supportsMemberEditing` 为 `false`。页面的统一提示由全局门控产生：`SiteTriggerZoneViewController.reload()` 发现当前 `state.rejectedRemote != nil` 或 `state.data.supportsMemberEditing == false` 时，会将**当前显示的所有** Zone 构造成 `hasCompleteSpaceList = false` 的占位模型，卡片统一显示“Some space information is unavailable. Editing is unavailable until it is verified.”，并关闭编辑。这个提示并不证明 `spaces` 数组本身缺失。

当前页面若直接采用本次云端对象，缺少 `deviceAddress` 就足以触发统一提示；若有 `pending`，页面可能继续显示旧的本地 `state.data`，还需检查这个本地目标是否也采用旧字段。仅凭 HTTP 响应无法证明目前的 3 个可见 Zone 分别来自哪份状态。

关键源码：`SiteTriggerZoneData.swift` 的成员解析、`SiteExtensionData.supportsMemberEditing`；`SiteTriggerZoneViewController.swift` 的 `reload()`；`SiteTriggerZoneItemCell.swift` 的提示条件。

## 数量与本地状态

这份响应的 Site 级 `extensionData.triggerZones` 明确只有 **2 个**：第一个有 8 个成员，第二个为空。各 Space 内的 `spaceData.triggerZones` 是另一套数据，不是本页面的 Site 级列表。若页面当前展示 **3 个** Zone，第三个不能从这份响应推出；页面读取的是 `SiteTriggerZoneStore` 的 `state.data`，有未确认 `pending` 时可能保留本地目标，数量可与服务器不同。此前同 Site 的只读快照曾显示本地目标 4 个、缓存云端 2 个，不能将该历史数量直接当成本次页面状态。需要记录当前 `state.data.zones?.count`、`serverData?.zones?.count`、`pending`、`conflict`、`rejectedRemote` 和 `supportsMemberEditing`，才能解释这次实际显示的 3 个来自哪里；只记录计数和布尔值即可。

本次 `get/siteprops` 的 `extensionData` 是合法 JSON 对象，字段不匹配发生在**成员语义校验**，而非顶层 JSON 解码。若服务器时间戳不早于本地记录，`SiteTriggerZoneStore.receive` 会清掉旧的 `rejectedRemote`；若仍看到统一提示，还应核对当前有效的本地 `state.data`，不能只凭 HTTP 200 推断页面已采用此响应。

## 修复方向与验证

先确定服务端成员字段契约和地址语义。当前 App 的 `deviceAddress` 是规范化设备地址：优先 Vendor Model 所在元素地址，否则使用主地址；`triggerElementAddress` 表示接收触发消息的元素地址，不能未经核实直接视为同一字段。兼容旧数据时应在确认语义后做明确迁移或字段映射，保留未知字段和原有成员；同时加入这份旧格式的解析回归用例，并覆盖空 Zone、非空 Zone、混合新旧成员及未确认本地草稿。不要仅为了消除提示而跳过成员校验或静默丢弃 8 个成员。

日志中的 `_UITemporaryLayoutWidth == 0`、`_UITemporaryLayoutHeight == 0` 与 SnapKit 约束冲突属于页面初始测量时的布局问题。它们不会设置 `hasCompleteSpaceList`，因此不是这句提示的触发条件；若真机稳定布局仍异常，应独立排查。

本次仅做静态诊断，未修改生产代码、云端数据或设备配置，也未宣称已完成真机 UI 验收。
