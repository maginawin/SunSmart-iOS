# Node `createdTimestamp` 需求分析与开发方案

> 日期：2026-09-01  
> 范围：SunSmart App 当前工作树、本地 NordicSigMeshSDK、Site/Space 服务器同步约定  
> 状态：App 与本地 SDK 已实现并完成静态合同、iPhoneOS 编译验证；服务器与真机联调待执行

## 1. 结论

需求的核心方向合理：把 `createdTimestamp` 作为同一 Node UUID 不同“入网代次”的单调版本，在服务器保留 UUID 主键的前提下，可以阻止旧手机中的历史 Node 快照覆盖较晚创建并正在使用的 Node。

比较条件使用“大于等于”也是合理的：

- 等于：表示同一代 Node 的幂等更新，应允许更新普通属性；
- 大于：表示较晚重新添加或重新 Provision 的 Node，可替换旧代 Node；
- 小于：表示较旧快照，必须拒绝对当前 Node 的更新、替换或删除。

经确认，本次开发只覆盖 `/sitespace/sync/siteprops` 与 `/sitespace/sync/spaceprops` 中 Node 的 `createdTimestamp` 传输，以及这两类服务器数据回读后的本地解析和持久化。明确不新增 `/sitespace/sync/nodeprops`，不改变现有快照差集删除，不增加删除墓碑，也不修改 UUID 主键。

所有 SDK `Node` 类型都增加该属性，包括 Gateway 对应的 Node。Gateway Node 出现在 Site/Space 的 `nodes[]` 中时必须携带 `createdTimestamp`；“Gateway payload 保持不变”仅指独立 Gateway 注册接口不单独扩展字段或改动请求结构。

服务器冲突行为按以下语义记录：当上传 Node 的 `createdTimestamp` 小于服务器当前同 UUID Node 的时间戳时，服务器删除/丢弃本次请求中的低版本 Node，保留服务器现有的高版本 Node。若“删除版本冲突的 Node”实际是指删除服务器现有高版本 Node，则会与本需求目标相反，必须在开发前纠正。

## 2. 时间值定义

建议把协议定义固定为：

- 字段名：`createdTimestamp`；
- 类型：JSON 整数，对应客户端与服务器的 64 位有符号整数；
- 单位：自 1970-01-01T00:00:00Z 起的整秒数；
- 合法范围：大于等于 0；
- `0`：历史数据或未知创建时间的兼容哨兵值；
- 非 0：Node 本次在 App 本地成功创建/Provision 时的手机时间；
- 创建后不可因编辑名称、配置、移动 Space、同步、App 重启或服务器回读而改变；
- Node 被真正重新 Provision 时属于新代 Node，应产生新的值。

Unix Epoch 秒本身是绝对时间，不带时区。需求中的“无时区信息”不需要先转换成本地时区字符串，也不应使用 `DateFormatter`；直接取 Epoch 秒即可。

## 3. 当前 App/SDK 源码事实

### 3.1 当前工作树只存在两个所述上传接口

`NetowrkReqeustApi.swift` 当前声明：

- `/sitespace/sync/siteprops`：由 `siteAdd` 与 `siteUpload` 共用；
- `/sitespace/sync/spaceprops`：由 `spaceUpload` 使用；
- 当前工作树未找到 `/sitespace/sync/nodeprops` 的路由、枚举或调用。

证据：

- `SunSmart/Common/Network/NetowrkReqeustApi.swift:274-295`
- `SunSmart/Common/Network/NetowrkReqeustApi.swift:396-423`
- 全工作树对 `nodeprops`、`nodeProps`、`sync/node` 的检索无结果。

`nodeprops` 不在当前 App 中，本次已确认不新增、不接入，也不纳入测试和验收范围。

### 3.2 Site/Space 同步最终共用 Space 的完整 Node 导出

当前同步链路为：

- Site 同步：`SiteData.export(spaceIds:)`；
- Space 同步：`SpaceData.export()`；
- Space 导出遍历 Mesh Network 内 Node，先用 `JSONEncoder` 编码 SDK `Node`，再附加 App 扩展字段，最后写入 `nodes[]`；
- Gateway 注册另有 `Node.export()`，但不属于本次 Site/Space 同步范围。

证据：

