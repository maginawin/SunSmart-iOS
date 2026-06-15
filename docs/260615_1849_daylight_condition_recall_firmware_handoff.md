# Daylight Condition Recall 固件沟通日志整理

## 背景

- 设备地址：`00B0`，十进制 `176`
- 设备信息：`cid=0A78`，`pid=2002`
- 场景：Group Profile 同步重试，失败点显示为 `配置文件切换`
- 失败命令：`daylightConditionRecall(index: 0)`
- 结论状态：设备有回复，Mesh 通讯和解密正常；失败来自设备业务状态码 `errorCode=2`

## 命令收发明细

| 步骤 | App 语义命令 | 发送方向 | 发送 Access PDU | 回复 Access PDU | 解码结果 |
| --- | --- | --- | --- | --- | --- |
| 1 | `daylightConditionRecallGet` | `0001 -> 00B0` | opcode `0xF1780A`, parameters `0x313F` | opcode `0xF3780A`, parameters `0x313F00FF` | 成功。`0x31/0x3F` 状态 `0x00`，当前 index `0xFF`，App 解码为 `-1` |
| 2 | `daylightLuxTriggerLock(delay: 600)` | `0001 -> 00B0` | opcode `0xF0780A`, parameters `0x313B5802` | opcode `0xF3780A`, parameters `0x313B00` | 成功。`0x0258` little-endian = `600` 秒 |
| 3 | `daylightConditionRecall(index: 0)` | `0001 -> 00B0` | opcode `0xF0780A`, parameters `0x313F00` | opcode `0xF3780A`, parameters `0x313F02` | 失败。`0x31/0x3F` 状态 `0x02`，设备返回错误码 2 |

## 原始命令摘录

### 1. 读取当前 daylight condition recall

- 发送：`SunricherVendorGet(daylightConditionRecallGet)`
- 解密后的发送命令：`opcode=0xF1780A, parameters=0x313F`
- 空口加密发送包：`0x0034E6D75DA4CDF8D55BD10C30462ABC53373E472C165523`
- 空口加密回复包：`0x0034C78FC4E2E76296415DBD4CC9AEB04F52CE3B09A680D1C9B2`
- 解密后的回复命令：`opcode=0xF3780A, parameters=0x313F00FF`
- App 解码：成功，当前 recall index 为 `-1`

### 2. 设置 daylight lux trigger lock

- 发送：`SunricherVendorSet(daylightLuxTriggerLock(delay: 600))`
- 解密后的发送命令：`opcode=0xF0780A, parameters=0x313B5802`
- 空口加密发送包：`0x0034A0E8A4B6D38AA8B90FBF93885183D08F2F80D345CE12F186`
- 空口加密回复包：`0x0034164B34D8179529A7C54ED367FDE0584CE034445E02378A`
- 解密后的回复命令：`opcode=0xF3780A, parameters=0x313B00`
- App 解码：成功

### 3. 切换 daylight condition recall

- 发送：`SunricherVendorSet(daylightConditionRecall(index: 0))`
- 解密后的发送命令：`opcode=0xF0780A, parameters=0x313F00`
- 空口加密发送包：`0x00343B170E06EED373D721C9AB40B05761C9AAC6CD181D9133`
- 空口加密回复包：`0x00346F005987C09F00975F4FC99C057D6DAA26F4C6739E4237`
- 解密后的回复命令：`opcode=0xF3780A, parameters=0x313F02`
- App 解码：失败，`errorCode=2`

## 需要固件确认的问题

1. `pid=2002` 是否支持 daylight condition recall：`0x31/0x3F`。
2. `0x313F02` 中的错误码 `0x02` 在固件侧具体表示什么：不支持、参数非法、condition 不存在、状态不允许，还是其他原因。
3. 当 `daylightConditionRecallGet` 返回 `0x313F00FF` 时，`0xFF` 是否表示当前没有已激活的 recall condition。
4. 对 `daylightConditionRecall(index: 0)`，固件要求 index `0` 预先具备哪些配置。
5. 如果 App 在 recall 前先发送 condition 写入命令，固件是否应接受后续 `0x313F00`：
   - 分段 condition 路径：`0x313C`、`0x313D`、`0x313E`
   - 非分段完整 condition 路径：`0x313A`

## App 侧判断

这条最新日志里，`0x313F00` 前只有：

1. `0x313F` 读取 recall 状态
2. `0x313B5802` 设置 lock
3. `0x313F00` 执行 recall

没有出现修复后新建同步任务时应有的 condition 写入命令，例如 `0x313C`、`0x313D`、`0x313E` 或 `0x313A`。

因此，这条日志不能证明新 App 修复逻辑已经实际执行。更可能是重试了旧同步步骤，或者运行的不是包含修复的新 App 包。

## 是否需要回退 App 修复

不建议回退。

已有 App 修复的目标是：新建同步任务时，在 `daylightConditionRecall(index: 0)` 前先补齐对应 daylight condition 配置，并让 retry 相关性包含 day/night lux threshold 任务。这个方向与当前日志暴露的问题一致，不会改变 vendor opcode 编码，也不会让其他设备走不同的 recall 协议。

下一步应使用包含修复的新 App 重新生成同步任务，而不是只点击旧失败步骤的 retry。期望看到 `0x313F00` 前出现 condition 写入命令。如果 condition 写入成功后 `0x313F00` 仍返回 `0x313F02`，则可以明确转固件侧处理。

## 追加核实：App 是否仍存在问题

当前源码的新建同步任务路径已经具备修复逻辑：

