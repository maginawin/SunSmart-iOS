# Space Node 容量评审问题修复实施总结

## 1. 修复结果

已按确认的方案 B 完成两条评审问题修复：

1. Restore 不再把同 UUID 历史 Node 的重新 Provisioning 误算为新增 Node。容量策略现在支持每项独立的净新增成本；扫描设备 UUID 已存在于当前 `realNodes` 时成本为 0，否则成本为 1。
2. Professional Candidate 的全选、取消全选和逐项选择计数统一限定到当前 `showDevices`。隐藏分类未提交选择不再消耗当前分类名额；隐藏分类已在途设备仍通过全部 `candidateDevices` 占用全局容量。

## 2. 业务改动

### 容量策略

- `SpaceNodeCapacityPolicy` 新增按每项成本进行稳定筛选的能力。
- 普通 Add 的 `acceptedPrefix` 继续按每项成本 1 工作，既有行为和签名不变。
- 混合 Restore 批次中，新增名额耗尽后仍可接受后续成本为 0 的替换项，接受项保持原相对顺序。

### Restore

- 使用扫描设备 UUID 与当前 `realNodes` UUID 集合判断净新增成本。
- UUID 为空、数据库中存在但当前网络不存在、或 UUID 不一致时，保守按新增 Node 处理。
- 在途计数只额外预留真正净新增的 Restore 项目；同 UUID 替换不重复占用名额。
- 全选、逐项选择、批量提交和 Provisioning 前地址检查复用同一 Restore 批次门禁。
- Site 级 `space == nil` Restore 保持原行为。
- Battery Power Switch Restore 副作用和 Element 地址需求仍只基于最终接受批次。

### Professional Candidate

- Select All 与取消 Select All 只处理当前分类的 `showDevices`。
- 逐项选择只统计当前分类未提交选择。
- 全局 `inFlightNodeCount` 仍统计全部 `candidateDevices`。
- 批量提交仍只提交当前 `showDevices`。

## 3. 测试改动

- 纯 Swift 容量测试新增以下边界：
  - 500 Node 时接受成本为 0 的替换。
  - 499 Node 时同时接受替换和 1 个新增。
  - 新增名额耗尽后跳过超额新增、继续接受后续替换。
  - 在途容量与新增成本共同扣减。
  - 负成本归一化为 0。
- Integration contract 新增以下契约：
  - Restore UUID 成本真值、净新增在途计数和四个入口统一。
  - Professional 当前分类选择域、全局在途域和当前分类提交域。

## 4. 验证结果

### Focused 与回归脚本

以下命令最终均以退出码 0 完成：

- `bash scripts/check_space_node_capacity.sh`
  - `SpaceNodeCapacityPolicyTests passed`
  - `SpaceNodeCapacityIntegrationContractTests passed`
  - `PASS: Space Node capacity policy and target membership.`
- `bash scripts/check_device_restore_efc_support.sh`
  - Restore Candidate 与 EFC Recovery 检查通过。
- `bash scripts/check_efc_controller_flows.sh`
  - EFC Controller 流程契约通过。
- `bash scripts/check_professional_candidate_footer_visibility.sh`
  - Professional Candidate footer 可见性契约通过。
- `git diff --check`
  - 无输出，退出码 0。

### 四品牌 generic iPhoneOS 构建

以下 scheme 均使用 Debug、generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO` 直接执行 `xcodebuild`，并输出 `BUILD SUCCEEDED`：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

构建均解析到本地 NordicSigMeshSDK：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。日志存在 AppIntents metadata 跳过警告，未影响构建结果。

## 5. 改动文件

业务与测试：

- `SunSmart/Main/Device/Model/SpaceNodeCapacityPolicy.swift`
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`
- `Tests/Device/SpaceNodeCapacityPolicyTests.swift`
- `Tests/Device/SpaceNodeCapacityIntegrationContractTests.swift`

文档：

- `docs/260805_1124_space_node_capacity_review_fix_plan.md`
- `docs/260805_1127_space_node_capacity_review_fixes_implementation_plan.md`
- `docs/260805_1153_space_node_capacity_review_fixes_implementation_summary.md`

未修改 NordicSigMeshSDK、本地化、资源、数据库 schema、依赖或 target 配置。未执行 Git commit、push 或 merge。

## 6. 未完成的真实环境验收

静态测试和构建不能证明真实 Mesh Restore 全链路成功，仍需真机验证：

- 500 Node Space 中同 UUID 单个及批量 Restore，最终 Node 数保持 500。
- 499 Node 的替换与真实新增混合批次，超额新增被拒绝而后续替换保留。
- 数据库回退、UUID 为空或不一致时不得加入第 501 个 Node。
- 并行 Restore、失败、取消、重试后的容量状态。
- Professional 四分类跨分类选择、当前分类提交和隐藏分类在途占位。
- 地址申请、Provisioning、数据迁移、Mesh 配置和最终设备控制状态。
