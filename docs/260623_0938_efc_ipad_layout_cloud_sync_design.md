# EFC iPad 布局与云同步设计

## 背景

本次需求包含两个问题：

- iPad 上 Others 分类中的 EFC 设备卡片没有像 Lights、Switches 一样居中排列，且卡片尺寸偏大。
- Owner 或 Editor 在 EFC Edit 页面修改 EFC 配置后，对端重新进入 Space 或手动拉取后应能看到最新配置；同步目标需要与 Battery Power Switch、Group Profile 等配置一致，进入现有云同步链路。

本设计只覆盖 iPad Others 中 EFC item 的布局一致性，以及 EFC Edit 配置变更的云同步可验证性。不做 Owner/Editor 同页实时推送。

## 代码事实

### iPad Others 布局

`DeviceOthersViewController` 已定义与 Lights/Switches 相同的布局参数：

- iPad 列数：6
- iPad collection 边距：24
- iPad item 间距：30

但当前 `flowLayout` 初始化时写死了较小的 spacing 和 section inset，没有使用这些参数，也没有设置 `itemRowCount`。因此在 iPad 上，Others 的实际 item 宽度和居中算法会偏离 `DeviceLightsViewController`，表现为 EFC item 与 Lights item 大小、排列不一致。

### EFC 云同步

当前 EFC Edit 保存链路已经具备基础云同步能力：

- `LinkedEmerFireEditVC.saveAction()` 保存成功后会发 `spaceDataChangedNotificaitonName`，类型为 `.device`。
- `SpaceViewController` 对 Owner/Editor 收到 `.device` 后，会更新 `space.lastUpdate` 并调用 `syncSpace(level: .promptly)`。
- `SyncLevel.promptly` 的等待时间为 0 秒，语义上是立即加入云同步队列。
- `SpaceData.export()` 会导出 `emergencyFireControllers`，字段包含 `configuration`、`bindNodeAddress`、`publishGroupAddress`、`reportToGateway` 等。
- `SpaceData.update(spaceJsonData:)` 会在远端 payload 包含 `emergencyFireControllers` 时重建本地 EFC 配置。

因此，EFC Edit 配置变更不是完全没有接入云同步。更可疑的风险点是：

- EFC 同步任务完成后，`isSynced` 等状态再次本地保存，但没有再次发起 Space 云同步。
- 现有云同步缺少 EFC 维度的明确 contract 或 debug 证据，测试时很难确认 `spaceUpload` payload 和对端 `spaceInfo` response 是否带了最新 `emergencyFireControllers`。
- 对端导入依赖远端 `updateTimestamp` 变新。若服务端保存或返回的 timestamp 没有变化，配置内容变化但数量不变时可能被 timestamp gate 跳过。

## 推荐方案

采用“最小修复 + 可验证合同”的方案。

### 1. iPad Others 布局对齐 Lights

调整 `DeviceOthersViewController` 的 collection layout，使其和 `DeviceLightsViewController` 使用同一类参数：

- `minimumLineSpacing` 使用 `itemMargin`。
- `minimumInteritemSpacing` 使用 `itemMargin`。
- `itemRowCount` 使用 `columnNum`。
- iPad content inset / section inset 规则对齐 Lights，确保 AlignCenterFlowLayout 能按 6 列、24pt 外边距、30pt 间距计算。
- `sizeForItemAt` 继续按 `columnNum`、content inset、section inset、interitem spacing 计算正方形 item。

目标是 iPad Others 中 EFC item 的尺寸和行内居中效果与 Lights item 一致；同时不改变 iPhone 行为，不影响 Dongle 的点击、长按、删除逻辑。

### 2. EFC Edit 云同步保持现有架构

保留现有 `.device` + promptly 同步模式，不新增独立 EFC 云接口，也不做同页实时推送。

保存 EFC 配置后的期望链路为：

1. EFC Edit 保存本地 `DeviceEmerFireData`。
2. 发送 `.device` 类型 Space 变更通知。
3. Space 更新 `lastUpdate`。
4. 现有 `CloudSynchronizationManager` 立即执行 `.syncSpace` 或必要时 `.syncSite`。
5. `SpaceData.export()` 带上最新 `emergencyFireControllers`。
6. 对端重新进入 Space 或手动触发 `spaceInfo` 拉取后，`SpaceData.update()` 导入最新 EFC 配置。

### 3. 补齐 EFC 云同步验证点

为了确认“真的同步给服务器”，增加轻量验证手段，优先使用 DEBUG contract 或现有脚本扩展：

- 断言 `LinkedEmerFireEditVC` 的保存路径仍然发 `.device`，不能退化成 `.common` 或只发本地刷新通知。
- 断言 `SpaceData.export()` 持续包含 `emergencyFireControllers` 和 `configuration`。
- 断言 `SpaceData.update()` 继续只在 payload 存在 `emergencyFireControllers` 时覆盖本地 EFC 表，避免旧 payload 清空本地配置。
- 如需要日志，增加 DEBUG-only EFC cloud probe，输出本次 `spaceUpload` 中的 EFC 数量、id、lastUpdate，不输出敏感 Auth 信息。

### 4. 同步成功后的状态补发评估

重点检查 EFC 设备同步完成后的保存路径：如果同步成功后会更新 `isSynced` 并通过 `DeviceEmerFireStore.shared.save(data)` 落本地，那么这类本地状态也应被云端感知。

实施时优先确认是否需要在同步成功回调中补发 `.device`：

- 若目标只要求“配置内容”同步，且 `isSynced` 不作为对端业务真值，可只保留现状并写入验证说明。
- 若目标要求对端也看到同步后的准确 EFC 状态，则在 sync success 持久化后补发 `.device`，让 `isSynced` 等状态进入下一次 promptly `spaceUpload`。

推荐实现时选择第二种，更接近“EFC Edit 页面变更后对端重新进入能看到最新配置和状态”的直觉。

## 验收标准

- iPad Others 中 EFC item 与 Lights item 使用相同列数、边距、间距和 item 尺寸。
- iPhone Others 布局不出现明显回归。
- EFC Edit 保存后，Owner 和 Editor 都会触发 Space promptly 云同步。
- `spaceUpload` 或 `siteUpload` payload 中包含最新 `emergencyFireControllers.configuration`。
- 对端重新进入 Space 或手动触发拉取后，能导入最新 EFC 配置。
- 若 EFC sync success 会更新 `isSynced`，该状态也能进入云同步 payload。

## 不做范围

- 不实现 Owner/Editor 同页实时推送。
- 不重写 `CloudSynchronizationManager`。
- 不新增 EFC 专用云 API。
- 不调整 EFC 协议、AppKey、vendor message、associated groups 订阅策略。
- 不顺手重构 Others、Lights 或 Battery Power Switch 的通用布局组件。

## 验证计划

- 运行 EFC contract 脚本，扩展必要断言覆盖 Others layout 和 EFC cloud contract。
- 运行 `git diff --check`。
- 运行 iPhoneOS 构建：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

如需人工验证：

- Owner 修改 EFC Edit 配置，等待云同步完成；Editor 重新进入 Space 或手动拉取，确认 EFC Edit 显示最新配置。
- Editor 修改 EFC Edit 配置，等待云同步完成；Owner 重新进入 Space 或手动拉取，确认 EFC Edit 显示最新配置。
- iPad 打开 Devices > Others，对比 EFC item 与 Lights item 的尺寸和居中效果。
