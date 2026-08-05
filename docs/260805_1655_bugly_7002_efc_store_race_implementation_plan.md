# Bugly #7002 EFC Store Race Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This repository requires Inline Execution and does not authorize subagents or commits for this task.

**Goal:** 为 EFC Store 的共享缓存建立单一、可测试的并发边界，消除 Groups 页面并发同步态计算触发的 Swift Array/ARC 崩溃。

**Architecture:** 新增一个只负责数组容器同步的 `DeviceEmerFireCache<Element>`，使用私有 `NSLock` 保护 replace、merge、remove 和 snapshot。`DeviceEmerFireStore` 保留现有数据库、Mesh、通知与业务流程，只把所有内存缓存访问收口到该容器；锁不覆盖数据库、MeshNetwork、通知或 proxy filter 操作。

**Tech Stack:** Swift、Foundation `NSLock`、GCD、Thread Sanitizer、现有 standalone Swift contract、Xcode generic iPhoneOS build。

## Global Constraints

- 所有回复、计划和总结使用简体中文；UI 文案默认英文，但本任务不修改用户可见文案。
- 当前年份按 2026 年处理。
- 不新增 Auth 信息，不修改本地化、资源、依赖或 SDK。
- 保持改动聚焦，不重构 `Group.needSync`、Node 同步缓存、EFC Repository 或 Mesh 并发模型。
- 不使用 Simulator 做构建校验。
- 共享 Swift 文件必须检查 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 scheme。
- 不执行 Git commit、push 或 merge。

---

### Task 1: 用真实缓存 API 建立并发回归测试

**Files:**

- Create: `Tests/Device/DeviceEmerFireCacheTests.swift`
- Create: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireCache.swift`

**Interfaces:**

- Consumes: Foundation `NSLock`、GCD `DispatchGroup` 与 `DispatchQueue`。
- Produces: `DeviceEmerFireCache<Element>`，公开 `replace(with:)`、`merge(_:matching:)`、`removeAll(where:)`、`snapshot()` 四个内部模块 API。

- [x] **Step 1: 先创建失败测试**

创建 `Tests/Device/DeviceEmerFireCacheTests.swift`：

```swift
import Dispatch
import Foundation

private struct CacheRecord: Equatable, Sendable {
    let id: Int
    let revision: Int
}

@main
struct DeviceEmerFireCacheTests {

    static func main() {
        testReplaceReturnsIndependentSnapshot()
        testMergeReplacesMatchingAndAppendsNewRecords()
        testRemoveAllRemovesOnlyMatchingRecords()
        testConcurrentMergesKeepOneRecordPerIdentifier()
        print("DeviceEmerFireCacheTests passed")
    }

    private static func testReplaceReturnsIndependentSnapshot() {
        let cache = DeviceEmerFireCache<CacheRecord>()
        var source = [CacheRecord(id: 1, revision: 10)]
        cache.replace(with: source)
        source.append(CacheRecord(id: 2, revision: 20))

        precondition(cache.snapshot() == [CacheRecord(id: 1, revision: 10)])
    }

    private static func testMergeReplacesMatchingAndAppendsNewRecords() {
        let cache = DeviceEmerFireCache<CacheRecord>()
        cache.replace(with: [CacheRecord(id: 1, revision: 10)])
        cache.merge([
            CacheRecord(id: 1, revision: 11),
            CacheRecord(id: 2, revision: 20),
        ]) { existing, incoming in
            existing.id == incoming.id
        }

        precondition(cache.snapshot() == [
            CacheRecord(id: 1, revision: 11),
            CacheRecord(id: 2, revision: 20),
        ])
    }

    private static func testRemoveAllRemovesOnlyMatchingRecords() {
        let cache = DeviceEmerFireCache<CacheRecord>()
        cache.replace(with: [
            CacheRecord(id: 1, revision: 10),
            CacheRecord(id: 2, revision: 20),
            CacheRecord(id: 3, revision: 30),
        ])
        cache.removeAll { $0.id.isMultiple(of: 2) }

        precondition(cache.snapshot() == [
            CacheRecord(id: 1, revision: 10),
            CacheRecord(id: 3, revision: 30),
        ])
    }

    private static func testConcurrentMergesKeepOneRecordPerIdentifier() {
        let cache = DeviceEmerFireCache<CacheRecord>()
        cache.replace(with: (0..<64).map { CacheRecord(id: $0, revision: 0) })
        let group = DispatchGroup()

        for worker in 0..<32 {
            DispatchQueue.global().async(group: group) {
                for iteration in 0..<2_000 {
                    let id = (worker + iteration) % 64
                    cache.merge([CacheRecord(id: id, revision: worker * 2_000 + iteration)]) {
                        $0.id == $1.id
                    }
                    _ = cache.snapshot()
                }
            }
        }

        group.wait()
        let snapshot = cache.snapshot()
        precondition(snapshot.count == 64)
        precondition(Set(snapshot.map(\.id)) == Set(0..<64))
    }
}
```

- [x] **Step 2: 运行测试并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Device/DeviceEmerFireCacheTests.swift -o /tmp/DeviceEmerFireCacheTests
```

