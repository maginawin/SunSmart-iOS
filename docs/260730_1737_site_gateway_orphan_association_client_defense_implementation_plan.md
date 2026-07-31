# Site Gateway Orphan Association Client Defense Implementation Plan

> **执行方式：** REQUIRED SUB-SKILL: 使用
> `superpowers:executing-plans` 在当前会话 Inline Execution；每个任务按
> RED→GREEN 执行，不使用 subagents。

**Goal:** 对 owner 的完整 `siteInfo` 快照执行 Gateway 关联完整性校验，使顶层
Gateway 不存在时的孤儿 Space 关联显示为 No Gateway，同时保留本地 Node 暂时
无法解析时的服务器 Internet online/offline 状态。

**Architecture:** 新增一个 Foundation-only 的
`SiteGatewayAssociationSnapshot` policy，负责判定 Gateway 快照是否权威及
Space Gateway ID 是否为孤儿。`SiteData.update` 使用同一次响应中的
`gateways` 构造 snapshot，只归一化本次响应导入的 Space；Site UI 继续只读消费
`SpaceData.gatewayStatus`，不增加第二套过滤。

**Tech Stack:** Swift、Foundation、SwiftyJSON、SQLite-backed model storage、
standalone `swiftc` tests、source contract tests、Xcode generic iPhoneOS builds。

## Global Constraints

- 只对 `role == owner` 且 `gateways` 数组完整有效的 `siteInfo` 启用强校验。
- `gateways = []` 是权威空快照。
- editor、visitor、缺失或格式异常的 Gateway 快照必须保留 Space 服务器状态。
- 不使用本地 `GatewayModel`、`MeshNetworkManager`、`Node.state` 或
  `showGatewayModels` 判断服务器 Gateway 是否存在。
- 不恢复 `SiteViewController.setupData()` 对 `SpaceData.gatewayStatus` 的写入。
- 不修改 Gateway bind、unbind、delete API 或请求顺序。
- 不修改 Wi-Fi/4G 协议、NordicSigMeshSDK、依赖、资源或用户可见文案。
- 新生产文件加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。
- 保留当前 worktree 中已完成但未提交的 Associated Spaces 方案 A 改动。
- 不执行 Git commit、push 或 merge。

---

## File Structure

- Create:
  `SunSmart/Common/Data/SiteGatewayAssociationConsistencyPolicy.swift`
  - 只负责 Gateway ID 归一化、权威快照构造和孤儿关联决策。
- Create:
  `Tests/Site/SiteGatewayAssociationConsistencyPolicyTests.swift`
  - 独立执行 policy 的行为测试。
- Modify:
  `SunSmart/Common/Data/ImportData.swift`
  - 使用同一次 `siteInfo` 的 Gateway 快照归一化本次导入的 Space。
- Modify:
  `Tests/Site/SiteGatewayOnlineStateContractTests.swift`
  - 增加导入链契约，同时保留此前 Internet 状态真值约束。
- Modify:
  `scripts/check_site_gateway_online_state.sh`
  - 串行执行新 policy 测试和既有源码契约。
- Modify:
  `SunSmart.xcodeproj/project.pbxproj`
  - 将新 policy 加入 Common/Data group 和四个 app target。

---

### Task 1: 建立 Gateway 快照一致性 Policy

**Files:**

- Create:
  `Tests/Site/SiteGatewayAssociationConsistencyPolicyTests.swift`
- Create after RED:
  `SunSmart/Common/Data/SiteGatewayAssociationConsistencyPolicy.swift`
- Modify:
  `scripts/check_site_gateway_online_state.sh`

**Interfaces:**

- Produces:
  `SiteGatewayAssociationConsistencyDecision`
- Produces:
  `SiteGatewayAssociationSnapshot.make(isComplete:rawGatewayIds:)`
- Produces:
  `SiteGatewayAssociationSnapshot.decision(for:)`

- [ ] **Step 1: 写入 policy 失败测试**

创建测试入口，覆盖：

