# Site 网关删除误报、未发送 Reset 与修复方案

- 日期：2026-09-16。
- 分析基线：`b4716de0`，分支工作区 `fix-gateway`；分析开始时工作区干净。
- 范围：本轮分析代码、提交历史及既有测试，制定修复方案；不修改业务代码。
- SDK：工程锁定 `a6246b1b0409824a3227a9c7cad8140219feb182`；本地 `nordic-sig-mesh-sdk-worktrees/one-dev` 的 HEAD 与之相同，已核对相关实现。
- 最新方案：用户已改为 Owner／Editor 均需联网、服务器优先删除、取消 FORCE DELETE；以 `260916_1131_gateway_online_server_first_delete_decision.md` 为准。本文根因和提交历史仍有效，第 7 节仅保留此前方案的分析背景。

## 1. 结论

这是两个客户端问题叠加，WiFi Gateway 与共用详情页的其他 Site 网关均受影响。

1. **Site 网关错误进入了必须有 Space 的永久删除保护流程。** Site 添加的网关属于 Site 主网络，正常情况下找不到以该主网络 ID 为子网 ID 的 `SpaceData`。通用删除入口要求所有 `DevicePermanentDeletionContext.isPrepared` 为真，网关不满足，直接显示 `configuration_deletion_cleanup_pending` 并返回。因此既没有调用 `MeshAPI.resetNodes`，也没有进入真正的 Reset 失败／强制删除弹窗。
2. **云端删除已成功，但 Site 导入把“等待本地 Reset”的网关作为普通云端缺失项移除了。** Owner 完整快照缺失已上传过的网关时，当前导入逻辑删除本地 Node 和 GatewayModel，没有排除 `serverDeletionPendingLocalReset`。该本地删除不发蓝牙命令，硬件仍在 Mesh 中。

网关是否新添加、是否有历史残留、是否关联 Space，均不是本次提示的直接判断依据。关联 Space 只是给网关增加跨子网控制能力，不会使 Site 主网络中的网关变成某一个 Space 的普通设备。

用户已确认本次使用 **Site Owner（创建者）账号**，与第二项的 Owner 完整快照删除分支吻合：服务器删除成功后，返回 Site 的刷新会按云端缺失项移除本地待 Reset 网关。账号角色这一待确认项已解决；Editor／Visitor 的不完整快照不会执行这段删除，但仍受 Reset 前的 Space 检查影响。本结论依据用户复现信息与代码调用链，尚未采集真机运行日志。

## 2. 操作步骤与代码对应

| 操作 | 代码行为 | 对问题的影响 |
| --- | --- | --- |
| Site → Click to add a gateway | `SiteViewController.addGateway` 进入 `SiteDeviceAddViewController`；添加前切换到 Site 主网络 | Node 属于 Site 主网络，不以单个 Space 为归属 |
| 打开 WiFi Gateway 并连接 | WiFi 控制器继承 `GatewayViewController`，使用同一套 Mesh Proxy 连接及删除实现 | WiFi 页面没有独立删除覆盖方法 |
| Delete → Continue | `deleteBtnAction` 调用 `beginGatewayDeletion` | 权限检查后开始服务器优先删除 |
| 服务器成功 | 保存 `serverDeletionPendingLocalReset = true`，然后调用 `resetNodeAfterServerDeletion` | 云端 Gateway 已删除，本地应继续完成 Reset |
| 通用删除准备 | `DeviceProtocol.deleteNodes` 创建 Space 删除上下文，检查全部 `isPrepared` | Site 网关因缺少匹配 Space 被拦截 |
| 出现误报 | 显示清理未完成；回调为成功列表空、失败列表含网关 | Reset 调用位于 guard 后，根本没执行 |
| 用户返回 Site | `finishGatewayDetailPresentation` 发起静默 Site 刷新 | 云端列表已没有该网关 |
| 导入 Owner 完整快照 | 已上传的本地网关在服务器列表中缺失 → `forceRemove`／`Node.delete`、`GatewayModel.delete` | 本地列表消失，设备未物理退网 |

关键位置：

