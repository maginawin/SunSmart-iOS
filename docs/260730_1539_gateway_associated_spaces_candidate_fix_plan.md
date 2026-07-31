# Gateway Associated Spaces Candidate Fix Implementation Plan

> **执行方式：** REQUIRED SUB-SKILL: 使用 `superpowers:executing-plans` 在当前会话 Inline Execution；每项按 RED→GREEN 执行，不使用 subagents。

**Goal:** 让 4G/WiFi Gateway 的 Associated Spaces 使用显式、最新的 Site Primary MeshNetwork 生成候选，并区分真实空列表与 AppKey 数据不可用。

**Architecture:** 新增一个不依赖 UIKit 和 Mesh SDK 的候选策略，输入 Space 编辑/绑定状态与显式 AppKey 映射，输出候选或数据不可用。`GatewayViewController` 从本地 Mesh 数据库重新加载 Site 主网快照并调用该策略；`GatewayAssociatedSpacesController` 通过 provider 在首次进入和 Retry 时重新计算候选。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Foundation-only standalone tests、shell contract runner、Xcode generic iPhoneOS builds。

## Global Constraints

- 只修改 Gateway Associated Spaces 候选链路，不改变云端 bind/unbind API、Gateway `SAVE` 边界或设备侧同步顺序。
- 4G 与 WiFi Gateway 共用修复，不复制子类逻辑。
- 不新增用户可见文案，复用 `failed_to_retrieve_data`、`network_problem_note`、`RETRY` 和 `no_data`。
- 新生产文件加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。
- 不修改 NordicSigMeshSDK，除非 RED/GREEN 证据证明 AppKey 加载问题位于 SDK。
- 不提交或推送 Git。

---

### Task 1: 建立候选策略 RED 测试

**Files:**

- Create: `Tests/Device/GatewayAssociatedSpaceCandidatePolicyTests.swift`
- Create: `scripts/check_gateway_associated_space_candidates.sh`
- Create after RED: `SunSmart/Main/Device/Gateway/Model/GatewayAssociatedSpaceCandidatePolicy.swift`

**Interfaces:**

- Produces: `GatewayAssociatedSpaceCandidatePolicy.resolve(spaces:currentGatewayId:appKeyIndicesByNetworkId:)`
- Produces: `GatewayAssociatedSpaceCandidateResolution.available([GatewayAssociatedSpaceCandidate])`
- Produces: `GatewayAssociatedSpaceCandidateResolution.unavailable(missingAppKeySpaceIds:)`

- [ ] **Step 1: 写入失败测试**

测试输入使用独立字面值，覆盖：

1. 两个可编辑、未绑定 Space 在显式 AppKey 映射中均命中，必须返回两个候选。
2. 业务上合格的 Space 缺 AppKey，必须返回 `unavailable`，不能返回空候选。
3. 无编辑能力的 Space 被排除，但不构成 AppKey 数据错误。
4. 已绑定其他 Gateway 的 Space 被排除。
5. 已绑定当前 Gateway 的 Space 可进入候选，gatewayId 比较忽略大小写。

期望接口：

```swift
let result = GatewayAssociatedSpaceCandidatePolicy.resolve(
    spaces: [
        .init(
            spaceId: "space-1",
            canEdit: true,
            associatedGatewayId: nil,
            meshNetworkId: "network-1"
        )
    ],
    currentGatewayId: "gateway-a",
    appKeyIndicesByNetworkId: ["network-1": 7]
)

precondition(
    result == .available([
        .init(spaceId: "space-1", appKeyIndex: 7)
    ])
)
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
bash scripts/check_gateway_associated_space_candidates.sh
```

Expected: `swiftc` 因 `GatewayAssociatedSpaceCandidatePolicy` 尚不存在而失败。

- [ ] **Step 3: 写入最小候选策略**

策略只做三件事：

1. 排除 `canEdit == false`。
2. 排除非空且不属于当前 Gateway 的 `associatedGatewayId`。
3. 对业务合格 Space 查找 AppKey；任何一个缺失即返回 `.unavailable`，否则返回 `.available`。

所有用于匹配的 gatewayId 和 meshNetworkId 统一转为小写；空 gatewayId 按未绑定处理。