1. 对 day/night condition profile，会构造 `profileNightToggleTriggerConditionLux` 或 `profileDayToggleTriggerConditionLux`，并使用 `forceFullSet: true`。
2. 如果后续要执行 `daylightSensorConditionRecall`，会先追加 condition profile，再追加 recall。
3. retry 相关性检查已经包含 day/night condition profile，避免只重发 lock 和 recall。

因此，如果使用最新 App 重新生成同步任务，理论上 `0x313F00` 前应该能看到 condition 写入命令。

这条最新日志仍然只出现 `0x313F`、`0x313B5802`、`0x313F00`，没有 condition 写入。它更能说明本次操作没有跑到新建任务图中的修复逻辑，而不能单独证明当前源码修复无效。

判断标准：

- 如果只是点击旧失败步骤的 retry：仍可能复用旧任务图，这是 App 运行流程层面的旧状态问题，不代表当前源码修复错误。
- 如果退出同步页、用包含修复的新包重新进入 SAVE/同步后，仍然没有 `0x313C/0x313D/0x313E` 或 `0x313A`：App 仍存在任务生成路径遗漏，需要继续查 App。
- 如果重新生成后 condition 写入已出现且成功，但 `0x313F00` 仍返回 `0x313F02`：问题应转固件侧确认。

## 设备端日志补充

设备端关键日志：

```text
[00:01:15.961,171] <dbg> sr_srv: vnd_get: opcode:31
[00:01:16.141,187] <dbg> sr_srv: vnd_set: opcode:31 subcode:3b
[00:01:16.351,171] <dbg> sr_srv: vnd_set: opcode:31 subcode:3f
[00:01:16.351,198] <err> mod_amb: group:0000 or scene:0000 not found
```

这与 App 侧日志完全对应：

1. `vnd_get opcode:31` 对应 `daylightConditionRecallGet`，即 `0x313F`。
2. `vnd_set opcode:31 subcode:3b` 对应 `daylightLuxTriggerLock(delay: 600)`，即 `0x313B5802`。
3. `vnd_set opcode:31 subcode:3f` 对应 `daylightConditionRecall(index: 0)`，即 `0x313F00`。
4. 固件随后报 `group:0000 or scene:0000 not found`，这就是 App 收到 `0x313F02` 的直接原因。

因此，设备端不是没有收到 App 命令，也不是 Mesh 传输失败。固件处理 `daylightConditionRecall(index: 0)` 时，拿到的目标 group 或 scene 是 `0000`，然后查找失败并返回错误。

需要固件进一步确认：

1. `index=0` 的 daylight condition 当前为什么会解析出 `group=0000` 或 `scene=0000`。
2. 这是出厂默认值、flash 旧数据、condition 未写入、还是 PID 2002 对该功能不支持导致的默认空配置。
3. 当 condition 为空时，`daylightConditionRecallGet` 返回 `0xFF` 是否符合预期。
4. 如果 App 在 recall 前先写入 `0x313C/0x313D/0x313E` 或 `0x313A`，固件侧是否会把 group/scene 更新为 App 下发的目标地址和场景号。

结合 App 侧最新日志，因为 recall 前没有 condition 写入命令，所以当前这次失败的直接原因可以描述为：App 触发了 `index=0` recall，但设备端 `index=0` 对应的 condition 执行动作为空，固件查到 `group=0000` 或 `scene=0000` 后拒绝执行。

## App 容错边界

当前 App 对这种情况的容错是不完整的。

已有修复属于发送前预防：新建同步任务时，强制在 `daylightConditionRecall(index:)` 前先写入 condition，避免设备端拿到空的 `group=0000` 或 `scene=0000`。

但当前执行中的同步流程没有收到失败后的现场恢复逻辑：

1. App 收到 `daylightConditionRecallGet` 返回 `index=-1` 时，只是不记录当前 recall index；不会据此清空本地 condition 缓存，也不会强制补写 `index=0` 的 condition。
2. App 收到 `daylightConditionRecall(index: 0)` 返回 `errorCode=2` 时，会按失败处理；不会自动补发 `0x313C/0x313D/0x313E` 或 `0x313A` 后再重试 recall。
3. 旧失败步骤的 retry 主要复用已有任务图；如果旧任务图里没有 condition 写入任务，retry 无法凭空恢复出完整 condition 配置。

所以更准确的 App 侧结论是：

- 新建任务路径已经加了预防式容错，不建议回退。
- 对“设备端已有空 condition / 旧任务图只剩 recall / 固件返回 `0x313F02`”这种现场失败，App 仍缺少运行时恢复容错。

如果要继续增强 App，推荐方向不是忽略 `0x313F02`，而是在检测到 daylight recall 失败时，把对应 condition 视为无效并重新生成同步任务，确保先下发 condition 写入命令，再执行 recall。

## App 恢复策略实现

已为 App 增加运行时恢复策略：

1. 只在 `daylightConditionRecall(index:)` 收到 vendor status 失败，且 `errorCode=2` 时触发。
2. 先尝试从当前同步 step 的 day/night condition task 复用目标 condition。
3. 如果旧任务图没有 condition task，则从当前 group profile 的 night/day 配置按 index 推导 condition。
4. 恢复队列会先发送 condition 写入命令，再重发 `daylightConditionRecall(index:)`。
5. 同一轮同步对同一设备同一 index 只恢复一次，避免设备持续失败时无限循环；新一轮同步会重新允许恢复。

这层恢复不会吞掉失败。如果补写 condition 或 recall 重试仍失败，最终同步结果仍会显示失败。
