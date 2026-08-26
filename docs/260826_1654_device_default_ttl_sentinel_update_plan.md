# App 设备默认 TTL 哨兵值更新分析与开发方案

## 1. 结论

需求方向合理，范围已经确认：

1. **已确认的存量范围**：只修复后续实际生成并发送的配置消息；已经写入设备的 TTL `5` 不自动迁移，不增加一次性迁移任务，也不修改现有同步判定来主动发现 TTL 差异。
2. **已确认的 Neighbor 规则**：以前使用 TTL `0` 的构造点继续使用 `0`；以前不是 `0` 的构造点统一改为 `0xFF`。

实施采用**定点替换 + 保留 TTL 0 + 回归契约保护**，不要把 Lab TTL 接入这些设备侧配置，也不要全局替换工程内其他 `defaultTtl`。

## 2. 需求归一化

| 配置项 | 当前发送值 | 目标值 | 是否修改 | 说明 |
|---|---:|---:|---|---|
| Kinetic Proxy Model Publication | `5`（取自 App Network Parameters） | `0xFF` | 是 | 使用 Proxy Node 自身 Default TTL |
| Battery/AC Power Switch Key Config | `0xFF` | `0xFF` | 否 | 维持现有设备默认 TTL 语义 |
| EFC Scene Publication | `5`（取自 App Network Parameters） | `0xFF` | 是 | 使用 EFC Node 自身 Default TTL |
| EFC Action Config | `0xFF` | `0xFF` | 否 | 维持现有行为 |
| Group Add 路径生成的 Proximity Neighbor Config | `5`（取自 App Network Parameters） | `0xFF` | 是 | 这是当前源码中 Neighbor 唯一使用非 `0` 的构造点 |
| 通用 Node 同步生成的 Neighbor Config | `0` | `0` | 否 | 业务要求：仅直达，不允许 Relay |
| Space Sync 生成的 Neighbor Config | `0` | `0` | 否 | 业务要求：仅直达，不允许 Relay |
| EFC Sync 生成的 Neighbor Config | `0` | `0` | 否 | 业务要求：仅直达，不允许 Relay |
| SDK `proximityLightingNeighborSet` 默认参数 | `0` | `0` | 否 | 防止未显式传值的调用改变业务语义 |

因此，“EFC Neighbor Config 固定 `0xFF`”需要改写成更精确的验收描述：

> 只把当前明确使用 App Network Parameters Default TTL（现值为 `5`）的 Neighbor Config 构造点改为 `0xFF`；所有当前显式或默认使用 TTL `0` 的 Neighbor Config 继续使用 `0`。

## 3. 源码证据与影响范围

### 3.1 Kinetic Proxy Model Publication

- SDK 文件：`MeshEnOceanProxyServer.swift`
- 方法：`getEnOceanSwitchEnabledMessageHandles(...)`
- 当前行为：构造 `Publish` 时传入 `MeshNetworkManager.instance.networkParameters.defaultTtl`。
- 目标行为：传入固定的设备默认 TTL 哨兵值 `0xFF`。

注意：该方法先根据 `enOceanProxySwitchKeys` 计算发生变化的 Key，只有变化 Key 才生成 Model Publication。已有 Kinetic 配置若 Key 未变化，仅修改构造参数不会触发重新下发。

### 3.2 Battery/AC Power Switch Key Config

- SDK 类型：`BatteryPowerSwitchKeyConfiguration`
- 当前构造默认值：`ttl = 0xFF`。
- App 的 Battery/AC Switch 配置构造没有覆盖该 TTL，因此当前已经符合需求。
- 本次不修改生产逻辑，只增加或保留契约验证。

### 3.3 EFC Scene Publication

- App 文件：`DeviceEmerFireData+Sync.swift`
- 方法：`getPublicationMessageHandles(...)`
- 当前行为：构造 `Publish` 时传入 App Network Parameters Default TTL。
- 目标行为：固定传入 `0xFF`。

注意：`requiresControllerPublicationSync` 和方法内部短路判断目前只比较 Publication Address，不比较 TTL。已有 EFC 的地址正确但 TTL 为 `5` 时，不会仅因 TTL 不符而重新生成任务。

### 3.4 EFC Action Config

- App 常量：`DeviceEmerFireData.emergencyActionTTL = 0xFF`。
- Action Config 新旧值比较和实际下发都显式使用该常量。
- 本次保持不变，并用契约验证防止以后回退到 App Network Parameters Default TTL。

### 3.5 Proximity/EFC Neighbor Config

当前共有四个 App 构造点：

1. `GroupServer.swift`：使用 App Network Parameters Default TTL，当前实际为 `5`；这是唯一需要候选修改为 `0xFF` 的位置。
2. `Node+MessageHandles.swift`：显式 `ttl: 0`，必须保持。
3. `SyncDevicesCellModel.swift`：显式 `ttl: 0`，必须保持。
4. `EmerFireAlarmSyncCellModel.swift`：显式 `ttl: 0`，必须保持。

SDK 枚举 `proximityLightingNeighborSet` 的默认 TTL 也是 `0`，必须保持。

## 4. 推荐开发方案

### 阶段 A：改动边界确认（已完成）

