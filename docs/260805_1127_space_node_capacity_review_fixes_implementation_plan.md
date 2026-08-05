# Space Node 容量评审问题修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session. Steps use checkbox (`- [ ]`) syntax for tracking. Do not use subagents unless the user explicitly requests them.

**Goal:** 修复 Restore 同 UUID 替换被误算为新增 Node，以及 Professional Candidate 隐藏分类选择错误占用当前分类名额的问题，同时保持 500 Node 最终门禁和全局在途容量约束。

**Architecture:** 扩展现有纯 Swift `SpaceNodeCapacityPolicy`，让容量裁剪支持每个请求项独立提供净新增成本；普通 Add 继续使用每项成本 1 的稳定前缀，Restore 使用当前 `realNodes` UUID 判断成本 0 或 1。Restore 的全选、逐项选择、批量提交和 Provisioning 前检查复用同一成本语义；Professional 只把未提交选择限定到当前 `showDevices`，全局在途计数仍基于全部 `candidateDevices`。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、本地 Swift Package、独立 `swiftc` focused tests、Swift source contract tests、Xcode generic iPhoneOS builds。

## Global Constraints

- 单个 Space 最多 500 个真实 Mesh Node；本次不得修改上限值。
- Restore 扫描设备 UUID 已存在于当前 `realNodes` 时，本次请求净新增成本为 0；UUID 为空或当前不存在时成本为 1。
- 混合 Restore 批次中，新增名额耗尽后仍接受后续成本为 0 的替换项；所有接受项保持原相对顺序。
- Site 级 `space == nil` Restore 继续绕过 Space Node 上限。
- Restore 四个入口必须使用同一容量真值；Provisioning 前检查是最终权威边界，并先于 Unicast Address 申请。
- Professional 未提交选择只统计当前 `showDevices`；隐藏分类已在途设备仍通过全部 `candidateDevices` 占用 Space 容量。
- 普通 Classic/Professional Add 的每项成本继续为 1，现有 `acceptedPrefix` 行为不得改变。
- 不修改 NordicSigMeshSDK、本地化、图片资源、数据库 schema、依赖、target 配置、Switch 合计 16 个限制或其他业务模块。
- 不新增 Auth 信息，不重构或格式化无关代码。
- 所有构建使用 generic iPhoneOS，不使用 Simulator，不通过 shell 包装或重定向日志。
- 未经用户明确授权，不执行 Git commit、push、merge；各 Task 以 diff 和测试检查点代替 commit。
- 根据项目规则，计划不嵌入业务源码实现片段；接口、行为、断言和命令必须完整明确。

---

## 文件结构与职责

### 修改文件

- `SunSmart/Main/Device/Model/SpaceNodeCapacityPolicy.swift`
  - 新增按每项净新增成本进行稳定筛选的纯 Swift 能力。
  - 保留 `remainingNodeCount`、`acceptedNodeCount` 和 `acceptedPrefix` 的现有外部行为。
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
  - 定义 Restore 项目成本、净新增在途数量和统一批次裁剪。
  - 将全选、逐项选择、批量提交及 Provisioning 前检查接到同一规则。
- `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`
  - 将 Professional 全选、取消全选和逐项选择计数限定到当前 `showDevices`。
  - 保持全局 `inFlightNodeCount` 基于全部 `candidateDevices`。
- `Tests/Device/SpaceNodeCapacityPolicyTests.swift`
  - 增加每项成本 0/1、混合批次和顺序稳定性的纯 Swift 测试。
- `Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`
  - 锁定 Restore UUID 成本真值、四入口接入和 Professional 当前分类选择域。

### 检查但不修改

- `scripts/check_space_node_capacity.sh`
  - 已能编译运行上述两个测试文件，并检查公共策略属于四个 App target。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Provisioning/ProvisioningManager.swift`
  - 仅作为 SDK 按 UUID 替换旧 Node 的事实依据。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshAddDeviceManager.swift`
  - 仅作为 Restore 扫描优先查当前 `realNodes`、再回退数据库的事实依据。

