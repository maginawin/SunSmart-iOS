# EFC Group Action Config 实施计划

> 本计划按已确认的方案 A 执行：保留 App 现有 EFC Scene Recall 接收机制，移除灯端 Store Scene 设计，将受控灯订阅和 `0x4D` 动作配置切到 EFC Group 模型。

## 目标

- EFC 添加到 Space 后立即拥有独立 EFC Group，即使没有 Associate with group(s)，App 也能把该 EFC Group 加入 proxy filter。
- 保留当前 App 通过 proxy filter + 全局 message dispatch + Scene ID 解析 EFC 状态的方式。
- Associate with group(s) 改为订阅灯端业务控制模型：
  - Light Lightness Server 始终订阅 EFC Group。
  - Light LC Server 仅在 Event Ends 为 Restore AUTO 时订阅 EFC Group。
- 移除 `LightLightnessSet + SceneStore` 旧任务。
- 修正 EFC 动作配置和 resend 参数，使日志与协议建议一致。

## 关键判断

当前 App 能接收并解析 EFC Recall Scene 的方式是：

1. EFC 本地记录持有 `publishGroupAddress`。
2. 进入 Space 后 `EmergencyFireControllerSceneEventManager` 将所有 EFC Group 加入 proxy filter。
3. 各页面收到 Mesh message 后调用 `EmergencyFireControllerSceneEventManager.dispatch(...)`。
4. Manager 只处理 `SceneRecall` / `SceneRecallUnacknowledged`，并用 `destination == publishGroupAddress`、`source` 属于 EFC 节点/元素地址来匹配。
5. Scene ID `0xFF20 / 0xFF21 / 0xFF22` 分别映射 Power Loss / Fire Alarm / Restored。

因此本轮保留 EFC 的 Scene Recall 状态事件链路；只把 EFC Group 创建时机前移，避免没有 associate group 时缺少 proxy filter 地址。

## 修改任务

### 1. EFC Group 生命周期前移

涉及文件：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
- `SunSmart/Common/Data/ImportData.swift`

执行内容：

- 在 `DeviceEmerFireStore.ensureDevice(...)`、`bind(...)`、`restoreDevice(...)` 保存 EFC 后，调用统一 helper 确保 `publishGroupAddress` 存在。
- helper 复用现有 `DeviceEmerFireData.ensurePublishGroup(meshUUID:subnetworkId:)`，已有地址则不创建。
- 创建或复用后刷新 `EmergencyFireControllerSceneEventManager.refreshProxyFilterAddresses()`。
- import 已带 `publishGroupAddress` 时继续复用；缺失时先不在导入解析中强行创建，避免 import 阶段 mesh context 不完整。缺失记录在首次 load / bind / edit sync 时补齐。

验证点：

- 新增 EFC 后本地记录有 `publishGroupAddress`。
- 没有 Associate Group 时 proxy filter 仍能包含 EFC Group。

### 2. 保留 EFC Scene Recall 接收机制

涉及文件：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSceneEventManager.swift`
- `SunSmart/Main/Space/Controller/SpaceViewController.swift`

执行内容：

- 不改 `dispatch` 的 Scene ID 解析、source/destination 匹配、通知发出逻辑。
- 保留 EFC Group 加入 proxy filter 的逻辑。
- 调整 manual-control block 的关联判断，后续以 Light Lightness / Light LC 订阅为准，同时兼容历史 Scene Server 订阅。

验证点：

- `SceneRecallUnacknowledged(0xFF20/0xFF21/0xFF22)` 到 EFC Group 仍能触发状态更新。
- 没有 associate group 不影响 App 监听 EFC Group。

### 3. 重写 Associate with group(s) 同步任务

涉及文件：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmergencyFireControllerSyncVC.swift`

执行内容：

- 删除或停用灯端 `Scene Server` subscription 任务。
- 删除或停用 `LightLightnessSet + SceneStore(0xFF20/0xFF21)` 任务。
- 新增灯端 `Light Lightness Server` subscription 任务。
- `Light LC Server` subscription 改为仅 Restore AUTO 时生成。
- 删除 Group 时解除 Light Lightness subscription。
- 删除 Group 或从 Restore AUTO 切换到 Set Brightness / None 时，解除 Light LC subscription。
- 对历史版本已写入的 Scene Server subscription 做兼容清理：如果发现 Scene Server 仍订阅 EFC Group，生成 delete 任务。
- 更新 sync item 名称，避免 UI 仍显示 Store Scene 或 Scene subscription。

