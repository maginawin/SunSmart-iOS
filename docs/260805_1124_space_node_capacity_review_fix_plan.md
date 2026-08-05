# Space Node 容量评审问题修复方案（待确认）

## 1. 结论

两条评审意见均成立，且都来自提交 `d54a4963` 新增的容量限制逻辑：

1. Restore 当前把每个待恢复设备都按新增 Node 计数，未识别同 UUID 历史 Node 的替换语义，满 500 Node 时会在 Provisioning 前把恢复批次裁剪为空。
2. Professional Candidate 的全选和逐项选择使用了全部 `candidateDevices`，而批量提交只使用当前分类的 `showDevices`，导致容量名额、选择状态和实际提交批次不在同一作用域。

推荐采用“方案 B：按净新增成本计算 Restore 容量，并统一 Professional 当前分类选择域”。本轮只形成方案，确认前不修改业务代码。

## 2. 已核实的源码事实

### 2.1 Restore 是替换还是新增，SDK 以 UUID 为准

- `DeviceRestoreViewController.startScan()` 通过 `MeshAPI.startScanRecoverDevices` 获得扫描设备和历史 `Node`，并组合成 `DeviceRestoreData`。
- SDK 的 Restore 扫描优先从当前 `MeshNetworkManager.instance.realNodes` 按 MAC 匹配历史 Node；若当前网络未命中，还会回退到本地数据库加载历史 Node。
- Fast Add 在识别阶段会查询扫描设备 UUID 对应的现有 Node。
- Provisioning 完成后，SDK 使用新 Node 的 UUID 删除同 UUID 旧 Node，再加入新 Node。因此同 UUID Restore 的 Node 总数不增加。
- 数据库回退的历史 Node 不一定仍在当前 `realNodes` 中；扫描 UUID 缺失或与当前 Node 不一致时，也不能按零增长替换处理。

因此 Restore 容量判断不能简单地“全部放行”，也不能把全部 Restore 都按新增 Node 处理。正确真值是：扫描设备 UUID 当前已存在于 `realNodes` 时，本次 Restore 的净新增成本为 0；否则成本为 1。

### 2.2 Restore 当前有四个容量入口

当前 Restore 容量逻辑分布在：

- 全选：`selectAllBtnClick`
- 逐项选择：`tableView(_:didSelectRowAt:)`
- 批量提交：`addSelectedBtnClick` 调用 `nodeCapacityAcceptedRestoreData`
- Provisioning 前最终检查：`checkDeviceAddressesAreSufficient` 再次调用 `nodeCapacityAcceptedRestoreData`

只修复最终批次裁剪仍不完整：满容量时，全选和逐项选择仍会提前阻止用户选中替换设备。因此四个入口必须复用同一 Restore 容量语义，Provisioning 前检查继续作为最终权威边界。

### 2.3 Professional 的选择域与提交域不一致

- 当前 `showDevices` 由 `showDeviceTypes` 过滤，表示当前 Lights、Switches、Sensors 或 Others 分类实际展示的候选设备。
- `addSelectedBtnClick` 只提交 `showDevices` 中已选设备。
- 底部已选数量、全选状态和按钮可用状态也都基于 `showDevices`。
- 但全选的可选集合和逐项选择时的 `selectedNodeCount` 使用全部 `candidateDevices`，包含隐藏分类。
- `inFlightNodeCount` 使用全部 `candidateDevices` 是正确的，因为隐藏分类中已经处于 wait、connecting 或 adding 的设备仍真实占用全局 Space 容量。

因此应只收敛“尚未提交的选择状态”到当前 `showDevices`，不能把全局在途容量也改成当前分类。

## 3. 方案比较

### 方案 A：最小修改，整批扣减替换数量

做法：Restore 批次进入现有 `acceptedPrefix` 前，从现有 Node 数中减去本批次同 UUID 历史 Node 数；Professional 将两处 `candidateDevices` 改为 `showDevices`。

优点：改动最少。

缺点：Restore 混合批次不精确。例如真正新增项排在前面、替换项排在后面时，整批预先扣减后面的替换数量可能错误放行前面的新增项；如果坚持前缀裁剪，又可能继续误拒后面的零增长替换项。多个入口也容易再次产生不同口径。

结论：不推荐。

### 方案 B：按每项净新增成本裁剪，并统一选择域（推荐）

