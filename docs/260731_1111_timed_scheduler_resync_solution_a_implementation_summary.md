# Timed Scheduler 重复同步方案 A 实施总结

## 结论

方案 A 已完成代码实现和自动化/构建验证。

本问题的直接原因不是 `TimeSet` 本身，也不是 16 个 Scene 或 16 个 Scheduler 的容量边界，而是 SDK 的 Scheduler Model 缓存持久化格式不兼容：

- 保存时，`elementAddress` 被 JSON 编码为数字；
- 恢复时，旧实现只按十六进制字符串解码；
- 解码又被 `try?` 静默吞掉，导致退出 Space 后恢复出的 `allSchedulerModelEntrys` 为空；
- App 在 2026-07-27 的 Timed 修复中改为严格依赖每个 Scheduler Model 的真实状态，因此重进页面后把所有 Scheduler 重新判断为“需要同步”。

因此，之前的 Timed 严格判定修复是问题的暴露条件，但不是持久化数据丢失的根因。`TimeSet` 触发通用 `savePropertys()` 时还可能把无法恢复的原始值覆盖成空数组，使现象更稳定地复现。

## 已实施内容

### 1. 兼容历史数据并统一新格式

- SDK 同时兼容历史 JSON 数字地址和十六进制字符串地址。
- 十六进制字符串大小写均可读取。
- 新数据统一把 Element Address 编码成四位大写十六进制字符串。
- 地址必须是有效单播地址；非法字符串、错误 JSON 类型和越界地址会明确失败。
- 多 Scheduler Model 容器及“已知空 Model”状态可完整往返保存。

### 2. 防止损坏数据被无关保存覆盖

- 移除恢复路径中的静默 `try?`。
- 解码失败时记录原因并暂存原始 blob。
- 在尚未取得权威 Scheduler Model 数据时，`TimeStatus` 等无关保存继续保留原始 blob，不再写成空数组。
- 当 Scheduler Register/Action 已真正建立 per-Model 状态后，才用规范格式替换旧数据。

### 3. 收紧权威读取完成语义

- 完整读取仍会遍历节点的全部 Scheduler Model。
- Scheduler Register 为空也会建立“已知空 Model”状态。
- 完成结果同时覆盖 Register Get 和根据 Register 动态追加的 Action Get。
- 同一节点任一 Register、有效 Action 或预期结果缺失时，该节点本次读取失败。
- 完整读取失败时移除本次不完整的 per-Model 状态，使节点保持“未知、可重试”，并恢复读取前的 legacy 扁平投影，避免部分响应污染 UI。

### 4. Timed 页面一次性修复未知缓存

- Timed 页面出现且 Mesh 已连接时，只选择缺少任一 Scheduler Model 状态的真实节点。
- 不处理 Dongle collection Scheduler。
- 当前页面实例不会并发启动重复修复。
- 如果全局 Mesh 命令正忙，会等待后重试，不覆盖现有命令回调。
- 修复只执行 Scheduler Register/Action 读取，不写 Scheduler。
- 读取成功后刷新同步标记；全部 Model 已知的节点下次进入 Timed 不再重复读取。
- 读取失败的节点保持未知，下次进入页面可重试。

### 5. 保持严格同步判定并增强诊断

`needsSync` 仍以 per-Model 真值为准，不回退到可能掩盖跨 Model 残留的 legacy 扁平缓存。DEBUG 日志可区分：

- Owner Model 未知；
- Owner index 缺失；
- Owner entry 内容不一致；
- cleanup Model 未知；
- cleanup Model 仍有残留；
- 已同步；
- 非目标或节点不支持 Scheduler。

逐 Model 日志还会输出 Element Address、Model 状态、已有 index 和持久化解码错误。

## 自动化验证

### TDD

实施过程覆盖以下 RED → GREEN：

- 历史数字地址和新十六进制地址 codec；
- 规范编码、多 Model 往返和已知空 Model；
- 损坏 blob 保护；
- Register 与动态 Action Get 的完成结果汇总；
- 部分读取失败后的未知状态回滚；
- legacy 扁平投影回滚；
- Timed 未知缓存修复条件；
- 严格 per-Model 同步差异判定；
- App 与 SDK 源码接线契约。

### 聚焦测试

- `scripts/check_timed_scheduler_persistence.sh`
  - `SchedulerModelCachePersistenceTests passed`
  - `SchedulerModelReadCompletionTests passed`
- `scripts/check_timed_scheduler_single_owner.sh`
  - `TimedSchedulerOwnerPolicyTests passed`
  - `TimedSchedulerSingleOwnerContractTests passed`

### 静态检查

- App 仓库 `git diff --check`：通过。
- SDK 仓库 `git diff --check`：通过。
- 未发现无关业务文件被修改。

### iPhoneOS 构建

以下四个品牌 scheme 均使用 generic iPhoneOS、Debug、`CODE_SIGNING_ALLOWED=NO` 直接构建，并得到 `** BUILD SUCCEEDED **`：

1. `SunSmart`
2. `Archipelago`
3. `SLG Sync Plus`
4. `SylSmart`

构建仍包含工程既有的资源重复、弃用 API 和未使用值等 warning；没有观察到由本次改动新增的编译错误或明确归因于本次改动的新 warning。

## 真机验收边界

自动化与 generic iPhoneOS 构建不能替代真实 Mesh、真实节点以及退出/重进 Space 的生命周期验证，所以目前不能宣称真机闭环已经通过。

建议使用保留旧数据库的安装方式测试，不要先删除 App，这样才能覆盖历史坏数据迁移：

1. 进入 Space，再进入 Timed。
2. 等待 `[SchedulerModelCacheRepair] finished`；首次修复可能读取多个节点、多个 Model 及其有效 Action，耗时取决于 Mesh 规模。
3. 确认同步标记消失。
4. 退出 Timed 后再次进入。
5. 退出 Space 后再次进入 Space 和 Timed。
6. 强制结束 App，再启动并进入同一 Space/Timed。
7. 再次 SAVE 同一个 Scheduler，确认不再出现无原因的 cleanup/owner 重写。

需要覆盖：

- Target：Device、Group、Scene；
- Action：Auto/On、Off、Scene Recall；
- Profile：
  - proximity/predictive lighting with photocell；
  - daylight harvesting (closed loop)；
  - Manual control；
  - 无 Profile 或其他普通照明 Profile；
- 16 个 Scene、16 个 Scheduler 容量边界。

## 建议收集的日志

如仍复现，请提供从“进入 Space”到“重进 Timed”的连续完整日志，重点保留：

- `[SchedulerModelCache] decode failed`
- `[SchedulerModelCacheRepair] start`
- `[SchedulerModelCacheRepair] action read failed`
- `[SchedulerModelCacheRepair] finished`
- `[node-scheduler-model]`
- `[schedule-sync]`
- Scheduler Get / Status
- Scheduler Action Get / Status
- Scheduler Action Set / Status
- Time Get / Set / Status

同时注明：

- App 是否覆盖安装并保留旧数据库；
- 出问题 Scheduler 的 index、Target 类型、Action、Profile；
- Target 中每个真实 Node 的 primary address；
- 日志中 `reason=` 的具体值；
- 修复读取是否完成、失败节点有哪些。

## Git 状态

- App 工作树分支：`fix`
- SDK 分支：`dev`
- 未执行 commit、merge 或 push。
- 所有改动保留在当前两个本地工作树中。
