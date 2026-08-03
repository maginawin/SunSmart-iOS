# 全部 EFC Controller 恢复支持实施总结

**日期：** 2026-08-03
**方案：** B（Restore Device Data 两阶段恢复，复用当前 EFC 专用同步链）
**状态：** 代码、聚焦测试、静态合约和四个 App target 构建已完成；真机 EFC/Mesh 验收待执行

## 1. 实施结果

Restore Device Data 现已支持当前设备配置注册表中全部 `EmergencyController` 产品，不再维护 EFC PID 白名单。当前内置的 `CID 0x0A78 / PID 0x2131` 因已登记为 `EmergencyController`，已进入支持范围。

EFC 恢复采用精确身份约束：历史 Node 与当前未配网广播都必须具备 CID/PID、都必须命中当前注册表中的 `EmergencyController`，且 CID/PID 完全一致。不同 EFC 产品、身份缺失、EFC 与普通设备交叉匹配均被拒绝，避免按相同 MAC 误迁移到不同产品。

恢复执行已改为两阶段：

1. Restore 页完成 Provision、Key Bind 和 `DeviceEmerFireData` 地址迁移；迁移后继续保持未同步真值。
2. 批次添加完成后，逐台进入现有 `SyncDevicesViewController(.emergencyFire)`，由当前 EFC planner/执行器同步 Working Mode、Action Config、Resend、Restore Delay、Scene Client publication、关联灯订阅和 pending cleanup。

只有专用同步结束且控制器权威状态 `isSynced == true` 时，Restore 页才将 EFC 标记为成功。失败或中止保持 `syncFailed`，Retry 仍走 EFC 专用同步，不进入普通 `.devices` 同步链。

## 2. 与当前 EFC 功能链的符合性

本次没有恢复旧的 Fast Add 扁平 message handles 方案，而是删除 Restore 中过时的 EFC handle 执行与失败聚合逻辑，复用当前已维护的 EFC 专用任务链。因此恢复后的功能范围与现有 EFC Controller 保存/同步功能一致：

- 保留控制器名称、绑定地址、内部 publish group、Gateway 选项及完整 configuration；
- 使用当前四态 Working Mode，而不是旧的单一 enabled 语义；
- 同步 Trigger/Restore resend、三种状态 Action Config、Restore delay；
- 重新校验并同步 Scene Client publication；
- 关联设备继续只处理 Light，并执行新增订阅及 pending cleanup；
- 由当前专用同步页处理 task 状态、local-only、unsupported、Retry 和最终持久化；
- `controllerSelfSyncPending` 与 `isSynced` 继续作为现行同步真值，不因 Provision 成功而提前置为成功。

## 3. 主要改动

- 新增纯 Swift `DeviceRestoreCandidatePolicy`，集中处理入口范围、注册表类别及 EFC 精确身份策略。
- Restore 扫描候选改为从 `MeshLibManager.manager.supportDeviceInfos` 动态识别 EFC。
- `.all` 和当前 Space 非 Gateway 入口允许已注册 EFC；Site Gateway 入口仍只允许 Gateway。
- 通过身份验证后，以精确 CID/PID 对应的配置更新历史 Node 和 ProvisioningDevice 类型。
- EFC Fast Add 阶段只迁移本地控制器数据，不再展平 EFC planner handles。
- 新增 EFC 专用顺序同步队列；混合批次中 EFC 与普通设备失败分别路由。
- 新增聚焦策略测试、四 target 源文件归属检查，并更新 EFC 业务合约。
- 未修改 `NordicSigMeshSDK`，未新增用户可见文案，未修改本地化资源。

## 4. 变更文件

- `SunSmart/Main/Device/Model/DeviceRestoreCandidatePolicy.swift`
- `Tests/Device/DeviceRestoreCandidatePolicyTests.swift`
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- `SunSmart.xcodeproj/project.pbxproj`
- `scripts/check_device_restore_efc_support.sh`
- `scripts/check_efc_controller_flows.sh`
- `docs/260803_1011_efc_restore_device_data_analysis.md`
- `docs/260803_1034_efc_restore_all_controllers_implementation_plan.md`
- `docs/260803_1034_efc_restore_all_controllers_implementation_summary.md`

## 5. 已执行验证

### 聚焦测试与静态合约

- 候选策略先完成 RED：测试单独编译时因策略类型尚不存在而失败。
- 实现后 GREEN：`DeviceRestoreCandidatePolicyTests passed`。
- `scripts/check_device_restore_efc_support.sh`：PASS。
- `scripts/check_efc_controller_flows.sh`：PASS。
- `scripts/check_efc_comprehensive_status_mapping.sh`：PASS。
- `scripts/check_efc_status_content_list.sh`：PASS。
- `scripts/check_efc_i18n.sh`：PASS。
- `git diff --check`：PASS。

### iPhoneOS 构建

以下四个 scheme 均使用 generic iPhoneOS、Debug、`CODE_SIGNING_ALLOWED=NO` 直接执行 `xcodebuild`，构建成功：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

构建仍包含工程原有的重复资源、过时 API、actor isolation、重复 source/Info.plist 等警告；本次没有扩大范围处理这些既有警告。

## 6. 真机验收边界

当前证据证明源码策略、静态业务合约及四 target 编译成立，但不能证明真实 EFC、Mesh ACK、设备状态回报和持久化重启链已经通过。发布前至少需要完成以下验收：

1. `0x0A78/0x2131` EFC 重置后按 MAC/旧 MAC扫描、恢复和专用同步成功。
2. 另一种已登记 `EmergencyController` 的 CID/PID 产品执行相同恢复，证明非硬编码 PID。
3. 历史 EFC 与广播 CID/PID 不一致、身份缺失或未注册时不进入恢复。
4. Disabled、Power Loss、Fire Alarm、Both 四种 Working Mode 分别恢复。
5. Trigger/Restore action、brightness 0、delay 和 resend 的设备侧行为正确。
6. 多关联灯组、仅 Light 过滤、在线/离线设备、订阅新增和 pending cleanup 正确。
7. Scene Client publication、EFC vendor 消息及综合状态回报均由真实包和设备状态确认。
8. EFC 同步失败、中止、单任务 Retry、再次成功后的 Restore 状态与落库真值一致。
9. BLE OTA `specified` 恢复、App 重启后的控制器记录、绑定地址和同步状态正确。
10. 与普通设备、Gateway 混合恢复时，两类同步队列及失败路由互不污染。

## 7. Git 状态

本次未创建 commit、未 push、未 merge；改动保留在当前 `fix` worktree，等待人工检查与真机验收。

## 8. 审查修复补充

后续代码审查发现并已修复入网后身份异常降级、自动 OTA 失败误完成和迁移失败 Retry 无执行路径三项问题。最终状态和新增验证见 `docs/260803_1151_efc_restore_review_fixes_summary.md`。
