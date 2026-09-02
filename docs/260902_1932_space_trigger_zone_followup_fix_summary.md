# Space Trigger Zone 后续问题修复总结

## 1. 完成结论

本轮已按确认方案完成 App 与本地 NordicSigMeshSDK 源码修复，统一邻居上限采用 184。Group Path、Group Trigger Zone 与 Space Trigger Zone 继续通过同一拓扑 Planner 合并和去重，不互相覆盖，也没有删除 Group Trigger Zone 功能。

App 当前功能源码已通过全部共享品牌 target 的 iPhoneOS 构建。本地 SDK 的 iPhoneOS 构建也已通过。真实设备 Mesh 交互、页面视觉与固件 184 边界仍需设备验收。

---

## 2. 已完成修复

### 2.1 App 与 SDK 邻居上限统一为 184

- App 在统一拓扑完成 Sequence、Group Zone、Space Zone 合并和地址去重后，按每台设备检查最终邻居数。
- 184 个邻居允许保存与同步；185 个及以上会在保存或重新同步前提示，且不持久化该次编辑。
- Group Path 与 Space Trigger Zone 的保存、`Devices not synced` 重试都使用同一容量判断。
- SDK 的 Neighbor Set 增加 184 条业务上限，超过后通过发送失败通道返回，不进入可靠消息等待或分段队列。
- SDK Access Layer 增加通用报文容量保护：32-bit TransMIC 最大 380-byte Access PDU，64-bit TransMIC 最大 376-byte Access PDU。
- Neighbor Count 编码不再因超过 U8 转换范围触发运行时崩溃；超限内容不会被发送。

184 条 Neighbor Set 的 Access PDU 为 379 字节，需要 32 个 Lower Transport 分段；185 条为 381 字节，需要 33 段，因此被拒绝。

### 2.2 Device Restore 使用 Space 级统一地址迁移

- 移除 `Node.updateResoreData` 中仅处理当前 Group 的旧迁移逻辑。
- 新迁移入口扫描当前 Space/Subnetwork 下所有 Group Path、Group Trigger Zone 和 Space Trigger Zone。
- 同一结构中旧地址出现多次时会全部替换。
- 有实际变化时只执行一次 write-ahead Cloud Dirty 标记，再保存受影响 Group/Space；每个受影响 Group 更新同步状态。
- 无选中恢复 Group 时，只要能解析 Space，也会执行引用迁移。

### 2.3 Space Trigger Zone 增加未同步状态与重试

- 页面导航栏新增与 Path Sequence 一致的 `Devices not synced` 状态入口。
- 页面出现时针对 Space 内所有合格 Proximity Lighting 设备重新编译统一拓扑并比较设备状态。
- 点击后重新检查 184 上限，并将全部有差异设备送入 Space Trigger Zone Re-sync 流程。
- 重试成功返回页面后重新计算；仍有差异时入口继续显示。

### 2.4 跨 Group Space Zone Test

- Zone 有 Item 即可启用 Test，不再要求所有 Item 的 Group Address 相同。
- Test 输入改为去重、排序后的 Group Address 列表。
- 首次 Start 时先依次向所有相关 Group 发送 Off，再保持原流程逐台发送 On。
- Group Path 与 Group Trigger Zone 继续通过单 Group 兼容入口调用，原交互保持不变。

### 2.5 Neighbor Set 成功条件补充 Enabled

普通设备同步与 Emergency 同步两份成功判断均改为同时校验：

- Enabled 为 true；
- Relay Number 一致；
- Neighbor Addresses 排序后一致。

### 2.6 32 个 Path/Zone 提示本地化

Sequence、Group Trigger Zone、Space Trigger Zone 三个达到 32 上限的入口都改为读取本地化 value，不再直接显示 key。

新增 184 邻居容量提示已同步 English 与简体中文。

---

## 3. 验证结果

### 3.1 聚焦回归

`scripts/check_path_topology_persistence.sh` 通过：

- Path topology persistence contracts；
- Proximity Lighting topology policy tests；
- Space Trigger Zone follow-up contracts。

覆盖 183/184 允许、185 合并后拒绝、255 字段上限仍拒绝、重复边去重、保存前容量拦截、三类 Restore 引用、无 Group Restore、Space Re-sync、跨 Group Test、Enabled 成功判断与本地化调用。

### 3.2 本地化与差异检查

- English、简体中文 `Localizable.strings` 均通过 `plutil -lint`。
- App 与 SDK 均通过 `git diff --check`。

### 3.3 iPhoneOS 构建

以下 App scheme 均使用 Generic iOS Device、关闭签名构建成功：

- SunSmart；
- Archipelago；
- Lumineux；
- SylSmart；
- SLG Sync Plus。

本地 NordicSigMeshSDK 的 `NordicSigMeshSDK` scheme 同样通过 Generic iOS Device 构建。SDK 184/185 XCTest 源码已使用 iPhoneOS SDK 完成 typecheck。

---

## 4. 尚未由自动验证覆盖的边界

### 4.1 App 尚未切换到本地 SDK 修改

App workspace 当前仍解析远端 `NordicSigMeshSDK release @ 86f5ec9`。因此 App 五个 target 的成功构建验证了 App 改动和现有远端 SDK 的兼容性；SDK 新增的发送层保护是在本地 SDK 工作树单独构建验证的。

要把 SDK 防御真正带入 App 发布物，还需要后续提交并发布 SDK revision，再更新 App 的 Swift Package 解析版本。本轮未执行 commit、push 或依赖 revision 更新。

### 4.2 设备与 UI 验收

仍需真实 iPhone 与固件设备完成：

- 183、184、185 邻居边界发送与固件返回；
- 多 Group Off 的实际 Mesh 排队顺序及逐设备 On；
- Restore 后云端上传与重载后的三类引用一致性；
- `Devices not synced` 在各字号、横竖屏和品牌资源下的实际布局与点击；
- 同时存在 Group Path、Group Trigger Zone、Space Trigger Zone 时的真实 PIR 传播行为。

自动化通过不等同于固件接收成功或真实灯具行为完成。