- `SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift:446`：添加前选择 Site 主网络。
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:9`：继承关系。
- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:1164`：删除确认入口。
- 同文件 `:1178`、`:1237`、`:1279`：服务器删除、持久化待 Reset 标记、调用通用删除。
- `SunSmart/Main/Device/Model/DeviceProtocol.swift:123`：Reset 前的上下文检查。
- `SunSmart/Main/Site/Controller/SiteViewController.swift:895`：退出详情后静默刷新。
- `SunSmart/Common/Data/ImportData.swift:951`：完整快照删除缺失本地网关。

## 3. 提示的准确判断条件

### 3.1 本次实际命中的入口

`DeviceProtocol.deleteNodes` 为每一个目标 Node 创建 `DevicePermanentDeletionContext`，只要其中任意一个 `isPrepared == false`，就显示该提示并返回。

上下文根据 Node 所在网络的 UUID 找到 Site 的 Spaces，再寻找 `space.meshNetworkId == node.subNetworkId` 的 Space。`prepare()` 必须全部满足：

1. 找到了 Space，且 Node 仍有 network。
2. 能获取 Space 恢复上下文，且账号、区域、Space 恢复代次等上下文仍有效。
3. Space 的 Mesh UUID 和子网 ID 与 Node 匹配。
4. 当前 Mesh Manager 使用的 network 与捕获 network 是同一实例。
5. 当前 Network Key 的 network ID 与 Space 子网 ID 相同。
6. 没有未完成的 Space 导入。
7. Space 数据库检查点创建／读取成功。
8. 删除日志成功写入本次 Node 的 prepared 记录。

Site 主网络网关在第 1 项就会失败，`isPrepared` 保持默认值 false。这里没有“新设备可通过”的分支，也没有先检查该网关是否实际存在需要清理的场景、定时、Path 或 Trigger Zone 引用。

因此文案把“当前删除场景不适用 Space 上下文”错误表达成了“已经有设备数据没有清理完”。重新进入任意 Space 并不能改变网关的所属网络，无法解决本次问题。

### 3.2 同一文案的其他用途

- 强制删除前：任一失败 Node 不能再次准备删除上下文，也会显示该文案。
- 删除完成后：`showCompletion(space:)` 在删除日志仍待清理时显示；日志读取失败也按待清理处理。
- 删除完成后：`showCompletion(contexts:)` 对缺失 Space 的上下文也直接视为待清理。

所以仅删除 Reset 前的 guard 仍不完整：结束提示和强制删除路径也依赖 Space，且还会削弱普通设备原本需要的删除保护。

证据：`DevicePermanentDeletionCleanup.swift:16–42`、`:277–290`，`SpaceConfigurationSafety.swift:165`，`DeviceProtocol.swift:163`。

## 4. 为什么没有 Reset，却在 Site 消失

### 4.1 Reset 未调用

当前服务器优先流程本身符合既有最终决策。错误发生在服务器成功后的 App 本地准备阶段，早于 SDK 调用，不能归因于 WiFi 连接状态、蓝牙信号弱或固件不响应。

SDK 的正常链路是：

1. `MeshAPI.resetNodes` → `MeshAddDeviceManager.resetNodes`。
2. 对目标地址发送标准 `ConfigNodeReset`，默认单节点等待 10 秒。
3. 收到 `ConfigNodeResetStatus` 后，SDK 的配置客户端移除本地 Node。
4. App 完成业务数据清理及页面刷新。

SDK 已有这项能力，无需为本次服务器优先修复增加延迟删除接口。

注意，“已连接”在此应按 Mesh Proxy 可发送命令的状态判断。WiFi／互联网连接成功与蓝牙 Mesh 连接就绪是不同状态；但本次 guard 不检查这两者，无论是否就绪都会先被错误拦截。

### 4.2 Site 消失的独立条件

`SiteData` 导入满足以下条件时删除本地网关：

- `gatewaySnapshot.isComplete == true`：当前实现要求 Owner，且 `gateways` 列表能形成有效完整快照。
- 本地 `lastUploadCloudTimestamp != nil`。
- 本次服务器列表中没有相同 MAC 的网关。

这段逻辑没有检查：

- `serverDeletionPendingLocalReset`。
- 是否已收到 Reset Status。
- 是否用户明确选择 FORCE DELETE。

