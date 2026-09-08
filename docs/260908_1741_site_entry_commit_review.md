# Site 进入性能改动审查

## 范围

- 审查 `250e0ee..HEAD`，HEAD 为 `e014e837`，共一个提交、22 个文件。
- 未提交的 `SunSmart.xcodeproj/xcshareddata/xcschemes/SunSmart.xcscheme` 修改不属于本次范围，保持不动。
- 未修改业务代码、SDK 或依赖配置。

## 结论

当前补丁存在以下两个应修复的问题。

### P1：正式依赖缺少新增 SDK 接口

`Database.swift:66` 调用了 `MeshDataManager.databaseReadRevision()`。正式 workspace 未配置本地覆盖，Package.resolved 仍锁定 `86f5ec9e40148b9cd93e0512702337fcec41dd40`；直接检查该 revision 的源码确认不存在此接口。接口目前只在 one-dev 未提交修改中存在。因此本地开发 workspace 可构建不代表正式 workspace 或干净检出可构建，所有共享此代码的品牌 target 均受影响。需按原有 SDK 发布流程提供包含接口的版本并更新正式依赖，不应强行改绑用户本地开发入口。适用规则：AGENTS.md 第 13–15 行。

### P2：首次访客导入被自身权限转换误判为过期

`SpaceData.update` 在处理远端元数据前捕获恢复上下文，却在新增预检 await 后使用此旧上下文判断是否过期。首次访客导入的恢复状态默认为 writable；本次 `applyRemoteSpaceMetadata` 经 `reconcileAuthority` 转为 readOnly，并由 `updateAuthority` 更换 generation。即使没有任何并发修改，第 1642–1645 行也会拒绝合法导入。新 Space 经 `SpaceData.import` 返回 nil，当前 Site 更新无法加入该 Space；已有 Space 降级访客时，本轮配置刷新也会被拒绝。应在本次合法元数据/权限转换完成后捕获供异步预检使用的上下文，同时保留返回后的真正过期检查。

## 验证

- `git diff --check 250e0ee HEAD` 通过。
- `check_network_response_queue.py` 通过。
- `check_proximity_scoped_import.py` 通过。
- `check_space_recovery_receipts.py` 通过。
- `check_site_entry_performance.py` 对本地 one-dev SDK 通过；这不是正式 SDK 依赖验证。
- 临时扩展现有 recovery receipt harness，运行生产元数据、权限和恢复状态方法：确认新访客处理元数据后，处理前上下文不再 current，而处理后新上下文仍 current；没有并发修改。该复现未写入仓库测试文件。

未执行 iOS 构建、生产服务器 gzip 接收测试、真实 Mesh 操作或原 iPad 性能/布局验收；已有合同测试通过不能替代这些验证。