---

### Task 1: 扩展纯 Swift 每项成本容量策略

**Files:**

- Modify: `Tests/Device/SpaceNodeCapacityPolicyTests.swift`
- Modify: `SunSmart/Main/Device/Model/SpaceNodeCapacityPolicy.swift`
- Verify: `scripts/check_space_node_capacity.sh`

**Interfaces:**

- Produces: `SpaceNodeCapacityPolicy.acceptedElements(_:existingNodeCount:inFlightNodeCount:nodeCost:) -> [Element]`
- `nodeCost` 类型：`(Element) -> Int`
- `nodeCost <= 0`：按 0 个新增 Node 处理。
- `nodeCost > 0`：只有剩余容量足够支付完整成本时才接受并扣减。
- 保持：`acceptedPrefix(_:existingNodeCount:inFlightNodeCount:) -> [Element]`，内部以每项成本 1 复用新能力，输出必须与当前实现一致。

- [ ] **Step 1: 为每项成本能力增加失败测试**

  在 `SpaceNodeCapacityPolicyTests.main()` 增加以下精确断言：

  - 现有 500、在途 0、请求 `[replacement: 0]`，接受 replacement。
  - 现有 499、在途 0、请求 `[replacement: 0, new: 1]`，两项都接受。
  - 现有 499、在途 0、请求 `[newA: 1, newB: 1, replacement: 0]`，接受 `newA` 和 `replacement`，拒绝 `newB`，并保持接受项相对顺序。
  - 现有 498、在途 1、请求 `[newA: 1, newB: 1]`，只接受 `newA`。
  - 负成本按 0 处理，不增加剩余容量，也不拒绝该项目。
  - 现有 `acceptedPrefix` 的全部断言保留，证明普通 Add 行为未变化。

- [ ] **Step 2: 运行 focused check 并确认 RED**

  Run: `bash scripts/check_space_node_capacity.sh`

  Expected: 编译在 `SpaceNodeCapacityPolicyTests.swift` 失败，错误明确指向 `acceptedElements` 尚未定义；原有测试在新增断言前基线已通过。

- [ ] **Step 3: 实现最小每项成本筛选**

  在 `SpaceNodeCapacityPolicy` 增加 `acceptedElements`，严格遵守以下行为：

  - 初始剩余容量只调用现有 `remainingNodeCount` 计算一次。
  - 按输入顺序遍历所有项目，不预先扣减后续项目成本。
  - 每项成本先归一化到不小于 0。
  - 成本不大于剩余容量时接受并扣减；否则跳过该项并继续检查后续项。
  - 返回所有接受项，保持输入中的相对顺序。
  - `acceptedPrefix` 改为使用 `acceptedElements` 且固定每项成本 1，不改变签名和调用方。

- [ ] **Step 4: 运行 focused check 并确认 GREEN**

  Run: `bash scripts/check_space_node_capacity.sh`

  Expected:

  - `SpaceNodeCapacityPolicyTests passed`
  - `SpaceNodeCapacityIntegrationContractTests passed`
  - `PASS: Space Node capacity policy and target membership.`

- [ ] **Step 5: 检查 Task 1 聚焦 diff**

  Run: `git diff -- SunSmart/Main/Device/Model/SpaceNodeCapacityPolicy.swift Tests/Device/SpaceNodeCapacityPolicyTests.swift`

  Expected: 只包含新接口、现有 `acceptedPrefix` 的委托实现和新增断言；不改变 500 上限、现有参数签名或其他文件。

---

### Task 2: 修复 Restore 替换容量语义并统一四个入口

**Files:**