- [ ] **Step 4: 运行测试并确认 GREEN**

Run:

```bash
bash scripts/check_gateway_associated_space_candidates.sh
```

Expected:

```text
GatewayAssociatedSpaceCandidatePolicyTests passed
PASS: Gateway Associated Spaces candidate policy
```

### Task 2: 将 Gateway 页面接到显式 Site 网络快照

**Files:**

- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayAssociatedSpacesController.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Modify: `scripts/check_gateway_associated_space_candidates.sh`

**Interfaces:**

- Consumes: Task 1 的 candidate policy。
- Produces: `GatewayAssociatedSpacesCandidateLoadResult.available([GatewaySpaceData])`
- Produces: `GatewayAssociatedSpacesCandidateLoadResult.unavailable`
- Produces: `GatewayAssociatedSpacesController.init(gateway:candidateProvider:)`

- [ ] **Step 1: 扩展测试 runner 的集成约束并确认失败**

Runner 必须验证新 policy 文件被四个 app target 编译。缺少 target membership 时失败。

Run:

```bash
bash scripts/check_gateway_associated_space_candidates.sh
```

Expected: FAIL，提示 policy 必须属于四个 target。

- [ ] **Step 2: 在 GatewayViewController 生成显式候选**

新增私有候选方法：

1. 使用 `MeshNetwork.load(meshUUID: site.meshUUID, subnetworkId: site.meshNetworkId, allData: false)` 获取最新 Site 网络快照。
2. 从该快照建立 `networkId -> appKeyIndex` 映射，不读取 `MeshNetworkManager.instance.meshNetwork`。
3. 将 `site.spaces` 映射为 policy 输入，其中 `canEdit` 必须同时满足 `canEditing` 和 `deviceOperates.contains(.edit)`。
4. `.available` 映射为 `GatewaySpaceData(permission: .editor)`。
5. `.unavailable` 保留缺失 Space ID 的 DEBUG 诊断并返回数据不可用。

- [ ] **Step 3: 让选择页在首次加载和 Retry 时重新取候选**

`GatewayAssociatedSpacesController` 不再只接收固定数组，改为接收 provider：

```swift
enum GatewayAssociatedSpacesCandidateLoadResult {
    case available([GatewaySpaceData])
    case unavailable
}
```

每次 `loadAssociatedSpaces()`：

1. 先调用 provider 刷新本地候选。
2. 再请求服务器当前 Gateway 的 `refSpaces`。
3. 若服务器补回了合法已绑定 Space，正常展示。
4. 合并后为空且候选 `.available([])`，显示 `no_data`。
5. 合并后为空且候选 `.unavailable`，显示现有获取失败状态和 `RETRY`。

- [ ] **Step 4: 将新文件加入四个 target**

在 `project.pbxproj` 中增加：

- 1 个 `PBXFileReference`
- 4 个 `PBXBuildFile`
- Gateway `Model` group 条目
- 四个 `PBXSourcesBuildPhase` 条目

- [ ] **Step 5: 运行聚焦 GREEN 验证**

Run:

```bash
bash scripts/check_gateway_associated_space_candidates.sh
bash scripts/check_gateway_associated_spaces_deferred_save.sh
bash scripts/check_site_gateway_online_state.sh
```

Expected: 三个脚本均 PASS。

### Task 3: 完整静态与构建验证

**Files:**

- Modify only if verification reveals an in-scope defect.

- [ ] **Step 1: 检查改动范围和格式**

Run:

```bash
git diff --check
git status --short
```

Expected: 无 whitespace error；改动只包含分析/计划文档、policy、两个 Gateway controller、测试、runner 和 project 配置。

- [ ] **Step 2: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: 最终复核**

重新运行三个聚焦脚本和 `git diff --check`，阅读完整 diff，确认：

1. Gateway `SAVE` 和 bind/unbind 请求位置未改变。
2. WiFi Gateway 继续继承共享入口。
3. 无新增本地化、资源、依赖或 Auth 信息。
4. 自动化只能证明候选策略、静态契约和编译；真机、真实服务器与 Gateway 硬件验收仍待执行。