`network.forceRemove(node:)` 只执行本地 Node 数据删除、内存数组移除和时间戳更新，不会发送 `ConfigNodeReset`。因此“Site 列表消失”不是“网关物理退网成功”的证据。

在误报返回的直接回调中，`successNodes` 为空，详情页不会走成功分支中的 `gatewayModel.delete()`。后续 Site 导入是应重点修复的另一个删除入口。

一旦本地 Node／设备密钥信息也已随刷新删除，当前 App 的正常连接重置入口就可能丢失。后续修复可以保护仍保有上下文的待删除记录；对已经被旧版本完全移除的记录，不能承诺仅安装修复版即可自动恢复，通常仍需手动重置再添加。

## 5. 引入历史

以下时间均为 Git 记录的 UTC+08:00；作者时间与提交时间不同的条目分别列出。

| 提交 | 时间 | 与本问题的关系 |
| --- | --- | --- |
| `d2784c94` — `fix: reset readd device timed issues` | 2026-08-03 20:19:09 | 引入 `DevicePermanentDeletionContext`，统一删除后的业务引用清理；当时不要求 Reset 前必须有 Space |
| `86ac431c` — `feat: force clear spaces` | 2026-08-18 11:40:03 | 引入现有统一服务器优先流程和持久化待本地 Reset 标记 |
| `081f1c69` — `fix: timezone bugs` | 作者 2026-08-18 17:35:29；提交 2026-08-19 11:27:22 | 形成当前 Owner 完整快照删除缺失本地网关的实现，未排除待 Reset 标记；该“云端缺失则删本地”的策略本身可追溯至 2026 年 2 月 |
| `abfbe5a7` — `fix: space trigger zone bugs` | **作者 2026-09-07 17:46:06；提交 2026-09-08 11:02:44** | **直接回归提交：增加 Reset 前 `allSatisfy(isPrepared)`、强制删除准备检查、Space 删除日志／检查点保护，以及本次错误文案** |

`abfbe5a7` 的父版本对没有 Space 的上下文仍可执行普通扩展清理，也不会阻断 `MeshAPI.resetNodes`。该提交将针对 Space 引用完整性的保护要求扩大到了通用删除入口，没有覆盖 Site 主网络网关这一合法场景。

结论区分：**误报与未发送 Reset 直接来自 `abfbe5a7`；返回 Site 后丢失待 Reset 记录是更早的导入策略遗漏，被本次提前返回稳定暴露出来。**

## 6. 其他网关的影响范围

| 类型／场景 | 分流及归属 | 结论 |
| --- | --- | --- |
| WiFi，CID `0x0A78` / PID `0x2721` | `WiFiGatewayViewController`，继承通用 Gateway 删除；Site 主网络 | 同样受影响，用户当前场景 |
| 内置 4G，PID `0x2701`、`0x2702` | `GatewayViewController`；Site 主网络 | 同样受影响 |
| `0x2703` 或其他来自服务器配置／Gateway 导入的型号 | 只要作为 Gateway 进入当前详情页，就走同一基类删除 | 同样存在代码级风险，不受 DFU 类型限制 |
| 已关联一个或多个 Space 的 Site 网关 | Node 仍归属 Site 主网络；Associated Spaces 不构成其 Space 删除归属 | 关联操作不能修复该问题 |
| 离线 Site 网关 | 同样先被 Space 准备 guard 拦截 | 连正常的 Reset 失败 → FORCE DELETE 分支也可能无法进入 |
| 合法归属于 Space 的历史／异常网关记录 | 是否通过取决于真实 Space、当前网络和保护状态 | 不能仅按 PID 一概豁免，应按业务入口和网络归属区分 |
| Space 内灯具、开关、应急等设备 | 有真实 Space 清理范围 | 此保护有必要；本次不整体移除 |

内置产品来自 `SunSmart/devices_config.json`；WiFi 分流见 `MeshNetwork+SunSmart.swift:1927` 和 `SiteViewController.swift:3253`。当前没有独立以硬件能力识别所有 4G 网关的逻辑，非 WiFi 的 Gateway 页面走基类。

各品牌共享该业务实现，风险并非 SunSmart 单一 target。Space 的旧 `GatewaysViewController` 当前是空列表占位实现，不构成另一套有效删除逻辑。

## 7. 推荐修复方案