Expected: 编译失败，明确提示找不到 `DeviceEmerFireCache`，证明测试依赖尚未实现的生产 API。

- [x] **Step 3: 创建临时无锁实现，确认测试能捕获真实 race**

先在 `DeviceEmerFireCache.swift` 写入同 API 的无锁数组实现，仅用于 RED 验证：

```swift
import Foundation

final class DeviceEmerFireCache<Element>: @unchecked Sendable {
    private var elements: [Element] = []

    func replace(with newElements: [Element]) {
        elements = newElements
    }

    func merge(_ newElements: [Element], matching areSame: (Element, Element) -> Bool) {
        newElements.forEach { incoming in
            if let index = elements.firstIndex(where: { areSame($0, incoming) }) {
                elements[index] = incoming
            } else {
                elements.append(incoming)
            }
        }
    }

    func removeAll(where shouldRemove: (Element) -> Bool) {
        elements.removeAll(where: shouldRemove)
    }

    func snapshot() -> [Element] {
        elements
    }
}
```

Run:

```bash
swiftc -sanitize=thread -parse-as-library SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireCache.swift Tests/Device/DeviceEmerFireCacheTests.swift -o /tmp/DeviceEmerFireCacheTestsTSan
TSAN_OPTIONS=halt_on_error=1 /tmp/DeviceEmerFireCacheTestsTSan
```

Expected: Thread Sanitizer 报告 `Swift access race` 或 data race，并以非零状态退出。若未触发，增加 worker/iteration 后重跑，不进入 GREEN。

- [x] **Step 4: 用最小锁实现进入 GREEN**

将临时实现替换为最终实现：

```swift
import Foundation

final class DeviceEmerFireCache<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Element] = []

    func replace(with newElements: [Element]) {
        withLock {
            elements = newElements
        }
    }

    func merge(_ newElements: [Element], matching areSame: (Element, Element) -> Bool) {
        withLock {
            newElements.forEach { incoming in
                if let index = elements.firstIndex(where: { areSame($0, incoming) }) {
                    elements[index] = incoming
                } else {
                    elements.append(incoming)
                }
            }
        }
    }

    func removeAll(where shouldRemove: (Element) -> Bool) {
        withLock {
            elements.removeAll(where: shouldRemove)
        }
    }

    func snapshot() -> [Element] {
        withLock { elements }
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
```

- [x] **Step 5: 运行普通测试和 TSan 测试并确认 GREEN**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireCache.swift Tests/Device/DeviceEmerFireCacheTests.swift -o /tmp/DeviceEmerFireCacheTests
/tmp/DeviceEmerFireCacheTests
swiftc -sanitize=thread -parse-as-library SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireCache.swift Tests/Device/DeviceEmerFireCacheTests.swift -o /tmp/DeviceEmerFireCacheTestsTSan
TSAN_OPTIONS=halt_on_error=1 /tmp/DeviceEmerFireCacheTestsTSan
```

Expected: 两次运行都打印 `DeviceEmerFireCacheTests passed` 并以 0 退出；TSan 不报告 race。

---

### Task 2: 将 EFC Store 全部缓存访问收口到同步容器

**Files:**

- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift:18-220`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: Task 1 的 `DeviceEmerFireCache<DeviceEmerFireData>`。
- Produces: `DeviceEmerFireStore.devices` 只读快照，以及线程安全的 replace、merge、delete 缓存路径。

- [x] **Step 1: 替换共享数组字段**

将现有字段：

```swift
private(set) var devices: [DeviceEmerFireData] = []
```

替换为：

```swift
private let cache = DeviceEmerFireCache<DeviceEmerFireData>()

var devices: [DeviceEmerFireData] {
    cache.snapshot()
}
```

- [x] **Step 2: 收口全部缓存写入口**

在 `loadDevices` 中把直接赋值替换为：

```swift
cache.replace(with: devices)
```

在 `delete` 中把直接 `removeAll` 替换为：

```swift
cache.removeAll { $0.id == device.id }
```

将 `mergeCache(with:)` 替换为：

```swift
private func mergeCache(with newDevices: [DeviceEmerFireData]) {
    cache.merge(newDevices) { existing, incoming in
        existing.id == incoming.id
    }
}
```

