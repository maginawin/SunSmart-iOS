# EFC Editor 重启后设备偶发不见修复方案

## 背景

Editor 在 Space > Others 添加真实 EFC 并配置功能后，设备功能正常，但退出 App 后再打开，Others 中偶发看不到 EFC。后续未稳定复现。

前置分析判断：设备功能正常说明 mesh/vendor 配置已经写入真实控制器和灯端；UI 不见主要风险在 App 侧 `emergencyFireControllers` 本地展示数据被重启后的 Space 云端导入覆盖。

## 修复目标

- Editor 添加、绑定、配置、删除 EFC 后，Space payload 尽快上传，不再长时间停留在 slow sync 窗口。
- Space 云端导入时，不因为旧 payload、缺少 `emergencyFireControllers` 字段、或同时间戳 summary 未识别 EFC 差异而清空本地 EFC 展示数据。
- 如果远端 nodes 中仍存在真实 `emergencyController` 节点，即使 EFC 配置记录缺失，也应该在 Others 中恢复为可见且需要同步的 EFC，而不是静默消失。

## 不做范围

- 不改 EFC vendor 协议、SDK message、AppKey bind、model bind 逻辑。
- 不改 EFC 监控页 UI、功能按钮、底部弹窗。
- 不新增 Auth 信息，不改资源和 target 配置。
- 不做全局 cloud sync 重构。

## 方案对比

### 方案 A：推荐方案，源头 promptly sync + 导入防误清空

1. EFC 创建、保存、绑定真实设备、删除后，把 Space 变更按需要及时上传。
   - 当前 EFC 编辑保存走 `.common`，会进入 10 秒 slow sync。
   - 计划改为使用现有 `.device` 同步级别，触发 promptly sync。
   - 这样不新增同步枚举，改动面最小。

2. `SpaceImportSummary` 增加 EFC 摘要。
   - 当前只比较 device/group/scene/schedule/switches。
   - 增加 `emergencyFireControllerCount`，至少覆盖“本地 1 台、远端 0 台”的丢失场景。

3. Space 导入 EFC 时区分字段缺失和明确空数组。
   - 如果远端 payload 没有 `emergencyFireControllers` 字段，按旧 payload/不完整 payload 处理，不清空本地 EFC 表。
   - 如果字段存在且是空数组，才表示远端明确没有 EFC 配置。

4. 导入完成后用当前 Space 重新合并真实 EFC 节点。
   - 当前导入后调用的是 `loadDevices(meshUUID:meshNetworkId:)`，缺少 Space 上下文。
   - 计划改成基于当前 `space` 的合并入口，让真实 `emergencyController` 节点至少能恢复成可见的本地 EFC 记录，并标记为未同步。

优点：覆盖本次最可能的时序问题，改动集中，符合现有同步结构。  
风险：如果同一 Space 多端同时编辑，仍要依赖现有 active-user/Editor 机制避免冲突；本方案不引入复杂的 per-controller 冲突合并。

### 方案 B：新增 `.emergencyFire` 同步类型

新增 `SpaceChangeDataType.emergencyFire`，在 Space 层映射到 promptly sync，EFC 页面统一发这个类型。

优点：语义更清晰，未来 EFC 同步规则更容易独立调整。  
缺点：需要扩展同步枚举和所有 switch 处理点；当前收益不明显，改动面比方案 A 略大。

### 方案 C：只把 EFC 保存改为 promptly sync

只处理 slow sync 窗口，不改导入逻辑。

优点：改动最小。  
缺点：无法防止旧 payload 或字段缺失导致导入清空 EFC 表，不足以解释和修复本次偶发问题。

## 推荐方案

采用方案 A。

理由：这次问题不是单纯“上传慢”，而是“上传未完成 + 重启导入覆盖”的组合风险。方案 A 同时收紧源头上传和导入防线，且不改协议、不动 SDK、不重构 cloud sync。

## 预计修改点

- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift`
  - EFC create/save/delete/link 后的 `notifySpaceDataChanged` 从 slow 路径调整到 promptly 路径。

- `SunSmart/Common/Data/ImportData.swift`
  - `SpaceImportSummary` 增加 EFC 摘要。
  - 导入 `emergencyFireControllers` 前判断字段是否存在。
  - 字段缺失时不执行 `DeviceEmerFireData.deleteAll(...)`。
  - 导入结束后使用当前 Space 合并真实 EFC 节点。

- `scripts/check_efc_controller_flows.sh`
  - 增加轻量 contract，防止 EFC 保存重新回到 `.common` slow sync。
  - 增加导入逻辑 contract，防止缺失 `emergencyFireControllers` 字段时清空本地 EFC 表。

## 验证计划

1. 跑 EFC contract：
   - `bash scripts/check_efc_controller_flows.sh`

2. 跑 diff 检查：
   - `git diff --check`

3. 跑 iPhoneOS 构建：
   - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

4. 手工验证：
   - 以 Editor 进入共享 Space。
   - 在 Others 添加真实 EFC。
   - 配置 EFC 功能并保存。
   - 立即退出 App 后重开。
   - 期望 Others 中 EFC 仍可见；如同步未完成，应显示需要同步/修复状态，而不是消失。
   - 等待 cloud sync 完成后再次重启，EFC 仍可见，功能仍正常。

## 确认点

请确认是否采用方案 A。

如果确认，我会按这个范围实施；不扩展到 SDK 协议和其他 UI 改动。