- Modify: `Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- Consume: `SpaceNodeCapacityPolicy.acceptedElements(_:existingNodeCount:inFlightNodeCount:nodeCost:)`

**Interfaces:**

- Produces: Restore 项目是否额外占用 Node 容量的私有判断，输入为 `DeviceRestoreData` 和当前真实 Node UUID 集合，输出为 0 或 1。
- Produces: Restore 净新增在途数量；只统计 `addState.reservesNodeCapacity == true` 且扫描 UUID 尚未出现在当前 `realNodes` 的项目。
- Reuses: `nodeCapacityAcceptedRestoreData(from:) -> [DeviceRestoreData]` 作为唯一批次裁剪入口。
- Preserves: `space == nil` 时原样返回输入批次。

- [ ] **Step 1: 增加 Restore source contract 失败断言**

  在 `SpaceNodeCapacityIntegrationContractTests` 对 `DeviceRestoreViewController.swift` 增加以下契约：

  - Restore 容量判断读取扫描设备 `unprovisionedDevice?.uuid` 和当前 `realNodes` UUID 集合。
  - UUID 当前存在时项目成本为 0；UUID 为空或不存在时项目成本为 1。
  - `inFlightNodeCount` 不再简单统计全部 `allDevices.filter`，而是使用相同 UUID 成本真值统计净新增在途项。
  - `nodeCapacityAcceptedRestoreData` 使用 `acceptedElements`，不得继续对 Restore 批次直接使用 `acceptedPrefix`。
  - `selectAllBtnClick` 从当前可见 `showRestoreData` 形成 Restore 数据批次，并调用统一裁剪入口。
  - `tableView(_:didSelectRowAt:)` 使用当前 Restore 数据和统一批次裁剪判断，不再直接调用仅接受数量的普通 Add 逻辑。
  - `addSelectedBtnClick` 与 `checkDeviceAddressesAreSufficient` 均继续调用统一裁剪入口。
  - Address 估算和 Battery Power Switch Restore 副作用仍只使用接受批次。

- [ ] **Step 2: 运行 focused check 并确认 Restore RED**

  Run: `bash scripts/check_space_node_capacity.sh`

  Expected: `SpaceNodeCapacityIntegrationContractTests` 失败，至少指出 Restore 尚未使用 UUID 成本判断、仍直接使用 `acceptedPrefix`，以及选择入口未统一。

- [ ] **Step 3: 建立 Restore UUID 成本真值**

  在 `DeviceRestoreViewController` 中实现私有辅助逻辑：

  - 每次容量判断从 `MeshNetworkManager.instance.realNodes` 建立 UUID 集合，不缓存跨回调状态。
  - `DeviceRestoreData.unprovisionedDevice?.uuid` 存在于集合时返回成本 0；其他情况返回成本 1。
  - 将 `inFlightNodeCount` 改为遍历 `sections` 中全部 Restore 数据，只统计在途且当前成本为 1 的项目。
  - 不以 MAC、历史 Node 对象身份或数据库存在性替代 UUID 判断，因为 SDK Provisioning 完成时按新 Node UUID 执行替换。

- [ ] **Step 4: 改造统一 Restore 批次裁剪**

  调整 `nodeCapacityAcceptedRestoreData(from:)`：

  - `space == nil` 直接返回输入。
  - 使用 Task 1 的 `acceptedElements`，现有 Node 数取当前 `realNodes.count`，在途数取净新增在途数量，每项成本取 Restore UUID 成本。
  - 未接受项目取消选择并只在确有裁剪时显示一次容量提示。
  - 保留 footer 刷新和 table reload 行为。
  - 允许在新增名额耗尽后继续接受后续成本为 0 的替换项。

- [ ] **Step 5: 接入 Restore 全选和逐项选择**

  全选必须：

  - 只处理当前 `showRestoreData` 中具有扫描设备、未禁用且未在途的项目。
  - 先得到统一裁剪结果，再将当前可选范围统一取消选择并只选中接受项。
  - `space == nil` 继续全选全部当前可选项目。

  逐项选择必须：

  - 使用当前可见 Restore 数据中已选项目加本次目标项目形成请求批次。
  - 目标项目出现在接受结果中才允许选中；否则显示现有容量提示并保持未选中。
  - 取消选择、失败重试状态恢复和现有 cell/footer 刷新逻辑保持不变。

- [ ] **Step 6: 保留最终门禁和副作用顺序**

  检查并保持：

  - `addSelectedBtnClick` 先裁剪，再对接受项记录 Battery Power Switch Restore link group。
  - `checkDeviceAddressesAreSufficient` 在设置 wait/connecting 状态及计算 Element 地址前再次裁剪。
  - 第二次裁剪在网络状态未变化时不得重复提示；网络状态变化导致真实裁剪时必须阻止超额 Provisioning。
  - 所有 Address 申请、`addDevice` 调度和 Restore 后续数据迁移只接收最终接受批次。

- [ ] **Step 7: 运行 focused check 并确认 Restore GREEN**

  Run: `bash scripts/check_space_node_capacity.sh`

  Expected: policy tests、integration contract 和四 target membership 检查全部通过。

- [ ] **Step 8: 运行 Restore 相关回归检查**

  Run: `bash scripts/check_device_restore_efc_support.sh`

  Expected: Restore Candidate、EFC icon、EFC recovery 等现有检查全部通过；不因容量辅助逻辑改变 EFC 身份或数据迁移行为。

  Run: `bash scripts/check_efc_controller_flows.sh`

  Expected: EFC Controller 相关流程契约全部通过。

- [ ] **Step 9: 检查 Task 2 聚焦 diff**

  Run: `git diff -- SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`

  Expected: 只包含 Restore 容量成本、四入口接入和对应契约；不修改 Restore 身份过滤、Provisioning callback、配置消息、文案或 SDK。

---

### Task 3: 修复 Professional 当前分类选择域

**Files:**

- Modify: `Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`
- Modify: `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`

**Interfaces:**

- Current selection scope: `showDevices`
- Global capacity reservation scope: `candidateDevices.filter { $0.addState.reservesNodeCapacity }`
- Submission scope: `showDevices.filter { $0.selectedState == .selected }`

- [ ] **Step 1: 增加 Professional source contract 失败断言**

  在 integration contract 分别提取 `selectAllBtnClick`、`tableView(_:didSelectRowAt:)`、`inFlightNodeCount` 和 `addSelectedBtnClick` 源码区段，并锁定：

  - 全选的 `canAddDevices` 来自 `showDevices`，该区段不得使用全部 `candidateDevices` 形成未提交选择集合。
  - 逐项选择的 `selectedNodeCount` 来自 `showDevices`，不得统计隐藏分类的 selected 项。
  - `inFlightNodeCount` 仍来自全部 `candidateDevices`，不得缩小到 `showDevices`。
  - 批量提交仍来自 `showDevices`。

- [ ] **Step 2: 运行 focused check 并确认 Professional RED**

  Run: `bash scripts/check_space_node_capacity.sh`

  Expected: integration contract 失败，明确指出全选或逐项选择仍使用 `candidateDevices`。

- [ ] **Step 3: 将全选和取消全选限定到当前分类**

  修改 `selectAllBtnClick`：

  - `canAddDevices` 从当前 `showDevices` 过滤未禁用且未在途项目。
  - 选中时仅在当前范围执行容量裁剪、取消选择和重新选中。
  - 取消全选时只取消当前范围，不改变隐藏分类的 selected 状态。
  - 容量不足提示、footer 刷新和 table reload 保持现有行为。

- [ ] **Step 4: 将逐项已选数量限定到当前分类**

  修改 `tableView(_:didSelectRowAt:)` 中 `selectedNodeCount`：

  - 只统计当前 `showDevices` 中已选且不是本次目标的项目。
  - 继续将全局 `inFlightNodeCount` 加入容量占用，确保隐藏分类已在途设备仍扣减名额。
  - 不修改失败重试、cell 图标和 footer 更新行为。

- [ ] **Step 5: 运行 focused check 并确认 Professional GREEN**

  Run: `bash scripts/check_space_node_capacity.sh`

  Expected: policy tests、Restore/Professional integration contract 和 target membership 全部通过。

- [ ] **Step 6: 运行 Professional footer 回归检查**

  Run: `bash scripts/check_professional_candidate_footer_visibility.sh`

  Expected: Candidate footer 的搜索、批量选择控件和按钮可见性契约全部通过。

- [ ] **Step 7: 检查 Task 3 聚焦 diff**

  Run: `git diff -- SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`

  Expected: Candidate View 业务改动仅有两处选择域收敛；`inFlightNodeCount` 和 `addSelectedBtnClick` 仍保持全局在途/当前提交的既定分工。

---

### Task 4: 综合静态检查与四品牌构建

**Files:**

- Verify: all modified files
- Verify: `SunSmart.xcworkspace`

**Interfaces:**

- Consumes: Tasks 1–3 的全部实现和测试。
- Produces: 可交付的静态测试、格式检查和四品牌 generic iPhoneOS 构建证据。

- [ ] **Step 1: 运行最终 focused checks**

  Run: `bash scripts/check_space_node_capacity.sh`

  Run: `bash scripts/check_device_restore_efc_support.sh`

  Run: `bash scripts/check_efc_controller_flows.sh`

  Run: `bash scripts/check_professional_candidate_footer_visibility.sh`

  Expected: 所有脚本退出码为 0，无失败断言。

- [ ] **Step 2: 检查格式和变更范围**

  Run: `git diff --check`

  Expected: 无输出，退出码为 0。

  Run: `git status --short`

  Expected: 仅显示本计划列出的 5 个实现/测试文件，以及本次分析和实施计划文档；不得出现 SDK、本地化、资源、依赖或工程 target 变更。

- [ ] **Step 3: 构建 SunSmart**

  Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

  Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: 构建 Archipelago**

  Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

  Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: 构建 SLG Sync Plus**

  Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

  Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: 构建 SylSmart**

  Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

  Expected: `BUILD SUCCEEDED`。

- [ ] **Step 7: 输出最终实施总结**

  总结必须列明：

  - 两条评审意见分别修改了哪些入口和容量真值。
  - focused tests、回归脚本、`git diff --check` 和四品牌构建的实际结果。
  - 工作树中所有改动文件，不掩盖既有或新建文档。
  - 未执行 commit、push、merge。
  - 真机 Mesh 验收仍开放，不能把静态测试或 `BUILD SUCCEEDED` 表述为 Restore 全链路成功。

---

## 真机验收清单（实施完成后由真实环境执行）

### Restore

- 500 Node Space，同 UUID Restore 1 个和多个设备均可进入 Provisioning，最终真实 Node 数保持 500。
- 499 Node Space，替换与真实新增混合批次最多到 500；超额新增被拒绝，后续替换仍保留。
- 数据库回退历史 Node、UUID 为空和 UUID 不一致按新增处理，不得加入第 501 个 Node。
- 并行 Restore、失败、取消和重试后容量状态正确，不重复预留替换设备。
- 容量通过后继续验证地址申请、Provisioning、数据迁移、Mesh 配置和最终控制状态。

### Professional Candidate

- 剩余 1 个名额且隐藏分类有更早候选时，当前分类 Select All 选中当前可见第 1 个项目。
- 隐藏分类未提交选择不阻止当前分类逐项选择，也不出现在当前 footer 计数或提交批次中。
- 当前分类取消全选不清除隐藏分类选择；切换回来时选择状态仍在。
- 隐藏分类 wait/connecting/adding 仍扣减 Space 全局容量并正确阻止超额添加。
- Lights、Switches、Sensors、Others 四类切换后的 Select All、已选数量、提交批次和容量提示一致。
