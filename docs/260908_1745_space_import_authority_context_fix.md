# Space 访客导入预检上下文修复

## 问题与修改

本次仅处理审查 P2。`SpaceData.update` 原先在远端元数据处理前捕获恢复上下文。首次访客导入，以及已有 owner/editor 降级访客时，`applyRemoteSpaceMetadata` 经生产权限逻辑将 authority 改为 readOnly，并更换 generation。原上下文因此在预检返回后失效，即使没有并发修改也会返回 `staleImportPreparation`。

现在保留元数据处理前的 active phase 检查，阻止正在删除的 Space 进入更新；在元数据、删除恢复及待导入数据等同步准备完成后、第一次 await 前捕获恢复上下文。预检和升级基线导出之后的取消、上下文、内存版本及数据库版本检查保持原有逻辑。

生产代码仅修改 `SunSmart/Common/Data/ImportData.swift`，无 SDK、依赖、target 配置或 UI 修改。工作区原有的 SunSmart scheme 修改和审查文档保持不动。未提交或推送。

## 回归验证

扩展 `scripts/check_space_recovery_receipts.py`，加入 `Tests/Group/SpaceImportPreparationTests.swift`。测试从生产文件提取 update 开头到两处异步失效检查结束的代码，并执行真实元数据、权限与恢复状态持久化方法；Mesh 预检、导出、数据库读取及删除恢复执行边界使用测试替身。

- 修改生产代码前，新测试在首次访客场景明确失败：`visitor import must survive its own authority transition`。
- 修改后，首次访客、owner/editor 降级访客、重复访客刷新及无并发变化的 owner 升级基线导出通过。
- 在预检和基线导出两个 await 边界分别注入权限变化、删除、账户切换、内存版本变化、存储版本变化及任务取消，均正确返回 `staleImportPreparation`。
- 已在删除中的 Space 在处理元数据前返回 `spaceRemovalPending`，未启动预检。
- `python3 scripts/check_space_recovery_receipts.py` 全部通过，包含既有持久化回执、重连、权限与生命周期回归。
- `python3 scripts/check_proximity_scoped_import.py` 全部通过，覆盖生产预检、拓扑保护、删除恢复与 Site 所有权回归。
- `git diff --check` 通过。

## 构建与验收边界

直接运行 xcodebuild，使用 `SunSmartLocal.xcworkspace`、SunSmart scheme、Debug、iphoneos、generic/platform=iOS、关闭代码签名，结果为 `BUILD SUCCEEDED`。构建解析到原有本地 NordicSigMeshSDK；仍有已有资源符号重名、AppIntents 等警告。

此次没有构建其他品牌或正式 workspace，也没有修改审查 P1 所涉及的正式 SDK 依赖。该本地构建不代表 P1 已修复。测试的 prepared 结果仅表示通过导入前置检查，不能视为完整 Mesh 导入提交成功；真实服务器、设备与 Site 页面端到端验收尚未执行。