```swift
import Foundation

@main
struct SiteGatewayAssociationConsistencyPolicyTests {

    static func main() {
        testCompleteEmptySnapshotClearsOrphan()
        testCompleteSnapshotPreservesMatchingGateway()
        testGatewayIdMatchingIgnoresCaseAndOuterWhitespace()
        testRestrictedSnapshotPreservesOrphan()
        testMissingGatewayArrayPreservesOrphan()
        testMalformedGatewayEntryMakesSnapshotNonAuthoritative()
        testSpaceWithoutGatewayIsPreserved()
        print("SiteGatewayAssociationConsistencyPolicyTests passed")
    }

    private static func testCompleteEmptySnapshotClearsOrphan() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: true,
            rawGatewayIds: []
        )
        precondition(
            snapshot.decision(for: "EF725643A2B9") ==
                .clearOrphan(gatewayId: "EF725643A2B9")
        )
    }

    private static func testCompleteSnapshotPreservesMatchingGateway() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: true,
            rawGatewayIds: ["EF725643A2B9"]
        )
        precondition(
            snapshot.decision(for: "EF725643A2B9") == .preserve
        )
    }

    private static func testGatewayIdMatchingIgnoresCaseAndOuterWhitespace() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: true,
            rawGatewayIds: [" ef725643a2b9 "]
        )
        precondition(
            snapshot.decision(for: "EF725643A2B9") == .preserve
        )
    }

    private static func testRestrictedSnapshotPreservesOrphan() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: false,
            rawGatewayIds: []
        )
        precondition(
            snapshot.decision(for: "EF725643A2B9") == .preserve
        )
    }

    private static func testMissingGatewayArrayPreservesOrphan() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: true,
            rawGatewayIds: nil
        )
        precondition(
            snapshot.decision(for: "EF725643A2B9") == .preserve
        )
    }

    private static func testMalformedGatewayEntryMakesSnapshotNonAuthoritative() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: true,
            rawGatewayIds: ["EF725643A2B9", nil]
        )
        precondition(
            snapshot.decision(for: "ORPHAN") == .preserve
        )
    }

    private static func testSpaceWithoutGatewayIsPreserved() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: true,
            rawGatewayIds: []
        )
        precondition(snapshot.decision(for: nil) == .preserve)
        precondition(snapshot.decision(for: "  ") == .preserve)
    }
}
```

- [ ] **Step 2: 扩展 runner 并确认 RED**

在既有脚本中增加：

```bash
policy_source="$repo_root/SunSmart/Common/Data/SiteGatewayAssociationConsistencyPolicy.swift"
policy_test_source="$repo_root/Tests/Site/SiteGatewayAssociationConsistencyPolicyTests.swift"
policy_test_binary="$temp_dir/site_gateway_association_consistency_policy_tests"

swiftc -parse-as-library \
  "$policy_source" \
  "$policy_test_source" \
  -o "$policy_test_binary"
"$policy_test_binary"
```

运行：

```bash
bash scripts/check_site_gateway_online_state.sh
```

Expected：FAIL，明确提示 policy 源文件不存在或对应类型未定义。

- [ ] **Step 3: 实现最小 policy**

创建：

```swift
import Foundation

enum SiteGatewayAssociationConsistencyDecision: Equatable {
    case preserve
    case clearOrphan(gatewayId: String)
}

struct SiteGatewayAssociationSnapshot {

    private let authoritativeGatewayIds: Set<String>?

    static func make(
        isComplete: Bool,
        rawGatewayIds: [String?]?
    ) -> SiteGatewayAssociationSnapshot {
        guard isComplete, let rawGatewayIds else {
            return .init(authoritativeGatewayIds: nil)
        }

        var normalizedIds: Set<String> = []
        for rawGatewayId in rawGatewayIds {
            guard let gatewayId = normalized(rawGatewayId) else {
                return .init(authoritativeGatewayIds: nil)
            }
            normalizedIds.insert(gatewayId)
        }
        return .init(authoritativeGatewayIds: normalizedIds)
    }

    func decision(
        for rawSpaceGatewayId: String?
    ) -> SiteGatewayAssociationConsistencyDecision {
        guard
            let displayGatewayId = rawSpaceGatewayId?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !displayGatewayId.isEmpty,
            let normalizedSpaceGatewayId = Self.normalized(displayGatewayId),
            let authoritativeGatewayIds
        else {
            return .preserve
        }

        guard !authoritativeGatewayIds.contains(normalizedSpaceGatewayId) else {
            return .preserve
        }
        return .clearOrphan(gatewayId: displayGatewayId)
    }

    private static func normalized(_ rawGatewayId: String?) -> String? {
        guard let gatewayId = rawGatewayId?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !gatewayId.isEmpty else {
            return nil
        }
        return gatewayId.lowercased()
    }
}
```

- [ ] **Step 4: 运行 policy 测试并确认 GREEN**

Run：

```bash
bash scripts/check_site_gateway_online_state.sh
```

Expected：

```text
SiteGatewayAssociationConsistencyPolicyTests passed
SiteGatewayOnlineStateContractTests passed
PASS: Site Gateway online-state source ownership checks passed.
```

---

### Task 2: 将 Policy 接入完整 Site 快照导入

**Files:**

- Modify:
  `Tests/Site/SiteGatewayOnlineStateContractTests.swift`
- Modify:
  `scripts/check_site_gateway_online_state.sh`
