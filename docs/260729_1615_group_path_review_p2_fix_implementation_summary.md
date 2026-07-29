# Group Path Review P2 修复实施总结

## 1. 结论

评审提出的两个 P2 问题均已修复：

1. 新增尚未添加设备的 Sequence 后直接保存，现在能够被识别为逻辑数据变更，并进入既有写前云脏标记流程。
2. Space Trigger Zone 构建设备同步任务时，成员资格集合从“每个节点重新计算一次”改为“每次任务构建计算一次并复用”。

本次没有修改 Mesh Opcode、Access Payload、设备命令、服务器 API、通知所有权或 Trigger Zone 永久清理语义。

## 2. 修改内容

### 2.1 新增空 Sequence 的云同步漏标记

修改：

- `SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift`

新增 Sequence 时删除对父级 `groupPath.paths` 的提前追加，只更新子页面的 `setPaths` 编辑副本。

保存仍由 `GroupPathSequencePageController.saveAction()` 统一执行：

1. 对父级数据建立比较快照。
2. 将子页面 `setPaths` 合并到 `groupPath.paths`。
3. 判断是否发生变化。
4. 变化时先执行 `space.markLocalChangePendingCloudSync()`。
5. 再保存 `GroupInfo`。

新增空 Sequence 会改变 Path 数量，因此不再被误判为未编辑。用户未保存直接退出时，也不会再因新增操作提前修改父级数据对象。

### 2.2 Trigger Zone 资格集合复用

修改：

- `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift`

`buildSyncDatas()` 现在在节点遍历开始前调用一次 `eligibleZoneMemberKeys()`，然后把同一个 `Set<SpaceTriggerZoneMemberKey>` 传给每个节点的 `desiredNeighborAddresses`。

没有将集合保存为控制器属性，因此：

- 同一次设备任务构建内复用结果。
- 下一次初始化、保存或设备任务构建仍根据最新 Group Profile 和成员关系重新计算。
- 不会引入长期缓存失效问题。

原有邻居过滤、去重、Relay Number 判断，以及目标邻居为空时禁用 Proximity Lighting 的行为保持不变。

## 3. 测试

修改：

- `Tests/Group/PathTopologyPersistenceContractTests.swift`

新增契约覆盖：

- Sequence 新增流程不得提前修改父级 `groupPath.paths`。
- Sequence 仍必须写入 `setPaths` 编辑副本。
- Group Path 保存必须先建立快照，再合并子页面编辑结果。
- 一次 `buildSyncDatas()` 必须且只能计算一次资格集合。
- 逐节点邻居计算必须接收操作级资格集合，不能自行重建。

### 3.1 TDD 证据

Task 1 RED：

```text
Fatal error: Adding a Sequence must not mutate the parent Group Path before save
```

Task 1 GREEN：

```text
PASS: Path topology persistence contracts hold.
```

Task 2 RED：

```text
Fatal error: Per-node neighbor calculation must not rebuild global eligibility
```

Task 2 GREEN：

```text
PASS: Path topology persistence contracts hold.
```

## 4. 最终验证

### Path Topology 契约

命令：

```text
./scripts/check_path_topology_persistence.sh
```

结果：

```text
PASS: Path topology persistence contracts hold.
```

### Diff whitespace

命令：

```text
git diff --check
```

结果：

- Exit code 0。
- 无输出。

### SunSmart generic iPhoneOS build

命令：

```text
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

结果：

```text
BUILD SUCCEEDED
```

## 5. 未覆盖的外部验收

本次没有执行：

- 真机新增空 Sequence 后的真实服务器上传确认。
- 真实 Mesh 节点邻居表同步。
- 接近 300 台设备的主线程性能基准测试。

源码契约和 iPhoneOS 构建已经验证；服务器、硬件和大规模性能仍属于集成验收范围。

## 6. Git 状态

- 未执行 commit。
- 未执行 push、merge 或 PR 操作。
- 保留当前 worktree 内此前已有的所有未提交改动。
