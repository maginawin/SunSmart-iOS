# 进入 Space 后重复出现定时同步任务

## 结论与证据边界

已修复 v3 Space 云端导入重建 Node 时丢失本机 Scheduler 观察缓存的问题。它会让成功同步的任务在重进后再次被判为待同步，与两份现场日志一致。离线行为回归及 SunSmart generic iOS Debug 构建通过；尚未执行真机重进或实际服务端往返。

现场日志仅包含点击同步后的报文，没有完整的 Space 导入过程或导入前后数据库快照。因此，重复下发及前次成功由日志直接证明，缓存丢失触发链由当前源码和行为复现证明；最终现场归因仍以修复版重进验收为准。

## 现场日志

来源：`/Users/maginawin/Desktop/enter 1.txt`、`/Users/maginawin/Desktop/enter 2.txt`。

| 观察 | 第一次 | 第二次 |
| --- | --- | --- |
| 同一目标 | node 0010、schedule 0、slot 0 | 相同 |
| 清除另一 Model | 向 Element 0012 发送 `SchedulerActionSet`，payload `40060080791EF03F0000` | 相同 |
| 写入 Owner | 向 Element 0010 发送 `SchedulerActionSet`，payload `40FE7F80008000660000` | 相同 |
| 回执 | 两条对应的 `SchedulerActionStatus` 均返回 | 相同 |
| App 完成状态 | 第 108–109 行：accepted=2，binding=synced，0010:[0]、0012:[] | 第 77–78 行：相同完成状态 |
| 云端上传 | HTTP/businessCode 200 | HTTP/businessCode 200 |

重复的配置是周三 08:00 关闭，渐变 38 秒。两次配置数据相同，不能解释为用户修改了任务。前置单播 TimeSet 随重复定时任务一起执行；第一次日志后面的 FFFF 广播 TimeSet/TimeZoneSet 是另一条校时路径，本次没有取消它。

HTTP 成功只代表上传得到成功响应，不能证明下次导入保留了本机设备观察缓存。

## 触发链

1. `Schedule.applySchedulerResults` 接受两条成功回执，写回各 Model、调用 `node.savePropertys()`，随后将 binding 保存为 synced。日志显示该阶段完成。
2. Space 入口加载和云端校对经过 `SpaceData.update`。其应用条件包含远端时间戳等于本地，不要求业务内容实际变化。
3. v3 经现有规范化会移除云端 Scheduler 观察数据；共享数据描述的是期望配置，本机观察缓存仍是本地状态。
4. 原导入实现 `forceRemove` 旧 Node，删除旧属性行，再从云端字典构造新 Node。`restoreSchedulerModelSnapshot` 在无远端快照时直接成功返回，没有将旧 Node 的本地观察迁移到新 Model。
5. 新 Node 的 Model 状态变为 unknown；`schedulerSyncDifference` 和 `getMessageHandles` 因此重新安排清除另一 Model、写入 Owner。binding=synced 本身不能代替设备观察。

## 修复范围

- `ImportData.swift`：在移除旧 Node 前保留当前 Mesh、当前 Space 的旧节点；仅 v3 导入向恢复入口传入同 UUID 的本地节点。
- `ExportData.swift` 的现有 Scheduler snapshot adapter：没有远端快照时，检查 UUID、主单播地址、非空且相同的 Device Key、Scheduler Model 地址集合，以及本地缓存解码完整性；通过后按 Element 地址映射到新 Model 对象。
- 已知空字典保留为空；缺失 Model 保持未知；失败/取消产生的未知状态不会被升级成成功。
- 不一致身份、拓扑改变或损坏缓存不继承。真实新配置仍与保留的物理观察比较，产生必要任务；不会仅凭 synced 跳过。
- 原 v1/v2 快照恢复及校验保持原流程；未修改 SDK、固件或服务器。
- **无数据库或 export JSON 结构变更**：表、字段、Key、类型、默认值和字段语义均不变，无迁移或回填要求。测试中的 fixture_node_properties 仅存在于临时测试 SQLite，不是 App schema。
- 已丢失的观察可能还需一次设备读取或同步恢复；修复防止随后同身份重进再次丢失。

两处代码由 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 及工程内 HSmart 共用。没有品牌条件分支、资源、依赖或 SDK API 改动，本轮使用 SunSmart 代表构建。

## 验证

- 先复现：新增 v3 Node 替换回归在旧逻辑下失败，断言为 “Space re-entry must retain acknowledged owner and known-empty cleanup Model”。
- `python3 scripts/check_scheduler_cloud_roundtrip.py`：通过。覆盖 v3 新 Node 接收本地观察、实际 SDK property 编解码后重载、已知空/部分未知、UUID/地址/Key/拓扑改变、损坏缓存；原 70 节点 / 140 Model 往返也通过。
- `CLANG_MODULE_CACHE_PATH=/tmp/sunsmart-scene-module-cache SWIFT_MODULECACHE_PATH=/tmp/sunsmart-scene-module-cache python3 scripts/check_timed_slot_persistence.py --scheduler-lifecycle`：通过。使用现场两条 payload，贯通 SDK 解码和观察、Proxy 收尾、App 回写和 binding、实际 Schedule SQLite、SDK property 编解码和测试 SQLite、Node 替换与任务生成。连续三次重进产生零条重复消息；修改分钟后只发送 Owner 更新。正常、迟到旧回执、部分成功、Node/Schedule 保存失败、取消、替换、重新加入均通过。
- `python3 scripts/check_space_entry_sync.py`：通过入口权限及会话回归。
- `python3 scripts/check_timed_task_replacement.py`：通过 TimeSet 取消/替换、批量回执、任务归属及失败重试回归。
- `git diff --check`：通过。
- 构建：`xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-schedule-sync CODE_SIGNING_ALLOWED=NO build`，结果 BUILD SUCCEEDED。

测试边界：BLE、队列准入、Node/Model 对象及属性表外围使用夹具；属性 bytes 经过实际 SDK 序列化和 SQLite 往返。未执行完整 UIKit/HTTP Space 导入事务、真实 Mesh 或服务端集成，离线结果不替代真机验收。最初 SQLite 编译缓存因沙箱路径不可写而失败，改用可写的独立 module cache 后通过，未清理共享缓存。

## 最短人工验收

1. 使用本分支修复版，在原 Space 完成一次同步，确认定时任务成功。
2. 返回 Site，再进入同一 Space，连续三次；同一 slot 的清除/写入任务不应重新出现。杀掉 App 重启再进入一次，结果相同。
3. 修改该定时的分钟并同步，确认仍会同步新配置；已清空且未变化的另一 Model 不应重复清除。
4. 补充中断/断网后重试，以及连续添加/移除定时目标后的退出重进：未完成项应保留，可重试，已成功且未变化项不重复。
5. 若仍复现，保留从返回 Site 前到重新进入后的完整日志，含网络加载、SpaceImport/CloudSync、ScheduleSend、ScheduleResult，以定位导入及重载边界；不要导出凭据或密钥。

## 交接状态

- 工作树：`feat-device-scene-261028`；分支：`feat/device-scene-261028`；基础 HEAD：`d2c44cf4`。
- 开始时工作树干净；当前仅本任务两处 App 文件、两组测试、一个测试拼接脚本及本文档有未提交差异。未 commit/push。
- SDK：`.local-sdk/nordic-sig-mesh-sdk` 实际指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `165d916`，本轮未修改，开始时干净。没有新增 SDK 发布依赖。
- 下一步：用户按上述步骤完成真实设备与云端重进验收。