### 7.1 保留服务器优先，建立 Site 网关专用删除上下文

以 `docs/260817_1820_gateway_delete_server_first_final_decision.md` 的最终决定为基础。当前实现还支持已确认服务器删除的持久化记录直接重试本地 Reset，保留这一能力。

建议在 Gateway 公共基类接入一个范围明确的网关删除协调器／上下文，供 WiFi 和 4G 共用：

1. 在请求服务器前预检 Site、网关 MAC、Node UUID／地址、Site 主网络 ID、当前网络实例以及必要的 Reset 数据，捕获稳定上下文。
2. 执行现有权限检查、禁止普通云端重注册、等待在途授权请求及服务器删除；保持失败提示和 30 秒上限。
3. 服务器成功后可靠保存待本地 Reset 状态；检查保存结果，不忽略持久化失败。
4. 通过现有 `MeshAPI.resetNodes` 向捕获的目标发送 Reset。连接中断／无回执按 Reset 失败处理，不能把服务器成功当作设备成功。
5. Reset 成功后在捕获的 Site／主网络范围提交本地清理；强制删除也通过同一提交点。
6. 本地清理完成且持久化结果确认后，才显示 Done、关闭页面并刷新 Site。

Gateway 删除不创建虚构 Space、不执行与其无关的 Space Path／Trigger Zone 事务。通用 `DeviceProtocol` 的真实 Space 删除保护保持有效。

### 7.2 补齐 Site 导入对删除会话的保护

完整云端快照缺少网关时，先判断该网关是否属于本机仍未完成的删除会话：

- `serverDeletionPendingLocalReset` 为真：保留本地 Node、GatewayModel 和可重试入口，不进入普通缺失项删除。
- 服务器删除进行中：同样防止并行 Site 导入提前移除当前 Reset 目标。
- 普通网关确实已从服务器消失：保留现有完整快照对账语义。
- Editor／Visitor 不完整快照：继续禁止根据列表缺失删除本地 Node。

**实现注意：** `isServerDeletionInProgress` 当前只是 GatewayModel 实例上的内存字段，而导入会重新 `GatewayModel.load`，新实例中该字段为 false。仅在导入处检查这个字段不足以解决进行中的竞态。需让导入能按账号／区域／Site／网关身份查询同一个删除会话，或增加语义清楚的持久化阶段；不能把“服务器已成功”的标记提前写成 true 来代替“正在请求”。

Site 展示层应保留尚可重试的待删除网关；普通时区同步、Save、自动授权和普通云同步应排除待删除会话。服务端关联已经删除后，不能把缓存 Associated Spaces 再当作仍有效的关联同步回去。

### 7.3 Reset 失败、取消及重启恢复

- 服务器失败／超时：不发 Reset，不清本地，维持现有服务器失败提示。
- Reset 失败／超时：显示已有网关 FORCE DELETE 弹窗与手动重置说明。
- Cancel：本地记录保留，可重新连接后重试 Delete；返回 Site、刷新、重启均不能丢失重试入口，也不能重注册云端 Gateway。
- FORCE DELETE：明确执行仅本地永久删除；此路径仍需用户手动重置硬件，复用现有说明。
- 本地清理失败：保持可恢复的待清理状态，不显示 Done、不复用“重新进入 Space”文案。

优先复用现有持久化标记；对“Reset 已成功但本地清理中断”的恢复补齐最小必要阶段／记录。SDK 在收到 Reset Status 后会移除 Node 并断开其 network 引用，清理必须使用事先捕获的身份与网络，不能事后依赖 `node.network`。仅有本地 Node 不存在也不能被 UI 当作硬件 Reset 成功的证明。

### 7.4 本地清理边界

- 删除目标 GatewayModel、目标 Node 的持久数据和必要的网关／OTA 等扩展缓存。
- 保留 Node 正常移除的 SDK 语义；强制删除不直接照搬导入用的 `forceRemove` 当作 Reset。
- 使用明确的 Site UUID、网络 ID、MAC 和 Node 身份定位，避免其他 Site 同地址对象受影响。
- 删除结果须显式区分成功、Reset 失败、本地持久化失败；不以可选拓扑结果是否为空推断成功。
- 需要新提示时同步英文和简体中文，并在所有共享 target 检查资源；诊断日志仅在 `#if DEBUG` 中输出，记录阶段和范围，不打印密钥／授权内容。