- Modify:
  `SunSmart/Common/Data/ImportData.swift`

**Interfaces:**

- Consumes:
  `SiteGatewayAssociationSnapshot.make(isComplete:rawGatewayIds:)`
- Consumes:
  `SiteGatewayAssociationSnapshot.decision(for:)`
- Preserves:
  `SiteViewController.setupData()` 的服务器状态只读约束。

- [ ] **Step 1: 扩展导入契约测试**

把 contract test 参数从 Site/Gateway 两个源码路径扩展为三个：

```swift
guard CommandLine.arguments.count == 4 else {
    fatalError(
        "Expected SiteViewController.swift, GatewayViewController.swift " +
        "and ImportData.swift paths"
    )
}

let importSource = try String(
    contentsOfFile: CommandLine.arguments[3],
    encoding: .utf8
)
```

新增约束：

```swift
require(
    importSource.contains(
        "SiteGatewayAssociationSnapshot.make("
    ),
    "SiteData.update must create a server Gateway identity snapshot"
)
require(
    importSource.contains("isComplete: self.permission == .owner"),
    "Only owner Site snapshots may enable strong orphan validation"
)
require(
    importSource.contains(
        "rawGatewayIds: gatewayDicts?.map"
    ),
    "The consistency snapshot must use the same siteInfo gateways payload"
)
require(
    importSource.contains(
        "gatewaySnapshot.decision(for: space.relevanceGatewayId)"
    ),
    "Every server-returned Space must be checked against the snapshot"
)
require(
    importSource.contains("space.relevanceGatewayId = nil") &&
    importSource.contains("space.gatewayStatus = .notBound") &&
    importSource.contains("space.gatewayLastOnline = nil") &&
    importSource.contains("space.save()"),
    "Orphan normalization must clear all Gateway state and persist it"
)
```

保留既有契约：

- `setupData()` 不写 `space.gatewayStatus`。
- Site Gateway 运行期对象继续从显式 Site 主网解析。
- 不按 Wi-Fi/4G 类型分支。

- [ ] **Step 2: 将 ImportData 路径传入 runner 并确认 RED**

增加：

```bash
import_source="$repo_root/SunSmart/Common/Data/ImportData.swift"
```

把 contract test 执行改为：

```bash
"$test_binary" \
  "$site_source" \
  "$gateway_source" \
  "$import_source"
```

Run：

```bash
bash scripts/check_site_gateway_online_state.sh
```

Expected：FAIL，提示 `SiteData.update must create a server Gateway identity
snapshot`。

- [ ] **Step 3: 在 SiteData.update 构造同响应 Gateway 快照**

在 Space 导入前解析一次 Gateway 字典：

```swift
let gatewayDicts =
    json["gateways"].arrayObject as? [[String: Any]]
let gatewaySnapshot = SiteGatewayAssociationSnapshot.make(
    isComplete: self.permission == .owner,
    rawGatewayIds: gatewayDicts?.map {
        $0["macAddress"] as? String
    }
)
```

后续 Gateway 导入把重复解析改为：

```swift
if let gatewayDicts {
    if let network = meshNetwork {
        // 保持现有 Gateway 导入逻辑
    }
}
```

不得改变 Gateway cache 删除、Node 导入或 timestamp 覆盖规则。

- [ ] **Step 4: 只归一化本次服务器返回的 Space**

在 task group 收集完局部 `spaces` 数组之后、合并到 `self.spaces` 之前执行：

```swift
spaces.forEach { space in
    switch gatewaySnapshot.decision(
        for: space.relevanceGatewayId
    ) {
    case .preserve:
        break
    case .clearOrphan(let gatewayId):
        space.relevanceGatewayId = nil
        space.gatewayStatus = .notBound
        space.gatewayLastOnline = nil
        let saved = space.save()
#if DEBUG
        print(
            "[SiteGatewayAssociationConsistency]",
            "siteId=\(self.id)",
            "spaceId=\(space.id)",
            "orphanGatewayId=\(gatewayId)",
            "scope=ownerComplete",
            "saved=\(saved)"
        )
#endif
    }
}
```

不得遍历或修改未出现在本次服务器响应中的本地未上传 Space。

- [ ] **Step 5: 运行聚焦测试并确认 GREEN**

Run：

```bash
bash scripts/check_site_gateway_online_state.sh
```

Expected：policy 测试和源码契约全部 PASS。

- [ ] **Step 6: 阅读导入链 diff**

确认：

1. `gatewayDicts` 只解析一次并被 Space consistency 与 Gateway 导入共用。
2. 只有 `.clearOrphan` 修改三个 Gateway 状态字段。
3. `space.save()` 不创建 CloudSynchronization operation。
4. DEBUG 日志不包含 Key、Auth 或 Node payload。
5. Site UI 没有新增过滤或状态写入。

