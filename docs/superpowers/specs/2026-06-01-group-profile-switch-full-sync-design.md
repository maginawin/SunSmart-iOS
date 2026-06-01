# Group Profile Switch Full Sync Design

## 背景

当前 Group Profile SAVE 流程是先保存本地 group/profile 数据，再根据每个节点当前缓存状态生成差量同步命令。该机制适合普通 Profile 属性更新，也适合添加设备到 group members 时减少重复命令。

问题发生在 group 从 Profile A 切换到 Profile B 时。部分设备或功能在差量化下发时会保留旧 Profile 状态，导致实际功能与新 Profile 不一致。因此类型切换场景需要对新 Profile B 的相关配置做全量下发。

## 目标

- 若 group 不切换 Profile 类型，保持现有差量下发逻辑。
- 若添加设备到 group members，保持现有下发流程逻辑。
- 若 group 从 Profile A 切换到 Profile B，对所有 group members 下发 Profile B 相关全量命令。
- 保留现有清理命令与顺序，不新增专门清理 Profile A 的命令流程。
- 保持现有同步 UI、失败判定、重试、PIR protection 行为。

## 非目标

- 不改变 group membership、scene、schedule、switch、proximity path 的同步域逻辑。
- 不新增 Mesh/Vendor 命令类型。
- 不重构 `SyncDevicesViewController` 的任务调度模型。
- 不修改 Profile UI 文案或交互。
- 不处理 `user-temp/`。

## 推荐方案

采用显式 Profile 同步上下文。

`ProfileSettingsViewController` 在保存 group profile 时比较旧类型与新类型：

- `selectProfile.type == group.info.profile.type`：普通保存，不强制全量。
- `selectProfile.type != group.info.profile.type`：Profile 类型切换，创建同步上下文并传入 `SyncDevicesViewController`。

同步上下文表达业务语义，例如：

- previous profile type
- saved profile type
- should force full profile sync

`SyncDevicesViewController` 在 group 同步时把该上下文传给 `Node.getSyncData(type:)` / `Node.getNodeSyncProfiles(...)`。`Node` 层只根据上下文决定是否对 Profile B 配置跳过差量判断。

## 命令生成规则

类型未切换时：

- 继续使用当前差量判断。
- 当前 Profile SAVE、添加成员、失败重试、手动 resync 等行为保持现状。

类型切换时：

- sensor publication enable/disable 继续按现有判断生成，不强制重复下发已正确的 publication。
- daylight calibration restore 相关命令仍只在当前存在 restore data 且 daylight enabled 时生成。
- 现有清理命令继续按当前规则生成，例如 `lightControlDelete`、`profileToggleTriggerConditionLuxDelete`。
- 新 Profile B 的核心 Profile 配置命令改为全量生成，不再依赖节点当前缓存值差量过滤。
- capability/model 判断继续保留，节点不支持的 model 不生成命令。

全量 Profile B 相关命令范围：

- Light LC mode / occupancy mode
- manual override timeout
- manual control enabled
- light auto adjust enabled
- high/low end trim
- occupancy/vacant/standby level 或 lux
- T1-T5
- daylight adjust speed
- power-up state
- sensitivity

proximity/path 相关仍保持现有独立同步链路，不混入 Profile 全量逻辑。

## 执行顺序

保持当前 `SyncDevicesViewController` 的 profile step 机制。

如果节点需要 add to group，仍先 add to group，再执行 profile 同步。

profile 内部保持当前生成与依赖顺序：

1. sensor publication enable/disable
2. daylight calibration restore
3. high/low end trim
4. 现有清理项：`lightControlDelete`、`profileToggleTriggerConditionLuxDelete`
5. 新 Profile scene switch / recall
6. 新 Profile 属性设置
7. scene store
8. power-up
9. sensitivity

`profileToggleTriggerConditionLuxLock/UnLock`、scene switch、store 的前置依赖继续沿用当前逻辑。

## 清理策略

采用已确认的策略 2：

- 不新增 Profile A 专门清理命令。
- 保留现有清理项。
- 现有清理项继续优先于新 Profile scene 配置命令下发。

这样可以避免额外 reset 命令扩大设备行为变化，同时保证当前代码已经处理的旧 scene 与旧 lux trigger condition 仍会被清理。

## 错误处理

- 单条命令继续使用当前 `ProfileType.isSuccessful(node:)` 判定。
- 同步失败后的 retry 继续复用现有 task/relevance task 逻辑。
- 同步中断时 PIR protection fallback 继续按当前逻辑工作。
- 全量下发会增加命令数量，但失败 UI 与重试粒度保持 task 级。
- 不新增回滚流程。

## 测试与验证

实现后需要验证：

- 同类型 Profile 属性更新仍生成差量命令。
- 添加设备到 group members 仍保持当前流程。
- Profile A 切换到 Profile B 时，所有 group members 都生成 Profile B 的全量核心配置命令。
- 现有清理命令仍在新 Profile scene 配置前。
- 不支持对应 model/capability 的节点不会生成不适用命令。

构建验证使用：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险

- 类型切换时命令数量增加，同步耗时会增加。
- 因保留现有清理策略，不新增 Profile A reset，某些旧属性如果当前代码没有覆盖或清理，仍可能残留。该风险由 Profile B 全量核心配置覆盖来降低。
- 若部分命令的成功判断依赖节点回包缓存，重复全量下发后仍可能受设备回包质量影响。