做法：扩展纯 Swift 容量策略，使其支持每个请求项的 Node 成本。普通 Add 的每项成本仍为 1；Restore 根据扫描 UUID 是否已存在于当前 `realNodes` 返回 0 或 1。Restore 四个入口复用同一分类和裁剪结果。Professional 的全选、取消全选和逐项已选数量限定到当前 `showDevices`，全局 `inFlightNodeCount` 保持不变。

优点：直接表达真实容量变化；可覆盖满容量替换、数据库回退、UUID 异常和混合批次；核心算法可由纯 Swift focused tests 验证；普通 Add 行为不变。

缺点：需要扩展公共策略并补充 Restore/Professional 契约测试，改动比方案 A 略多。

结论：推荐。

### 方案 C：Restore 全部绕过 Node 上限

做法：具有 Space 上下文的 Restore 也不执行 500 Node 限制。

优点：同 UUID 恢复不会被阻止。

缺点：数据库回退、UUID 缺失或不一致时可能真实新增第 501 个 Node，破坏容量契约。

结论：不采用。

## 4. 推荐设计

### 4.1 Restore 容量真值

对每个 `DeviceRestoreData` 在容量判断时读取当前 `realNodes` UUID 集合：

- 扫描设备 UUID 非空且已存在：视为替换，净新增成本为 0。
- 扫描设备 UUID 为空：保守视为新增，成本为 1。
- 扫描设备 UUID 不在当前 `realNodes`：视为新增，成本为 1，即使存在数据库历史 Node 也不提前假定 SDK 会替换当前 Node。

Restore 在途数量也使用相同真值：只有尚未体现在当前 `realNodes` 中且确实会净新增的在途项才额外预留容量；同 UUID 替换项不重复占用名额。每次选择和最终提交均重新读取当前网络状态，Provisioning 前结果为最终权威。

当混合批次的新增名额耗尽时：

- 后续成本为 1 的项目取消选择并提示容量上限。
- 后续成本为 0 的替换项目仍保留，避免新增项阻塞合法恢复。
- 所有被接受项目保持原相对顺序。

Site 级 `space == nil` Restore 继续绕过 Space Node 上限，不改变现有 Gateway Restore 边界。

### 4.2 Restore 四个入口统一

- 全选先从当前可见 Restore 数据中得到可选项，再调用 Restore 专用容量裁剪。
- 逐项选中时，以当前已选 Restore 数据、全局在途净新增成本和本次项目成本共同判断；成本为 0 的替换项在 500 Node 时仍可选。
- 批量提交只记录被接受项目的 Battery Power Switch 等后续副作用。
- `checkDeviceAddressesAreSufficient` 在申请 Unicast Address 前再次执行同一最终裁剪，防止 UI 状态变化或调用绕过。
- Unicast Address/Element 数量检查保持独立；替换不增加 Node 数，不代表不需要重新分配足够的 Element 地址。

### 4.3 Professional 当前分类选择域

- 全选与取消全选只处理当前 `showDevices` 中未禁用、未在途的设备。
- 逐项选中时，`selectedNodeCount` 只统计当前 `showDevices` 中已选且尚未在途的设备。
- `addSelectedBtnClick` 继续只提交当前 `showDevices`，与选择口径一致。
- 切换分类时保留其他分类已有的选择状态，但这些隐藏选择不占当前分类的“待提交选择”名额，也不会随当前分类提交。
- `inFlightNodeCount` 继续统计全部 `candidateDevices`，确保其他分类中已经开始添加的设备仍扣减 Space 全局剩余容量。
- Professional Controller 的 Provisioning 前最终批次门禁继续保留，防止 View 层被绕过。

## 5. 拟修改范围

### 业务源码

- `SunSmart/Main/Device/Model/SpaceNodeCapacityPolicy.swift`
  - 增加支持每项净新增成本的稳定裁剪能力；保留现有普通 Add 接口和行为。
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
  - 建立 Restore 项目成本判断、在途净新增计数和统一裁剪入口；接入全选、逐项选择、批量提交及 Provisioning 前检查。
- `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`
  - 将全选、取消全选和逐项选择计数限定到当前 `showDevices`；保留全局在途计数。

### 测试

- `Tests/Device/SpaceNodeCapacityPolicyTests.swift`
  - 增加零成本替换、普通新增、混合成本和顺序稳定性测试。
