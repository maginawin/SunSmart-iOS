# EFC 默认名称统一规则设计

## 背景

添加 Emergency Fire Controller 时，当前真实设备和虚拟设备的默认名称来源不一致：

- 真实 EFC 节点通过 `MeshNetworkManager.getNextNodeName(node.defaultNameCategory)` 生成，`defaultNameCategory` 为 `EFC`，占用集合只来自当前真实节点名称。
- 虚拟 EFC / 本地 EFC 配置通过 `DeviceEmerFireStore.nextDefaultName(space:)` 生成，当前 base 是 `EFC `，占用集合来自当前 Space 内的 EFC 本地配置。
- 真实 EFC 被手动重置后，旧 EFC 本地记录仍保留并变成未绑定虚拟设备；再次添加真实设备时，真实节点命名不会把这个未绑定记录算作占用，容易再次生成 `EFC1`。

用户期望虚拟或真实 EFC 一起计算默认名称，格式统一为无空格 `EFCn`，并在同一个 Space 内从小到大选择未占用序号。

## 目标规则

1. 默认名称格式固定为 `EFCn`，例如 `EFC1`、`EFC2`。
2. 序号占用集合以当前 Space 内的 `DeviceEmerFireData.name` 为准。
3. 虚拟 EFC 创建、真实 EFC 添加、restore 兜底创建都使用同一套 `DeviceEmerFireStore` 默认名生成逻辑。
4. 新建真实 EFC 本地记录时，将真实 `node.name` 同步为同一个 `EFCn`。
5. LINK 到已有虚拟 EFC 时，保留该虚拟 EFC 的名称，并把新绑定的 `node.name` 同步为该名称。
6. 不迁移历史名称，不兼容 `EFC 1`、`FEC 1` 等非目标格式。

## 推荐方案

将 EFC 默认名称生成收敛到 `DeviceEmerFireStore`，不要把 EFC 业务规则放进通用 `MeshNetworkManager.getNextNodeName`。

### DeviceEmerFireStore

- 将 `nextDefaultName(space:)` 和内部 `nextDefaultName(in:)` 的 base 改为 `EFC`。
- 计算时只检查当前 Space 内 EFC 本地记录名称。
- 从 1 开始递增，返回第一个未占用的 `EFCn`。

### 真实设备添加

Classic 和 Professional 添加入口已经在 EFC 成功入网后调用共享的 `DeviceEmerFireStore.ensureDevice(for:in:)` 或 `bind(_:to:in:)`。

- `ensureDevice(for:in:)` 找到已绑定记录时直接返回。
- `ensureDevice(for:in:)` 创建新记录时使用 `DeviceEmerFireData.default(space:)`，并把 `node.name` 同步为该记录名称后保存节点。
- `bind(_:to:in:)` 绑定已有虚拟 EFC 时，同步 `node.name = device.name` 并保存节点。

这样不需要分别在 Classic / Professional 两套控制器里补命名规则。

### 真实节点自动合并

`mergeRealEmergencyControllers(...)` 用于处理 Mesh 网络里已有真实 EFC、但本地还没有 EFC 配置的情况。

- 新建本地记录时使用统一的 `EFCn`。
- 同步真实 `node.name` 为该本地记录名称。
- 不再优先使用 `node.name` 作为业务记录名称，避免真实节点名绕过 Space 内 EFC 占用集合。

### Restore

`restoreDevice(replacing:with:in:)` 需要保持恢复语义：

- 如果能找到旧 EFC 记录，沿用旧记录名称，并同步到新 `node.name`。
- 如果找不到旧记录，创建新 EFC 记录时走统一 `EFCn` 规则，并同步到 `node.name`。
- 继续保持 `isSynced = false`，不改变后续同步任务语义。

## 示例

已有状态：

- 本地 EFC 记录：`EFC1`，`bindNodeAddress == nil`
- 当前真实节点列表里没有 `EFC1`

再次添加真实 EFC：

1. Mesh 节点完成入网。
2. `ensureDevice(for:in:)` 未找到已绑定记录。
3. `DeviceEmerFireData.default(space:)` 看到当前 Space 已占用 `EFC1`。
4. 新记录命名为 `EFC2`。
5. 新真实节点 `node.name` 同步为 `EFC2`。

结果：虚拟旧设备为 `EFC1`，新真实设备为 `EFC2`，不会重复。

## 影响范围

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift`
- Classic Add Device 和 Professional Add Device 通过共享 store 间接受影响。
- Device Restore 通过 `DeviceEmerFireStore.restoreDevice` 间接受影响。

不改动：

- 通用节点命名 `MeshNetworkManager.getNextNodeName`。
- 非 EFC 设备命名规则。
- 历史 EFC 名称迁移。
- 本地化、资源、target 配置和依赖。

## 验证计划

1. 静态检查 EFC 命名链路：
   - 虚拟 EFC 创建。
   - 真实 EFC 添加到 Space。
   - LINK 到已有虚拟 EFC。
   - restore 替换 EFC。
2. 运行 `git diff --check`。
3. 运行 iPhoneOS 构建：

   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 自检

- 无待定项。
- 规则明确为 `EFCn`，不兼容历史带空格或拼写不同名称。
- 真实与虚拟默认名统一由 `DeviceEmerFireStore` 计算。
- 方案不引入无关重构，不影响非 EFC 设备命名。