- `SunSmart/Common/Cloud/CloudSynchronizationManager.swift:73-95`
- `SunSmart/Common/Data/ExportData.swift:219-255`
- `SunSmart/Common/Data/ExportData.swift:641-649`
- `SunSmart/Common/Data/ExportData.swift:656-674`

由于 Gateway 注册也复用 SDK `Node` 编码，如果直接把字段加入 SDK 通用 Codable，会同时改变独立 Gateway 注册接口的 Node payload。为保持范围聚焦，推荐由 SDK 负责所有 Node（包括 Gateway Node）的属性、创建赋值与 SQLite 持久化，由 `SpaceData.export()` 在生成 Site/Space 的 `nodes[]` 时显式写入 `createdTimestamp`。这样 Site 与 Space 共用一处导出改动；其中的 Gateway Node 同样带字段，而独立 Gateway 注册接口和其他 Node payload 保持不变。

### 3.3 服务器 Node 导入也共用 SDK Codable

当前至少有三条 Node 解析路径：

- Space 数据导入中的 `JSONDecoder.decode(Node.self, ...)`；
- Site Gateway 数据经 `Node.import(...)` 后解码；
- 独立 `Node.import(...)`。

证据：

- `SunSmart/Common/Data/ImportData.swift:1340-1359`
- `SunSmart/Common/Data/ImportData.swift:1983-2005`

为避免修改 SDK 通用 Codable 后影响其他 Node JSON 场景，App 在新建服务器 Node 对象时把缺失或 `null` 统一解释成 `0`。当 Site Gateway 数据与已有本地 Node 做字段合并或同身份替换时，缺失、`null` 或非法字段只表示服务器未提供该值，不能覆盖已有的本地时间戳；只有 payload 中显式存在的合法非负整数才可覆盖缓存。

### 3.4 Node 模型和本地持久化属于 NordicSigMeshSDK

`Node` 是 SDK 的 `Codable` 类型。当前 SDK：

- `Node` 没有 `createdTimestamp` 属性或 CodingKey；
- SQLite `nodes` 表没有相应列；
- 数据库旧表已有按列检查并增列的迁移模式；
- Node 加载与 `save()` 都需要同步增加字段；
- 本地 Provision 完成时创建 Node，然后加入 Mesh Network。

证据：

- SDK `nRFMeshProvision/Mesh Model/Node.swift:34-35`
- SDK `nRFMeshProvision/Mesh Model/Node.swift:307-357`
- SDK `nRFMeshProvision/Mesh Model/Node.swift:452-510`
- SDK `MeshLib/MeshDatabase.swift:340-387`
- SDK `MeshLib/MeshDatabase.swift:445-504`
- SDK `MeshLib/MeshDatabase.swift:744-784`
- SDK `MeshLib/MeshDatabase.swift:1125-1200`
- SDK `Provisioning/ProvisioningManager.swift:485-506`

