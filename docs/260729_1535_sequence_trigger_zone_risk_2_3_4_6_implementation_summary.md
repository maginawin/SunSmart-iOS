# Sequence / Trigger Zone 风险 2、3、4、6 修复实施总结

## 1. 完成范围

本次按确认的方案 B 完成以下修复：

- Risk 2：Group Sequence / Trigger Zone 保存前先持久化 Space 云端待上传状态。
- Risk 3：Space Trigger Zone 为空时仍显式导出 `triggerZones: []`；导入继续兼容空数组和字段缺失。
- Risk 4：存在设备同步任务时，只由通用同步页发送 `.device` 云同步通知。
- Risk 6：永久清理不再符合当前 Group、Node、Space 和 Profile 条件的 Trigger Zone 成员，同时保留空 Zone。

## 2. 主要实现

### 2.1 写前云同步标记

`SpaceData` 新增 `markLocalChangePendingCloudSync()`：

- 刷新 Space 汇总数量。
- Owner / Editor 使用现有单调时间规则标记待上传。
- Visitor 只保存汇总数量。
- 只持久化状态，不创建云同步 Handle。

现有 `commitLocalChangeForCloudSync(...)` 复用该方法。

Group Path 页面现在接收所属 `SpaceData`，并在 `group.info.save()` 前执行写前标记。

Space Trigger Zone 也在保存清理后的逻辑数据前执行写前标记。

### 2.2 空数组导出和兼容导入

`SpaceData.export()` 移除了 `triggerZones` 非空门禁：

- 非空数组正常导出。
- 空数组编码并导出为 `[]`。
- 编码失败仍不写入字段。

`ImportData.swift` 没有修改。当前逻辑已经满足：

- `triggerZones: []` 解码为本地空数组。
- 缺少 `triggerZones` 时进入兜底并赋值空数组。

### 2.3 通知去重

Space Trigger Zone 的设备同步成功回调不再额外发送 `.common`：

- 无设备任务：页面发送一次 `.common`。
- 有设备任务成功或失败：通用同步页发送一次 `.device`。

成功提示和页面返回行为保持不变。

### 2.4 永久清理失效成员

Space Trigger Zone 使用以下成员键判断有效性：

```text
groupAddress + normalized deviceAddress
```

有效集合只来自：

- 当前 Space/Mesh Network 的 Group。
- Profile 为 `proximityLighting` 或 `proximityLightingWithPhotocell`。
- 当前仍属于该 Group 的 Node。

清理发生在：

1. 页面初始化工作副本时。
2. 点击 Save、比较新旧数据前。
3. 编译目标邻居时再次防御性过滤。

只删除失效 Item，不删除清空后的 Zone。

目标邻居为空时继续使用既有 Proximity Lighting Disable，不新增空 Neighbor Set 双命令。

## 3. 新增验证

- `Tests/Group/PathTopologyPersistenceContractTests.swift`
- `scripts/check_path_topology_persistence.sh`

TDD 过程分别观察到以下预期 RED：

1. 缺少写前云脏标记。
2. 空 Trigger Zone 被导出门禁省略。
3. Space Trigger Zone 保存存在两次通知。
4. 缺少唯一成员键和永久清理逻辑。

每项最小实现后均重新执行并转为 GREEN。

## 4. 已完成验证

### 4.1 自动化契约

- `./scripts/check_path_topology_persistence.sh`
  - PASS
- `GroupPathSequenceDeviceAddViewContractTests`
  - PASS
- `./scripts/check_space_delete_cloud_restore.sh`
  - PASS
- `git diff --check`
  - PASS
- `ImportData.swift`
  - 无生产改动

### 4.2 generic iPhoneOS 构建

以下 Debug、`CODE_SIGNING_ALLOWED=NO` 构建均成功：

- SunSmart
- Archipelago
- SylSmart

`SLG Sync Plus` 当前没有共享 workspace scheme，本次未执行该 scheme 构建。

## 5. 待真机和真实服务器验证

以下项目不能由源码契约和编译替代：

1. Group 保存后立即终止 App，重新进入后仍能识别待上传并完成云同步。
2. 删除全部 Space Trigger Zones 后，服务器请求包含 `"triggerZones": []`。
3. 分别导入空数组和缺少 `triggerZones` 的服务器数据，本地都得到空数组。
4. 有设备任务的 Space Trigger Zone 保存只产生一次云同步入队。
5. Profile 失效成员从 UI、本地和服务器数据中消失。
6. 其他有效节点收到的 `0xF0780A / 0x41 / 0x02` Payload 不包含失效地址。
7. 清理最后一个邻居时，节点收到既有 `0x41 / 0x01` Disable。

设备命令成功、服务器同步成功和整条业务链成功应分别记录。

## 6. Git 状态

本次未执行 Git 提交、合并、推送或 PR 操作。

用户原有未跟踪分析文档保持不变：

```text
docs/260728_2000_path_sequence_and_trigger_zone_protocol_analysis.md
```