- `Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`
  - 锁定 Restore 使用 UUID/当前真实 Node 判断成本且四个入口复用统一逻辑。
  - 锁定 Professional 全选和逐项选择使用 `showDevices`，同时 `inFlightNodeCount` 仍使用 `candidateDevices`。
- `scripts/check_space_node_capacity.sh`
  - 预计无需修改；继续运行扩充后的 focused tests 与 integration contract。

### 明确不修改

- NordicSigMeshSDK 源码。
- 500 Node 上限值和普通 Classic/Professional Controller 的最终门禁。
- Switch 合计 16 个限制。
- 本地化文案、图片资源、数据库 schema、依赖和 target 配置。

## 6. 实施顺序

1. 先为纯容量策略补充失败测试，覆盖成本 0/1 与混合批次。
2. 扩展 `SpaceNodeCapacityPolicy` 的每项成本裁剪能力，使 focused tests 通过。
3. 为 Restore 与 Professional 补充 source contract 失败断言。
4. 修改 Restore 四个入口，统一使用 UUID 驱动的净新增成本。
5. 修改 Professional Candidate 当前分类选择域，保留全局在途计数。
6. 运行 focused capacity 脚本和相关 Device Restore/Add 契约检查。
7. 执行 `git diff --check`。
8. 使用 generic iPhoneOS、关闭签名，构建 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个共享代码 target；不使用 Simulator，不用 shell 包装或重定向日志。
9. 输出实施总结，明确静态/构建验证与真机 Mesh 验收的边界；未经明确授权不 commit、push 或 merge。

## 7. 自动化验收矩阵

### Restore

1. 已有 500 Node，同 UUID Restore 1 个：允许，批次不被裁空。
2. 已有 500 Node，同 UUID Restore 多个：全部允许，最终 Node 总数仍为 500。
3. 已有 499 Node，1 个替换 + 1 个真实新增：两者允许，最终最多 500。
4. 已有 500 Node，数据库历史 Node 但扫描 UUID 当前不存在：拒绝真实新增项。
5. 扫描 UUID 为空或与当前历史 Node 不一致：按新增处理，不得突破 500。
6. 混合顺序为“新增、超额新增、替换”：拒绝超额新增，但仍接受后续替换。
7. 替换设备已经在 wait/connecting/adding：不重复预留 Node 容量。
8. Site 级 `space == nil` Restore：保持原行为。
9. 容量裁剪后，仅对接受项计算 Element 地址和记录 Restore 副作用。

### Professional Candidate

1. 剩余 1 个名额，隐藏分类在当前分类之前有候选：当前分类全选仍选择当前可见的第 1 个设备。
2. 隐藏分类已有未提交选择：不阻止当前分类逐项选择，也不计入当前 footer 数量。
3. 当前分类全选/取消全选：不改变隐藏分类选择状态。
4. 提交当前分类：只提交当前 `showDevices` 的已选项。
5. 隐藏分类已有 wait/connecting/adding：仍占用全局容量并限制当前分类。
6. 切换分类后，各分类 footer 的已选数、总数和 Select All 状态与当前可见列表一致。

## 8. 真机验收边界

构建成功不能证明 SDK 在真实 Mesh 中完成了旧 Node 替换。至少需要真机验证：

- 500 Node Space 中对 OTA 后重置设备执行 Restore，确认 Provisioning 启动、旧 UUID Node 被替换、最终真实 Node 数保持 500。
- 接近上限时并行恢复多个设备，确认不会误裁剪，且失败/取消/重试后容量状态正确。
- Professional 四个分类之间切换、跨分类保留选择、当前分类提交和隐藏分类在途占位均符合设计。
- 检查地址申请、Provisioning、数据迁移、后续 Mesh 配置与最终业务可控状态；不能只以 Provisioning callback 或 build 成功作为整链路成功。

## 9. 待确认项

请确认以下契约后再进入正式实施计划与代码修改：

1. 采用方案 B，以扫描 UUID 是否已存在于当前 `realNodes` 作为 Restore 净新增成本真值。
2. 混合 Restore 批次中，即使新增名额已满，后续同 UUID 替换项仍保留，不强制整批前缀裁剪。
3. Professional 隐藏分类的未提交选择状态继续保留，但不占当前分类选择名额；隐藏分类的在途设备仍占全局容量。
4. 按上述三个业务文件、两个测试文件的聚焦范围实施，不修改 SDK、本地化、资源、依赖或 target 配置。