验证点：

- SAVE 添加 Group 时不再出现 `SceneStore(...)`。
- Set Brightness / None 下只订阅 Light Lightness Server。
- Restore AUTO 下订阅 Light Lightness Server + Light LC Server。
- 删除 Group 能解除 Light Lightness / Light LC，并清理历史 Scene Server 订阅。

### 4. 修正 EFC 控制器侧动作配置

涉及文件：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditState.swift`

执行内容：

- `0x4D/0x07` 三类 action config 的 `ttl` 固定为 `0xFF`。
- `stage1_target` / `stage2_target` 继续使用 EFC Group。
- None action 继续使用 `.invalid`，但 target/appKey/ttl 仍按 EFC Group 当前配置下发。
- `0x4D/0x03` 的 emergency/fire sync resend 参数中，`M` 固定为 `0xFFFF`。
- Restore send count 保持 `state_idx=0x02, N=5, M=UI send count`。
- `Resuming in` 保持现有 `0x4D/0x06`、范围 `0...120`。
- 保留 EFC Scene Client publication 到 EFC Group，用于 EFC 状态 Scene Recall；移除不再需要的 EFC Light LC Client publication，除非代码验证显示固件仍依赖它。

验证点：

- 日志中 Fire action config 为 `state_idx=0x01 action_type=0x06 ttl=0xFF`。
- Power Loss action config 为 `state_idx=0x00 action_type=0x06 ttl=0xFF`。
- Event Ends Set Brightness 为 `state_idx=0x02 action_type=0x06 ttl=0xFF`。
- Event Ends Restore AUTO 为 `state_idx=0x02 action_type=0x05 params=0x01 ttl=0xFF`。
- Event Ends None 为 `state_idx=0x02 action_type=0xFF params empty ttl=0xFF`。
- Trigger resend 的 `M` 为 `0xFFFF`。

### 5. 同步状态与脏数据兼容

涉及文件：

- `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/LinkedEmerFireEditViewModel.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift`
- `SunSmart/Common/Data/ImportData.swift`
- `SunSmart/Common/Data/ExportData.swift`

执行内容：

- 保存配置时确保 derived resend count 不被旧数据污染。
- export/import 保持 `publishGroupAddress` 字段，不新增云端 schema。
- 旧数据缺少 `publishGroupAddress` 时，通过本地 helper 补齐，不要求云端立即补历史数据。
- 保存后如果 EFC Group 新建或变化，刷新 proxy filter。

验证点：

- 云同步 JSON 仍包含 `publishGroupAddress`。
- 旧空间进入后不会因为缺失 `publishGroupAddress` 崩溃。

## 测试与验证

本仓当前没有可直接命中的 App 单元测试目标，本轮采用代码级验证 + iPhoneOS build + 关键日志人工核对。

1. 运行 `git diff --check`。
2. 运行：

   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

3. 人工核对关键日志：
   - 新增 EFC 后出现创建或复用 EFC Group 的日志。
   - 没有 Associate Group 时，proxy filter 包含该 EFC Group。
   - SAVE 不再发送 `SceneStore`。
   - 添加 Group 时发送 Light Lightness Server subscription 到 EFC Group。
   - Restore AUTO 时额外发送 Light LC Server subscription。
   - `0x4D/0x07` action config 的 TTL 为 `0xFF`。
   - EFC 发 `SceneRecallUnacknowledged(0xFF22)` 时 App 仍能解析为 restored。

## 风险与回退

- 如果固件的 EFC Scene Recall 状态事件依赖 EFC Scene Client publication，本轮必须保留该 publication 任务。
- 如果现场已有旧 Scene Server subscription，不做兼容清理会留下无用订阅；本轮会检测并删除。
- 如果旧数据缺少 `publishGroupAddress`，首次进入 Space 后仍需要有机会补齐；因此 EFC Group 创建不能只放在编辑页 SAVE。
- 如果 build 暴露 SDK 类型能力缺失，先确认是否属于协议编码层；非必要不修改 SDK。