---

### Task 3: 将 Policy 加入四个 App Target

**Files:**

- Modify:
  `scripts/check_site_gateway_online_state.sh`
- Modify:
  `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes:
  `SiteGatewayAssociationConsistencyPolicy.swift`
- Produces:
  四个 app target 的 production compile membership。

- [ ] **Step 1: 增加 target membership 契约并确认 RED**

在 runner 中增加：

```bash
project_file="$repo_root/SunSmart.xcodeproj/project.pbxproj"
source_phase_count="$(
  rg \
    'SiteGatewayAssociationConsistencyPolicy.swift in Sources \*/,' \
    "$project_file" |
  rg -v '= \{isa' |
  wc -l |
  tr -d ' '
)"

[ "$source_phase_count" -eq 4 ] || {
  echo "FAIL: consistency policy must belong to all four app targets" >&2
  exit 1
}
```

Run：

```bash
bash scripts/check_site_gateway_online_state.sh
```

Expected：FAIL，提示 policy 必须属于四个 app target。

- [ ] **Step 2: 更新 Xcode project**

在 `project.pbxproj` 中增加：

- 1 个 `PBXFileReference`
- 4 个不同的 `PBXBuildFile`
- Common/Data group 的文件条目
- SunSmart Sources 条目
- Archipelago Sources 条目
- SLG Sync Plus Sources 条目
- SylSmart Sources 条目

使用新的、不与现有 `C8FA301*` Associated Spaces policy 冲突的 PBX ID。

- [ ] **Step 3: 运行 target membership GREEN**

Run：

```bash
bash scripts/check_site_gateway_online_state.sh
```

Expected：全部 PASS，且 target membership count 为 4。

---

### Task 4: 回归与四品牌构建验证

**Files:**

- Modify only if verification exposes an in-scope defect.

**Interfaces:**

- Verifies:
  policy、导入契约、Associated Spaces 现有修复、四品牌编译。

- [ ] **Step 1: 运行聚焦回归**

Run：

```bash
bash scripts/check_site_gateway_online_state.sh
bash scripts/check_gateway_associated_space_candidates.sh
bash scripts/check_gateway_associated_spaces_deferred_save.sh
```

Expected：所有脚本 PASS。

- [ ] **Step 2: 检查改动范围**

Run：

```bash
git diff --check
git status --short
git diff --stat
```

Expected：

- 无 whitespace error。
- 本任务生产改动只涉及 policy、`ImportData.swift` 和 project 配置。
- 没有本地化、资源、依赖、Auth、Gateway API 或协议改动。
- 现有未提交 Associated Spaces 改动完整保留。

- [ ] **Step 3: 构建 SunSmart**

Run：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`** BUILD SUCCEEDED **`

- [ ] **Step 4: 构建 Archipelago**

Run：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`** BUILD SUCCEEDED **`

- [ ] **Step 5: 构建 SLG Sync Plus**

Run：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`** BUILD SUCCEEDED **`

- [ ] **Step 6: 构建 SylSmart**

Run：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`** BUILD SUCCEEDED **`

- [ ] **Step 7: 最终复核**

重新运行：

```bash
bash scripts/check_site_gateway_online_state.sh
git diff --check
```

并逐项确认：

1. owner + `gateways = []` + 两个孤儿 Space → 两个 `.notBound`。
2. owner + 顶层 Gateway 匹配 + 本地 Node 不可解析 → 保留服务器 online。
3. editor/visitor 和格式异常快照 → preserve。
4. `setupData()` 不重新写入 Space Internet 状态。
5. 自动化与构建不能替代真实服务器、权限账号和真机验收。

---

## 真机/服务器验收清单

1. 使用问题 Site 的 owner 账号请求 `siteInfo`。
2. 确认顶层 `gateways = []`，两个 Space 仍残留 Gateway 字段。
3. 进入 Site：
   - `Internet Online: 0`
   - `Internet Offline: 0`
   - `No Gateway: 2`
   - 两个 Space 卡片不显示 Gateway online/offline 图标。
4. 使用一个顶层 Gateway 正常存在但临时无法解析本地 Node 的 Site：
   - Site Internet 状态仍按服务器字段展示。
5. 使用 editor 和 visitor 账号回归 Site：
   - 行为保持现状，不因顶层列表可能裁剪而误清关联。
6. 删除一个真实关联两个 Space 的 Gateway 后重新请求 `siteInfo`，记录服务端是否
   已同步清理 Space 字段；客户端防御通过不代表服务端问题已解决。
