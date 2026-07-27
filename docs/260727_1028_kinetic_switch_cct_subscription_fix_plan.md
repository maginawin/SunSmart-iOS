# Kinetic Switch CCT Subscription Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 阻止仅支持调光的单色灯被 Kinetic Switch 的 Cooler / Warmer 动作订阅到色温虚拟组，同时保持色温灯、亮度调节以及 Default / Scene Panel 行为不变。

**Architecture:** 在本地 `NordicSigMeshSDK` 中把“从 Temperature 元素解析对应 Generic Level Model”的决策提取为可独立测试的纯 Swift resolver。`Node.ctlTemperatureLevelModel` 只通过该 resolver 查找 Temperature 元素上的 Level Model，不再在没有 Temperature Model 时回退到任意亮度 Level Model；现有 EnOcean 订阅生成逻辑无需修改。

**Tech Stack:** Swift 5、NordicSigMeshSDK、Foundation-only standalone contract test、Xcode generic iPhoneOS build。

## Global Constraints

- 仅处理新创建或删除后重新创建的 Switch；不清理已经错误配置的设备订阅。
- 不修改 `DeviceSwitchData.switchKeys`、Panel UI、Scene Recall、虚拟组分配或 EnOcean payload 编码。
- 不处理日志中的重复 Subscription Add 优化。
- App 继续引用 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk` 本地 Swift Package。
- 不新增 Auth 信息，不格式化或重构无关文件。
- 所有构建使用 generic iPhoneOS，不使用 Simulator。
- 不主动创建 Git commit，保留 App 与 SDK 两个仓库的聚焦 diff 供用户检查。

---

### Task 1: 用 TDD 收紧 CCT Level Model 解析

**Files:**

- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/Standalone/CctLevelModelResolverTests.swift`
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/CctLevelModelResolver.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`

**Interfaces:**

- Consumes: `Node.temperatureModel?.parentElement` 与 `Node.getFunctionModel(elements:modelId:)`。
- Produces: `CctLevelModelResolver.resolve(temperatureElement:levelModelInElement:) -> LevelModel?`；`Node.ctlTemperatureLevelModel` 在没有 Temperature 元素时返回 `nil`。

- [ ] **Step 1: 写 standalone 失败测试**

测试直接覆盖 resolver 的可观察决策，不读取或匹配源码文本：

```swift
@main
struct CctLevelModelResolverTests {
    enum Element: Equatable {
        case brightness
        case temperature
    }

    static func main() {
        testDimmableOnlyNodeHasNoCctLevelModel()
        testTemperatureElementResolvesItsOwnLevelModel()
        testTemperatureElementWithoutLevelModelReturnsNil()
        print("CctLevelModelResolverTests passed")
    }

    private static func testDimmableOnlyNodeHasNoCctLevelModel() {
        var lookupCalled = false
        let result: String? = CctLevelModelResolver.resolve(
            temperatureElement: Optional<Element>.none
        ) { _ in
            lookupCalled = true
            return "brightness-level"
        }

        precondition(result == nil)
        precondition(!lookupCalled)
    }

    private static func testTemperatureElementResolvesItsOwnLevelModel() {
        let result: String? = CctLevelModelResolver.resolve(
            temperatureElement: Element.temperature
        ) { element in
            element == .temperature ? "temperature-level" : "brightness-level"
        }

        precondition(result == "temperature-level")
    }

    private static func testTemperatureElementWithoutLevelModelReturnsNil() {
        let result: String? = CctLevelModelResolver.resolve(
            temperatureElement: Element.temperature
        ) { _ in nil }

        precondition(result == nil)
    }
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Standalone/CctLevelModelResolverTests.swift -o /tmp/CctLevelModelResolverTests
```

Expected: FAIL，编译器报告找不到 `CctLevelModelResolver`；失败原因是待实现的能力解析边界尚不存在。

- [ ] **Step 3: 添加最小 resolver**

```swift
enum CctLevelModelResolver {
    static func resolve<Element, LevelModel>(
        temperatureElement: Element?,
        levelModelInElement: (Element) -> LevelModel?
    ) -> LevelModel? {
        guard let temperatureElement else {
            return nil
        }
        return levelModelInElement(temperatureElement)
    }
}
```

- [ ] **Step 4: 让 `Node.ctlTemperatureLevelModel` 使用 resolver**

将当前“Temperature 元素优先、否则 `levelModels.last`”改为：

```swift
return CctLevelModelResolver.resolve(
    temperatureElement: temperatureModel?.parentElement
) { element in
    getFunctionModel(
        elements: element,
        modelId: .genericLevelServerModelId
    )
}
```

该实现没有 Temperature Model 时直接返回 `nil`；色温灯仍从 Temperature 元素取 `0x1002`。

- [ ] **Step 5: 运行测试并确认 GREEN**

Run:

```bash
swiftc -parse-as-library \
  Sources/NordicSigMeshSDK/MeshLib/Node/CctLevelModelResolver.swift \
  Tests/Standalone/CctLevelModelResolverTests.swift \
  -o /tmp/CctLevelModelResolverTests
/tmp/CctLevelModelResolverTests
```

Expected: 输出 `CctLevelModelResolverTests passed`，exit code 为 0。

- [ ] **Step 6: 检查 EnOcean 消费路径未被绕过**

确认 `MeshEnOceanProxyServer.getEnOceanSubscriptionMessageHandles` 对 `cctUp / cctDown` 仍只在 `ctlTemperatureLevelModel` 非空时生成订阅，且 `dimUp / dimDown` 仍使用 `levelModel`。

Expected:

- 单色灯：CCT 分支无 Message Handle；
- 色温灯：CCT 分支继续使用 Temperature 元素 Level Model；
- 所有调光灯：Dim 分支不受影响。

### Task 2: 完成静态与四品牌集成验证

**Files:**

- Modify: `docs/260727_1023_kinetic_switch_cct_subscription_analysis.md`
- Create: `docs/260727_HHmm_kinetic_switch_cct_subscription_fix_summary.md`

**Interfaces:**

- Consumes: Task 1 的 SDK resolver 与 App 当前本地 Package 引用。
- Produces: 可审查的 App / SDK diff、四品牌 generic iPhoneOS 构建结果和真机验收清单。

- [ ] **Step 1: 检查两个仓库的 diff**

Run:

```bash
git status --short
git diff --check
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check
```

Expected: 无空白错误；App 仅有本任务文档，SDK 仅有 resolver、Node accessor 和 standalone test。

- [ ] **Step 2: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 3: 构建 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: 构建 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 构建 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 写实施总结并区分验证边界**

总结必须记录：

- standalone contract 的 RED / GREEN 证据；
- App 与 SDK 的最终 diff；
- 四个 scheme 的实际构建结果；
- 未处理历史错误订阅；
- 真机需删除旧 Switch 后重新添加；
- Default / Scene Panel 都需要验证 Cooler / Warmer 不改变 L3 亮度；
- 自动化和编译不能代替真实 Mesh 硬件验收。