数据库保存、Mesh 操作、proxy filter 刷新和通知发送保持在缓存锁之外。

- [x] **Step 3: 把新文件加入四个 target**

在 `project.pbxproj` 中：

- 新增 `DeviceEmerFireCache.swift` 的一个 `PBXFileReference`；
- 在 FireAlarm `Model` group 中放在 `DeviceEmerFireData.swift` 相邻位置；
- 新增四个 `PBXBuildFile`；
- 分别加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 的 Sources phase。

使用以下不与现有条目冲突的 ID：

- File reference: `8C7002002FC0000000007002`
- Build files: `8C7002012FC0000000007002`、`8C7002022FC0000000007002`、`8C7002032FC0000000007002`、`8C7002042FC0000000007002`

- [x] **Step 4: 审计没有绕过缓存容器的数组写入**

Run:

```bash
rg -n "self\.devices\s*=|devices\.removeAll|devices\[.*\]\s*=|devices\.append" SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift
```

Expected: 不再命中 `DeviceEmerFireStore` 的缓存写入；允许命中 `mergeRealEmergencyControllers` 内部的局部变量操作。

- [x] **Step 5: 重跑缓存测试**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireCache.swift Tests/Device/DeviceEmerFireCacheTests.swift -o /tmp/DeviceEmerFireCacheTests
/tmp/DeviceEmerFireCacheTests
```

Expected: `DeviceEmerFireCacheTests passed`。

---

### Task 3: 接入现有 EFC 回归入口并完成自动化验证

**Files:**

- Modify: `scripts/check_efc_controller_flows.sh`
- Verify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireCache.swift`
- Verify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift`
- Verify: `Tests/Device/DeviceEmerFireCacheTests.swift`

**Interfaces:**

- Consumes: Task 1 的 standalone test binary。
- Produces: EFC 总契约脚本每次都运行真实缓存行为测试。

- [x] **Step 1: 在 EFC 脚本末尾编译并运行缓存测试**

在最终成功输出前加入：

```bash
cache_source="SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireCache.swift"
cache_tests="Tests/Device/DeviceEmerFireCacheTests.swift"
cache_test_binary="/tmp/DeviceEmerFireCacheTests"

swiftc -parse-as-library "$cache_source" "$cache_tests" -o "$cache_test_binary"
"$cache_test_binary"
```

- [x] **Step 2: 运行 EFC 总契约**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: 先打印 `DeviceEmerFireCacheTests passed`，最后打印 `EFC controller flow contracts passed.`。

- [x] **Step 3: 运行最终 TSan stress**

Run:

```bash
swiftc -sanitize=thread -parse-as-library SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireCache.swift Tests/Device/DeviceEmerFireCacheTests.swift -o /tmp/DeviceEmerFireCacheTestsTSan
TSAN_OPTIONS=halt_on_error=1 /tmp/DeviceEmerFireCacheTestsTSan
```

Expected: 退出码 0，无 race 报告。

- [x] **Step 4: 运行 diff 检查**

Run:

```bash
git diff --check
```

Expected: 退出码 0，无输出。

---

### Task 4: 验证四个共享 target 并记录边界

**Files:**

- Create: `docs/260805_1655_bugly_7002_efc_store_race_implementation_summary.md`
- Verify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: Tasks 1-3 的源码、测试与工程配置。
- Produces: 四 target 编译证据和明确的真机/Bugly 验收边界。

- [x] **Step 1: 直接构建 SunSmart generic iPhoneOS**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [x] **Step 2: 直接构建 Archipelago generic iPhoneOS**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [x] **Step 3: 直接构建 SLG Sync Plus generic iPhoneOS**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [x] **Step 4: 直接构建 SylSmart generic iPhoneOS**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`。

- [x] **Step 5: 写实现总结**

总结必须包含：

- 变更文件与并发边界；
- TDD RED、TSan RED、普通 GREEN、TSan GREEN 的实际结果；
- EFC 总契约与四 target 构建结果；
- 未执行真机 Groups 页面压力回归；
- 未观察带修复版本的 Bugly 数据，因此不能声明线上崩溃已归零；
- 未修改 SDK、本地化、资源、依赖或 Auth；
- 未执行 commit、push 或 merge。

- [x] **Step 6: 最终审阅**

Run:

```bash
git status --short
git diff --stat
git diff -- SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireCache.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift Tests/Device/DeviceEmerFireCacheTests.swift scripts/check_efc_controller_flows.sh SunSmart.xcodeproj/project.pbxproj
```

Expected: 仅包含本计划、上一轮分析文档、缓存实现、Store 接入、测试、EFC 脚本、工程配置和实现总结；没有无关格式化或业务改动。
