# Kinetic Switch 离线解绑、删除后遗留绑定问题分析与修复方案

## 1. 结论

测试反馈与当前代码的数据流可以完整对应。问题的主因不是单纯“删除 Switch 时没有清掉 proxy 的 App 关联”，而是以下两类行为叠加：

1. 用户取消 proxy 或取消 Group 关联并保存时，App 会先把新的期望状态写入正式 `DeviceSwitchData` 并持久化，再执行 Mesh 同步。L1 离线导致同步失败后：
   - `proxyNodeAddress`、`enOceanMacAddress`、`enOceanSecurityKey` 已从 Switch 正式数据中清空；
   - 已取消的 Group 已从 `bindGroupAddresses` 移到 `unbindGroupAddresses`；
   - 原 proxy 地址只剩在 `deleteProxyNodeAddress`；
   - 但 L1 节点缓存和真实设备固件仍保存原 Kinetic switch MAC、按键发布配置，组内节点也可能仍订阅旧虚拟组。
2. 删除 Switch 的同步规划只检查当前 `bindGroups`，并且只在这些 Group 的节点中按当前 `enOceanMacAddress` 查找 proxy；它没有覆盖 `unbindGroups` 和 `deleteProxyNodeAddress`。
   - 此时当前 Group 和当前 MAC 都已经被前一步清空；
   - 删除规划错误返回“没有任何待同步数据”；
   - App 因而直接删除本地 Switch、删除虚拟组并提示成功，但没有真正清理 L1 和目标节点上的 Mesh 配置。

这会形成“幽灵绑定”：

- App 中原 Switch 对象和 ID 已不存在；
- L1 的 App 节点缓存仍有旧 `enOceanMacAddress`；
- L1 固件仍有旧 EnOcean MAC 和按键发布配置；
- 目标节点可能仍订阅已经从 App 删除的旧虚拟组。

因此，新建 Switch 后即使没有 proxy ID，旧物理面板仍可能通过 L1 和旧虚拟组控制部分灯光；重新扫描同一物理面板时，App 又会根据 L1 节点缓存提示“已经被 L1 关联”。

补充确认：L1 再次被选择为 proxy 时，现有 SDK 支持覆盖式重配置。目标 MAC 与 L1 旧 MAC 不同时会先删除旧配置再添加新 MAC；MAC 相同但 Switch Group/按键目标变化时，也会比较旧 `enOceanProxySwitchKeys` 并重写 publish。基于这一能力，历史异常恢复不需要单独增加 orphan 清理流程，可以直接允许“原 L1 接管旧绑定并重新配置”。但如果用户选择的是其他 proxy，仍必须阻止绑定，避免原 L1 与新 proxy 同时响应同一个物理面板。

## 2. 测试现象与代码链路

### 2.1 取消 proxy 后，Switch 正式数据在同步前已经变成未绑定

`EnOceanProxyViewController` 关闭 proxy 开关时会立即清空：

- `enOceanMacAddress`
- `enOceanSecurityKey`
- `proxyNodeAddress`

文件：

`SunSmart/Main/Group/Switch/Controller/EnOceanProxyViewController.swift`

范围：410-416。

随后保存时，编辑前的 proxy 地址被记入 `deleteProxyNodeAddress`，但新的 `setSwitchData` 会在 Mesh 同步前更新到正式 `switchData` 并保存数据库。

文件：

`SunSmart/Main/Device/Switches/Controller/DeviceSwitchViewController.swift`

范围：

- 160-170：保存旧 proxy 地址；
- 219-225：同步前更新正式对象并持久化。

所以 L1 离线、解绑消息失败时，UI 所依赖的当前 proxy/MAC 已经为空。Switch 外圈出现虚线、绑定页面 ID 为空，与这条路径完全一致。

### 2.2 取消 Group 后，原 Group 被记录为待解绑，但不再属于当前绑定组

Group 选择回调会：

- 用新的选择结果覆盖 `bindGroupAddresses`；
- 把移除的原 Group 写入 `unbindGroupAddresses`。

文件：

`SunSmart/Main/Device/Switches/Controller/DeviceSwitchViewController.swift`

范围：698-715。

这本来可以作为“期望状态 + 待清理状态”的两阶段记录，但后续删除规划没有完整消费这两个状态。

### 2.3 删除规划漏掉待解绑 Group 和待删除 proxy

普通保存同步会处理：

- `unbindGroups`
- `deleteProxyNode`

文件：

`SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

范围：1697-1742。

但 `deleteSwitch == true` 的分支只处理：

- `bindGroups`
- `bindGroups` 内节点中 MAC 等于当前 `enOceanMacAddress` 的节点

文件：

`SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

范围：1679-1695。

离线解绑失败后，恰好是：

- 原 Group 只在 `unbindGroupAddresses`；
- 原 proxy 只在 `deleteProxyNodeAddress`；
- 当前 `enOceanMacAddress` 已为空。

所以删除分支无法找到任何待清理对象，错误返回空计划。界面把空计划解释为“未使用过，可直接删除本地缓存”，由此产生假成功。

### 2.4 删除本地缓存的防御性清理也无法命中 L1

`deleteSwitch(switchData:)` 当前通过：

`node.enOceanMacAddress == switchData.enOceanMacAddress`

查找需要清理的 proxy。

文件：

`SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

范围：932-946。

此时 `switchData.enOceanMacAddress` 已为空，而 L1 的 MAC 非空，因此不会命中 L1。该比较在 Switch MAC 为空时还可能命中任意一个同样为空的无关节点，存在额外误清风险。

即使命中，目前也只清 `node.enOceanMacAddress`，没有同步清理：

- `enOceanProxySwitchKeys`
- 相关同步状态缓存
- 真实 L1 固件内的 EnOcean 绑定与 publish 配置

因此它不能替代成功的 Mesh `enOceanDelete`。

### 2.5 “已经被 L1 关联”的提示来自 Node 缓存

扫码时除了页面内的映射，还会直接在所有真实节点中查找：

`node.enOceanMacAddress == 扫描到的 MAC`

文件：

`SunSmart/Main/Group/Switch/Controller/EnOceanProxyViewController.swift`

范围：222-246。

所以即使原 `DeviceSwitchData` 已删除，只要 L1 节点缓存仍保存旧 MAC，App 就会继续提示物理面板已经被 L1 关联。

SDK 只有在收到成功的 `enOceanDelete` 响应后，才会清除节点的：

- `enOceanMacAddress`
- `enOceanProxySwitchKeys`

文件：

`NordicSigMeshSDK/Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift`

范围：234-240。

这进一步证明，删除 App Switch 对象不等价于真实 proxy 已解绑。

## 3. 对用户理解的评估

### 3.1 理解正确的部分

- 正常添加、关联 Group、选择 L1 作为 proxy 后，物理面板工作正常。
- L1 离线时，涉及 L1 的解绑或删除消息无法完成。
- 删除 Group 关联后再次删除 Switch 能“成功”，但该成功仅是 App 本地删除成功，不是设备端清理成功。
- L1 再次上线后仍保留旧绑定，这会阻止同一物理面板绑定到新 Switch 或其他 proxy。
- 删除 L1 后恢复，是因为移除节点/重置流程消除了 L1 上的旧 proxy 状态，同时 App 也不再持有该节点缓存。

### 3.2 需要修正的部分

“删除 Switch 时把原 proxy 的 App 数据关联删除”只能解决扫码前的本地冲突提示，不能独立作为完整修复。

如果只清 App 缓存、不清 L1 固件：

- App 可能允许把同一物理面板绑定到另一个 proxy；
- 原 L1 仍会接收该物理面板事件并向旧虚拟组发消息；
- 网络中可能同时存在两个 proxy；
- 目标节点的旧虚拟组订阅仍可能保留；
- 当前“可以关灯但开灯无效”一类不一致控制仍可能继续或演变为其他异常。

因此，App 侧清理应是成功远端清理后的状态收敛或防御性补偿，不能用来替代真实 Mesh 清理。

## 4. 方案比较

### 方案 A：仅在本地删除 Switch 时清空原 proxy 缓存

处理：

- 通过 `deleteProxyNodeAddress` 找到 L1；
- 清除 L1 的本地 MAC 与按键缓存；
- 允许后续重新扫描。

优点：

- 改动小；
- 可以消除当前“已绑定 L1”的本地判断。

缺点：

- L1 固件和目标节点订阅仍可能残留；
- 会把 App 显示成已修复，但真实 Mesh 状态没有修复；
- 可能制造双 proxy 和不可预测控制。

结论：不建议单独采用。

### 方案 B：补全两阶段清理链路，禁止待清理状态被假删除

这是推荐方案。

#### B1. 删除规划必须覆盖所有有效与待清理状态

删除 Switch 时，Group 清理目标使用以下地址的去重并集：

- `bindGroupAddresses`
- `unbindGroupAddresses`

proxy 清理目标按地址优先解析：

- `deleteProxyNodeAddress`
- `proxyNodeAddress`
- 最后才允许用非空 MAC 做防御性查找

只要任一节点仍有解绑 Message Handle，删除计划就不能返回空。

#### B2. 只有远端清理确认成功后才完成本地删除

- L1 离线时保留 Switch 或删除 tombstone，不得把操作当作完整成功；
- L1 上线后重试 `enOceanDelete` 和相关 publish 清理；
- Group 内目标节点完成旧虚拟组 Subscription Delete；
- 全部完成后再删除 Switch 数据与虚拟组。

如果产品需要支持“离线时从列表隐藏 Switch”，应采用“逻辑删除 + 持久化 cleanup tombstone”，后台在 L1 上线后继续清理，不能直接丢弃旧 proxy、MAC、Group 和虚拟组地址。

#### B3. 修正删除完成时的本地缓存收敛

- 通过明确的 proxy 地址定位，禁止用空 MAC 做相等匹配；
- 成功收到设备端删除响应后统一清理 MAC、按键配置与同步缓存；
- `deleteSwitch(switchData:)` 仅保留防御性一致性检查，不承担替代远端解绑的职责。

#### B4. 同步失败时不再表现为“信息无条件丢失”

推荐保留两种状态：

- 用户期望：取消 proxy / 取消 Group；
- 设备实际或待清理：原 L1、原 MAC、原 Group。

UI 至少应显示“待解绑/同步失败”，并保留原 proxy 名称或 ID 供用户识别和重试，不能同时显示“未绑定”又允许删除绕过清理。

如果不增加新的 UI 状态，最稳妥的最小行为是在同步失败后恢复编辑前的显示与关联信息。

#### B5. 复用原 L1 的覆盖式绑定完成历史恢复

对于已经由旧逻辑产生的数据：

- 扫码发现相同 MAC 已保存在 L1，但用户当前选择的 proxy 也是 L1 时，允许继续绑定，不再提示“已经被 L1 关联”；
- 保存后复用现有 proxy 同步流程，让 L1 覆盖或更新旧 MAC、按键和 publish 配置；
- 如果相同 MAC 位于 L1，但用户选择的是其他 proxy，继续阻止绑定，避免双 proxy；
- L1 离线时同步仍会失败，保留待重试状态。

SDK 当前行为：

- 新 MAC 与 L1 旧 MAC 不同：先生成旧 EnOcean 解绑/删除消息，再添加新 MAC；
- 新 MAC 与旧 MAC 相同：不重复添加 MAC，但会比较新旧 `SwitchKey`，删除旧按键 publish 并写入新的虚拟组目标。

因此不需要新增 orphan 类型、独立清理页面或额外恢复服务。历史目标节点的旧虚拟组订阅仍由主路径的完整删除规划负责，不能因为 L1 支持覆盖就直接忽略。

优点：

- 修复导致假成功的根因；
- 不掩盖真实设备状态；
- 正常路径和历史异常路径都可收敛；
- 避免双 proxy。

代价：

- 必须准确比较“已绑定节点”和“用户当前选择的 proxy”是否为同一节点；
- 必须做真机离线、重新上线与覆盖重配验证。

### 方案 C：保存失败时完全回滚所有 Switch 编辑

处理：

- proxy 或任一 Group 同步失败，就恢复保存前的全部 `DeviceSwitchData`。

优点：

- UI 不会丢失原关联；
- 模型容易理解。

缺点：

- 同一轮可能已有部分节点解绑成功，整体回滚会重新把已成功节点当作旧状态；
- 不能自然保留部分成功进度；
- 与现有 `unbindGroupAddresses`、`deleteProxyNodeAddress` 的待清理设计不一致。

结论：可以作为不扩 UI 的短期策略，但长期不如方案 B 的显式两阶段状态可靠。

## 5. 推荐实施范围

建议确认采用方案 B，并分两部分实施。

### 第一部分：主路径根因修复

范围限制在 App：

1. 修正 `DeviceSwitchData.getNeedSyncDatas(deleteSwitch:)`：
   - 删除时覆盖 `bindGroups + unbindGroups`；
   - 删除时覆盖 `proxyNode + deleteProxyNode`；
   - proxy 按明确地址解析，不依赖当前 Group 或已经清空的 Switch MAC。
2. 修正 `MeshNetworkManager.deleteSwitch(switchData:)`：
   - 禁止空 MAC 匹配；
   - 通过有效 proxy/待删除 proxy 地址做防御性缓存收敛；
   - 不把本地清缓存当成远端删除成功。
3. 修正编辑失败后的可观察状态：
   - 保留 pending cleanup 信息；
   - 不显示为完全“未绑定”并允许绕过删除；
   - 不丢失重试所需的原 proxy、MAC、Group 信息。
4. 删除成功前保留旧虚拟组，避免还有真实订阅时先移除本地 Group 对象。

### 第二部分：原 L1 覆盖式恢复

1. 扫码命中旧绑定节点时，比较它与当前选中的 proxy：
   - 同一节点：允许继续，交给现有绑定同步覆盖配置；
   - 不同节点：继续提示已绑定，禁止产生双 proxy。
2. 不新增 orphan 数据模型、清理页面或专用恢复服务。
3. 不在删除时无条件清空 L1 的节点真值；保留它用于识别旧 proxy 和驱动 SDK 的差异清理。
4. 覆盖同步成功后，由现有响应处理更新 L1 的 MAC、按键和 publish 缓存。

不需要修改 Kinetic switch QR payload、按键动作定义、CCT 修复逻辑、Panel UI 布局或其他设备模块。

## 6. 自动化验证计划

### 6.1 同步规划回归测试

覆盖以下状态矩阵：

1. 正常绑定状态：
   - 当前 Group 为 G；
   - 当前 proxy 为 L1；
   - 删除计划包含 G 的待解绑节点和 L1。
2. proxy 解绑失败状态：
   - 当前 proxy/MAC 已空；
   - `deleteProxyNodeAddress = L1`；
   - 删除计划仍包含 L1。
3. Group 解绑失败状态：
   - `bindGroupAddresses` 已不含 G；
   - `unbindGroupAddresses` 仍含 G；
   - 删除计划仍包含 G 中未清理节点。
4. proxy 与 Group 同时处于待清理状态：
   - 删除计划不得为空；
   - 不允许直接删除本地 Switch。
5. Switch MAC 为空：
   - 不得通过 `nil == nil` 命中无关节点。

### 6.2 状态与扫描回归测试

1. L1 离线，取消 proxy 并保存失败：
   - 原 proxy/MAC 或明确 pending 状态仍可见；
   - 重新进入页面仍可重试；
   - 删除不得假成功。
2. L1 重新上线并清理成功：
   - L1 节点 MAC、按键缓存清空；
   - Switch proxy 待删除地址清空；
   - 同一物理面板可以绑定其他 proxy。
3. 旧绑定恢复：
   - 相同物理面板、选择原 L1：允许继续绑定并覆盖配置；
   - 新物理面板、选择原 L1：覆盖旧 MAC 并建立新配置；
   - 相同物理面板、选择其他 proxy：继续阻止，不能制造第二个 proxy；
   - L1 离线：同步失败并保留可重试状态。

### 6.3 iPhoneOS 编译

修改位于共享 Common 业务代码，需使用 generic iPhoneOS、关闭签名验证：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

不使用 Simulator。

## 7. 真机验收清单

自动化和编译不能代替真实 Mesh 验收。至少覆盖：

1. 正常绑定后，L1 离线：
   - 取消 proxy 保存失败；
   - 取消 Group 保存失败；
   - 删除 Switch 不得提示完整成功。
2. L1 再次上线：
   - 重试清理成功；
   - 删除 Switch 成功；
   - 同一面板可绑定 L1 或其他 proxy。
3. 删除完成后检查：
   - 扫码不再提示旧 L1；
   - 旧面板不再通过 L1 控制旧 Group；
   - ON、OFF、Dim、CCT、Scene 均没有旧虚拟组残留影响。
4. 部分成功场景：
   - Group 内部分节点在线、部分离线；
   - 已成功节点不重复制造错误；
   - 未成功节点保留待清理状态；
   - 最终重试可以收敛。
5. App 重启、切换 Space、云端重新导入后：
   - pending cleanup 不丢失；
   - 不出现 Switch 已删但 Node 仍被 App 判定占用的状态。

## 8. 待确认

推荐确认实施方案 B，包含：

- 主路径根因修复；
- 原 L1 的覆盖式恢复；
- 不新增新的复杂 UI 页面，优先复用现有同步失败与重试界面；
- 不新增 orphan 数据模型或专用清理服务；
- 不允许在选择其他 proxy 时绕过旧 L1 形成双 proxy。

用户确认前不修改业务代码。