本地开发路径 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev` 已存在且工作树干净。其 HEAD 为 `c480ffafb0c5fdd072c92439ea0a747790dcba21`；App 共享 workspace 当前仍锁定远程 `release` 的 `9504e5ba7286205f8d4749d8127bf2178b19d9a2`。本地 SDK HEAD 是该锁定 revision 的后继，但 App 共享构建并未使用本地 HEAD。

### 3.5 当前删除通过“Node 从下一次完整快照中消失”表达

设备删除流程在 Mesh Reset 成功或 FORCE DELETE 后把 Node 从本地 Mesh Network 移除，再保存 Space 并触发数据变化同步。下一次 `SpaceData.export()` 的 `nodes[]` 中已经没有该 Node。

证据：

- `SunSmart/Main/Device/Model/DeviceProtocol.swift:115-155`
- `SunSmart/Main/Device/Controller/DeviceBaseViewController.swift:184-200`

该事实意味着快照差集删除本身不能获得已移除 Node 的 `createdTimestamp`。用户已确认本次不处理这个边界：不修改差集删除、不增加墓碑，也不扩展 Node 删除协议。它作为已接受的范围外风险保留。

### 3.6 当前同步结果只有整体成功或整体失败

Space 同步成功时，App 直接把 `lastUploadCloudTimestamp` 更新为当前 `lastUpdate`；失败时只记录通用 `syncCloudError`。当前没有 Node 版本冲突、部分成功或服务器权威 Node 回读的专用处理。

证据：

- `SunSmart/Common/Cloud/CloudSynchronizationManager.swift:845-887`

用户已确认版本冲突由服务器删除/丢弃低版本 Node。按本方案的解释，服务器保留高版本 Node，并可按服务器既定语义处理请求剩余内容；App 本次不新增冲突错误类型、部分 ACK 或重试抑制逻辑。低版本 Node 仍可能保留在本地并在后续 Site/Space 同步中再次出现，但服务器比较必须持续阻止它覆盖高版本 Node。

## 4. 已确认的需求边界

### 4.1 字段与历史值

- API 字段统一为 `createdTimestamp`。
- 需求末尾的 `createTimestamp` 视为服务器内部旧列名或文字笔误；App JSON 不新增第二个近似字段。
- 历史 App、历史 SDK 本地数据库及服务器历史 Node 均使用 `0`。
- 不推算、不回填虚构的历史正数时间；版本保护从新版本 App 创建的 Node 开始生效。

### 4.2 版本冲突

本方案按以下服务器语义执行：

- 输入值大于服务器当前值：允许较新代 Node 更新或替换旧代；
- 输入值等于服务器当前值：允许同一代 Node 幂等更新；
- 输入值小于服务器当前值：服务器删除/丢弃本次请求中的低版本 Node，服务器现有高版本 Node 不得被覆盖或删除。

服务器的具体返回结构不在当前 App 仓库中。本次 App 不增加专用冲突错误、冲突 UUID 解析、部分 ACK 或重试抑制逻辑。

### 4.3 明确不改的范围

- 不新增或接入 `/sitespace/sync/nodeprops`。
- 不修改现有 Node 快照差集删除。
- 不增加 `deletedNodes[]` 或其他删除墓碑。
- 不修改显式 Node 删除、Site/Space 删除、Gateway 注册、转移或其他服务器接口。
- 不引入服务器 generation ID，不修改 UUID 主键。
- 不处理历史 Node 之间同为 `0` 时无法区分代次的问题。

### 4.4 已接受的时钟风险

手机生成的 Epoch 秒不是可信服务器时钟：

- 手机时间落后，可能让合法的新 Node 被判定为旧版本；
- 手机时间超前，可能产生过大的版本并长期阻塞后续合法更新；
- 秒级精度无法区分同一秒内的两次重新 Provision。

以上风险已接受，本次不扩大方案。

## 5. 最终开发方案

### 阶段 A：NordicSigMeshSDK Node 与 SQLite

在本地 `one-dev` SDK 中完成：

1. 为所有 `Node` 增加 Int64 `createdTimestamp`，包括 Gateway 对应的 Node，业务默认值为 `0`。
2. 只在本地真实新 Node 的 Provision/手动创建入口赋手机当前 Epoch 秒。
3. 不在数据库加载复用的通用构造器里赋当前时间，避免把历史 Node 误判为新 Node。
4. Node copy/truncate 时原样复制，不能重新生成。
5. `nodes` SQLite 表增加非空 Int64 列，默认值为 `0`；旧数据库迁移增列后，历史行自然为 `0`。
6. Node load/save 同步读写该列，后续普通保存、编辑、同步与重启不改变值。
7. 为保持接口范围聚焦，不把该字段加入 SDK 通用 Node JSON 编码；Site/Space JSON 由 App 显式处理。

由于 App 需要把服务器值写回 Node，SDK 需提供受控的恢复入口或可写属性。实现时优先采用语义明确的恢复入口，避免业务代码随意重置创建时间。

### 阶段 B：App Site/Space 导出

1. 在 `SpaceData.export()` 的唯一 Node 遍历处，把已持久化的 `node.createdTimestamp` 写入每个 `nodes[]` 对象；Gateway Node 只要位于该数组中也必须写入。
2. Site 同步包含 Space 时自然复用同一导出；不在 `siteUpload`、`spaceUpload` 网络层分别重复修改。
3. 历史 Node 从 SDK 数据库加载为 `0`，直接上传 `0`；上传过程不生成当前时间，也不回写新值。
4. 独立 Gateway 注册使用的 `Node.export()` 保持不变；这不影响 Gateway Node 自身拥有并持久化 `createdTimestamp`，也不影响它在 Site/Space `nodes[]` 中携带该字段。
5. 不增加 `nodeprops` 路由或调用。

### 阶段 C：App Site/Space 回读

1. 在 Space `nodes[]` 解码完成后读取 `createdTimestamp`：缺失或 `null` 为 `0`，整数值原样保存。
2. Site 返回中出现 Node 的导入路径复用同一归一化辅助逻辑，避免不同入口行为不一致。
3. Site Gateway 与已有本地 Node 合并或替换时，只有原始 payload 显式包含合法非负整数才覆盖缓存；字段缺失、`null` 或非法时保留缓存值。
4. Node 保存到 SDK SQLite 后，App 重启仍保持服务器返回或保留的值。
5. 不因普通 Site/Space 更新、名称编辑或配置变化重写该值。

### 阶段 D：中国大陆服务器联调

1. 服务器先部署到中国大陆环境。
2. App 切换到中国大陆服务器，对 `/sitespace/sync/siteprops` 与 `/sitespace/sync/spaceprops` 进行真实请求测试。
3. 分别验证历史值 `0`、相等值、较新值和较旧值。
4. 较旧值场景必须确认：服务器删除/丢弃的是本次请求里的低版本 Node，服务器现有高版本 Node 保持不变。
5. 中国大陆测试通过后，再由服务器团队决定其他区域的发布时间；本次 App 方案不增加运行时 feature flag。

### 阶段 E：SDK 发布与 App 依赖更新

1. SDK 改动先在 `one-dev` 与本地 App workspace 验证。
2. 按现有流程把已验证 SDK revision 晋升到远程 `release`。
3. 更新 App `Package.resolved` 到包含 `createdTimestamp` 的 release revision。
4. 共享工程继续使用远程 SDK，不提交本地绝对路径或本地 workspace。
5. Git commit、push、release 分支推进仍需单独明确授权。

## 6. 验证计划

### 6.1 SDK 单元与持久化测试

- 新本地 Provision Node：值位于创建前后的合理时间窗口内且大于 0。
- 历史 SQLite 表迁移：旧行加载为 0，重复初始化幂等。
- 新 Node 保存并重启加载：值不变。
- 同一 Node 多次保存、编辑和 copy/truncate：值不变。
- 服务器恢复入口写入 0 或正数后保存、加载：值不变。
- 数据库加载不能把 0 自动替换成手机当前时间。

### 6.2 App 合同测试

- `/sync/siteprops` 中实际上传的每个 `spaces[].nodes[]` 都有整数 `createdTimestamp`，包括其中的 Gateway Node。
- `/sync/spaceprops` 中每个 `nodes[]` 都有整数 `createdTimestamp`，包括其中的 Gateway Node。
- 历史本地 Node 上传 0，新建本地 Node 上传创建时的正数。
- 新导入的 Site/Space Node 回读缺失或 `null` 时为 0；已有 Gateway Node 在字段缺失、`null` 或非法时保留缓存值。
- 连续导出同一 Node，字段值不变。
- Gateway Node 自身拥有并持久化该字段；独立 Gateway 注册 payload 不因本次改动新增该字段。
- 当前工程仍不出现 `/sitespace/sync/nodeprops` 调用。
- 现有快照差集删除 payload 与行为保持不变。

### 6.3 中国大陆服务器矩阵

- 输入小于当前：丢弃低版本输入 Node，保留服务器高版本 Node。
- 输入等于当前：允许同代更新。
- 输入大于当前：允许新代更新或替换，并保存较大时间戳。
- 输入缺失或 `null`：按历史值 0 处理。
- 历史输入 0 与历史服务器 0：按相等值处理。
- 同一 Site/Space 含多个 Node 时，只按服务器既定规则处理冲突 Node，其他 Node 结果与接口返回需记录。
- 两个并发请求新旧交错后，服务器最终不能被较小时间戳覆盖。
- Site 与 Space 两个接口分别执行完整矩阵，不能只测其中一个。

### 6.4 真实集成验收

- 新 App 添加 Node 后立即同步，服务器保存正数时间戳。
- 同一 Node 后续编辑与多次同步，时间戳不变且更新成功。
- 历史 App 数据升级后同步，Node 时间戳为 0。
- 服务器返回字段缺失或 `null` 时，新导入 Node 为 0；已有 Gateway Node 不清除缓存中的正数值。
- 旧测试 App 离线一段时间后同步同 UUID 低版本 Node，服务器当前高版本 Node 不被覆盖或删除。
- App 删除 Node 后的现有快照差集删除行为没有因本次字段改动发生变化。

### 6.5 构建边界

SDK 修改后需验证所有引用 `NordicSigMeshSDK` 的品牌 target。当前工程可见五个 App target：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart
- Lumineux

先用本地 SDK workspace 完成联调与 generic iPhoneOS 构建，再在远程 `release` revision 更新后用共享 `SunSmart.xcworkspace` 重复构建。按项目规则不使用 Simulator。

现有 `scripts/check_nordic_sdk_dependency.sh` 仍断言只有四个引用 target，而当前工程已有五个。该脚本修复不属于本次 Node 时间戳范围；本次使用五个 scheme 的直接构建结果作为依据，并把脚本既有假失败单独记录。

## 7. 已确认决策与实施边界

1. API 字段统一为 `createdTimestamp`。
2. 历史 App、SDK 与服务器 Node 均为 0；只保护新版本创建的 Node。
3. 服务器删除/丢弃低版本输入 Node，保留现有高版本 Node。
4. 只修改 Site 与 Space 同步；不改 Node 同步和快照差集删除。
5. 中国大陆服务器先发布，App 可切换该环境进行真实比较测试。
6. 接受手机时钟和秒级精度风险；不引入 generation ID，不修改 UUID 主键。

## 8. 2026-09-01 本地实施结果

### 8.1 NordicSigMeshSDK

- 所有 `Node` 增加 Int64 `createdTimestamp`，默认值为 `0`。
- 真实 Provision 创建和公开的手动创建入口记录手机当前 Epoch 整秒。
- 数据库加载、历史转换与测试兼容构造器不生成当前时间，历史数据保持 `0`。
- Node copy 保留原值；服务器/持久化恢复入口把负数归一化为 `0`。
- SQLite `nodes` 表新增默认值为 `0` 的列，并完成建表、旧表增列、加载和保存闭环。
- 未把该字段加入通用 Node `CodingKeys`，因此独立 Gateway 注册 payload 不变。

### 8.2 App Site/Space 同步

- `SpaceData.export()` 在唯一 Node 导出边界向每个 `nodes[]` 对象显式加入 `createdTimestamp`；Site 同步复用该路径。
- Gateway 对应的 Node 只要出现在 Site/Space 的 `nodes[]` 中，同样包含该字段。
- 新导入的 Space Node 与 Site Gateway Node 回读均把缺失、`null` 转换为 `0`，正整数原样恢复。
- 已存在 Gateway Node 只有在原始 payload 显式包含合法非负整数时才更新并保存；merge/replace 遇到缺失、`null` 或非法字段时保留缓存值。
- 未新增 `nodeprops`，未修改独立 Gateway 注册导出、现有快照差集删除或任何墓碑协议。

### 8.3 自动验证

- `zsh scripts/check_node_created_timestamp.sh`：通过。
- App 与 SDK 两个工作树的 `git diff --check`：通过。
- 新增 SDK 测试文件的 iPhoneOS 类型检查：通过。
- 本地 `NordicSigMeshSDK` generic iPhoneOS 构建：通过。
- 使用本地 SDK 的五个 App scheme generic iPhoneOS 构建均通过：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。

整包 SDK 测试目前不能作为本次通过项：`swift test` 在 macOS 目标被 SDK 现有 UIKit 依赖阻断；iPhoneOS `build-for-testing` 又被既有 `LightLCFixedPropertyTests` 中 `DeviceProperty` 不符合 `Equatable` 的错误阻断。新增测试文件已经独立类型检查通过，以上阻断均不是本次 `createdTimestamp` 改动引入。

## 9. 仍待执行

- 中国大陆服务器部署后的 Site/Space 请求与版本冲突矩阵。
- 真机新建、重启持久化、历史数据库升级及 Gateway Node 实际 payload 验收。
- SDK revision 晋升到远程 `release`，以及 App 共享 `Package.resolved` 更新。

当前未修改共享工程的远程 SDK 锁定，也未执行 Git commit、push 或 release 分支操作。