### 7.5 预计涉及文件

- `GatewayViewController.swift`：替换通用 Space 删除入口，连接专用网关状态机。
- Gateway Model 目录新增小型删除协调器／上下文；必要时扩展 `GatewayModel` 与 `Database.swift` 的最小恢复状态。
- `ImportData.swift`：保护待 Reset 和进行中的网关删除会话。
- Site 列表／网关操作策略：确保待删除记录可见、可重试且不能恢复普通上传。
- 相关测试、本地化及必要的 Xcode target 文件成员配置。

预计无需改 SDK、服务端接口或改变删除顺序。若实现发现必须改 SDK，按项目规则使用既有本地开发路径，并验证全部引用 target。

## 8. 验证计划

现有 `GatewayForceClearSpacesContractTests` 主要检查控制器字符串及调用顺序，没有实际执行 `DeviceProtocol.deleteNodes` 的准备门；`DeviceDeletionRecoveryExecutionTests` 的有效删除场景均有 Space fixture。因此既有测试不足以发现本次 Site／Space 范围错配。

应增加可注入服务器、Reset 发送器和持久化边界的行为验证：

| 场景 | 核心断言 |
| --- | --- |
| Site 主网络、没有任何 Space 的新 WiFi 网关 | 服务器成功后 Reset 发送一次；不出现 Space 清理提示 |
| 4G `2701`／`2702`／`2703`，空或非空 Associated Spaces | 共用相同删除策略，均不要求有匹配 Space |
| 服务器失败／超时 | Reset 零次，本地数据保留 |
| 已确认服务器删除、再次 Delete | 使用待删除记录重试本地 Reset，不普通重注册 |
| Reset 成功 | 收到成功回执后提交清理；本地成功后才显示 Done |
| Reset 失败 + Cancel | 本地记录和重试能力保留 |
| Reset 失败 + FORCE DELETE | 只有用户确认后删除本地，保留手动重置语义 |
| Owner 完整快照缺少待 Reset 网关 | 不删除待处理 Node／GatewayModel |
| Owner 完整快照缺少普通已上传网关 | 原有缺失项对账仍生效 |
| Editor／Visitor 不完整快照 | 不按缺失项删除；待删除记录不能被 UI 权限投影意外丢弃 |
| 服务器成功前后并行 Site 刷新、迟到回调 | 不提前删除目标，不重复完成，不恢复注册 |
| 保存待删除状态失败、本地清理失败、App 重启 | 不假报成功；保有可恢复状态 |
| SDK 移除 Node 后 `node.network == nil` | 仍按捕获的 Site／网络范围完成清理 |
| 普通 Space 设备删除及持久化失败 | 原删除日志／检查点保护保持生效 |

构建阶段直接使用 `xcodebuild`，以 generic iOS 真机 SDK、禁用签名验证共享业务的 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux；不使用 Simulator，不重定向日志。

真机阶段使用允许的 `MtestiPhone15`，结合可用 WiFi 与 4G 网关执行：

1. 添加 → 建立蓝牙 Mesh Proxy 连接 → Delete → Continue。
2. 核对 Reset 发送／回执、网关恢复未配网广播、无需手动重置即可重新添加。
3. 测试中途断连、Cancel 后返回 Site／重开 App，再连接重试。
4. 测试 FORCE DELETE 提示和实际后果；分别检查 Owner 与 Editor。
5. 检查中英文提示、弹窗布局和受影响页面；最终体验由人工确认。

本轮未运行 App、未连接硬件、未执行蓝牙抓包或构建。以上是源代码和提交历史分析，不代替修复后的真机验收。

## 9. 已确认信息与既有决定

- 用户已确认：本次复现使用 Site Owner（创建者）账号，与“返回 Site 后按完整云端快照删除本地缺失网关”的分支吻合。
- 当前没有影响上述修复规划的待确认产品问题。
- 已有最终决定可直接沿用：服务器优先、服务器接口幂等、30 秒上限、Reset 失败后的 Cancel／FORCE DELETE 语义。无需为这些已确认规则重复询问。
- 本轮交付为分析和计划；业务修复尚未实施。