- Neighbor 原来是 `0` 的保持 `0`。
- Neighbor 原来不是 `0` 的改为 `0xFF`。
- 不按设备类型、PID 或固件版本增加额外分支。

### 阶段 B：最小生产代码修改

1. 在 SDK 的 Kinetic Proxy Publication 构造中，将 TTL 来源从 App Network Parameters 改为固定 `0xFF`。
2. 在 App 的 EFC Scene Publication 构造中，将 TTL 来源改为固定 `0xFF`。
3. 仅在 `GroupServer.swift` 的 Neighbor Config 构造中将当前 Default TTL 改为固定 `0xFF`。
4. 不修改 Battery/AC Power Switch Key Config。
5. 不修改 EFC Action Config。
6. 不修改三个显式 `ttl: 0` 的 Neighbor 构造点，也不修改 SDK 的 Neighbor 默认值 `0`。
7. 不接入 Lab TTL，不发送 `ConfigDefaultTtlSet`；设备 Default TTL 由约定的其他工具负责设置。

实现时建议使用语义明确的内部常量表达“使用设备 Default TTL”，避免散落魔法数；但不要为了本需求重构其他 TTL 调用点。

### 阶段 C：后续下发边界（已确认）

- 只实施阶段 B，不实现存量迁移。
- 新增、重新绑定、修改相关配置并确实触发同步后，设备收到 `0xFF`。
- 已经配置为 TTL `5` 且没有再次触发配置的设备，继续保留 `5`。
- 不修改 EFC Publication 同步判断去比较 TTL。
- 不拆分或扩展 Kinetic Key 差异与 Model Publication 差异判定。
- 不为 Neighbor 增加回读、迁移标记或强制重发。
- App 升级后存量设备不会自动统一，这是本次明确接受的范围边界，不作为缺陷。

## 5. 测试与验收方案

### 5.1 静态契约

新增聚焦的 TTL 契约检查，至少保证：

- Kinetic Proxy Publication 固定使用 `0xFF`，不再引用 App Network Parameters Default TTL。
- EFC Scene Publication 固定使用 `0xFF`。
- `GroupServer.swift` 的目标 Neighbor 构造点固定使用 `0xFF`。
- Battery/AC Key Config 默认 TTL 仍为 `0xFF`。
- EFC Action Config 常量及调用仍为 `0xFF`。
- 三个业务要求为 `0` 的 Neighbor 构造点仍显式使用 `0`。
- SDK Neighbor 默认参数仍为 `0`。

### 5.2 SDK 单元测试

- 保留并运行 Battery Power Switch vendor payload 测试，确认 TTL 字节仍为 `0xFF`。
- 为 Neighbor Config 增加 payload 编码用例，分别覆盖 `ttl = 0` 和 `ttl = 0xFF`，确认 App/SDK 编码没有改错字段位置。
- 为 Kinetic Publication 消息生成增加测试或最小可测抽取，确认生成的 Publication TTL 为 `0xFF`。

### 5.3 App 同步逻辑测试

- EFC 新建/重新同步时，Scene Publication 消息 TTL 为 `0xFF`。
- EFC Action Config TTL 仍为 `0xFF`。
- Group Add 目标路径的 Neighbor Config TTL 为 `0xFF`。
- Node Sync、Space Sync、EFC Sync 三条 Neighbor 路径的 TTL 仍为 `0`。
- 验证 App 升级或普通数据加载不会仅因存量 TTL 为 `5` 而创建迁移任务。

### 5.4 构建验证

由于 SDK 与公共 App 代码被多个品牌 target 共用，完成修改后按顺序验证：

- SDK 聚焦单元测试。
- App TTL 契约脚本。
- `git diff --check`。
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target 的真机通用目标构建，关闭签名。

### 5.5 真机/Mesh 验收

分别抓取并核对实际发送 payload：

- Kinetic Proxy Model Publication 的 Publication TTL 字段为 `0xFF`。
- EFC Scene Publication 的 Publication TTL 字段为 `0xFF`。
- Group Add 对应 Neighbor Config 的 TTL 字段为 `0xFF`。
- 三条 TTL 0 业务路径仍发送 `0`，并验证邻近照明不会产生额外 Relay。
- Battery/AC Key Config 和 EFC Action Config 仍发送 `0xFF`。
- 使用其他工具改变设备 Default TTL 后，验证 Kinetic/EFC/Neighbor 的设备发包实际跳数随设备 Default TTL 改变；这一步才证明设备端“使用自身 Default TTL”的闭环成立。

## 6. 验收边界

自动化测试和编译通过只能证明 App/SDK 构造与流程契约正确，不能单独证明：

- 设备 Default TTL 已被其他工具正确修改；
- 实际设备发送消息时确实采用了新的 Default TTL；
- 存量设备已完成迁移；本次明确不提供该能力，也不以此作为验收项。

这些结论必须由实际 payload 和真机 Mesh 跳数/Relay 行为共同验收。

## 7. 已确认的产品范围

App 升级后**不自动迁移**已经写入 TTL `5` 的存量 Kinetic/EFC/Neighbor 配置：

- 只修复以后由新增、重新绑定、编辑或既有业务流程实际触发的配置下发。
- 不新增后台扫描、版本迁移、强制同步或 TTL 差异检测。
- 后续若需要存量迁移，应作为独立需求重新分析和验收。
