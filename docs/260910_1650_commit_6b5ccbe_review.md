# 6b5ccbe 代码审查

## 范围与结论

- 比较 `6b5ccbe^..6b5ccbe`，审查开始时工作区干净。
- 适用项目规则为根目录 `AGENTS.md`，未发现更具体的指令文件。
- 结论：存在 4 个应修复的运行时问题。未修改业务代码、测试文件或 Git 历史。
- 这些问题来自调用链与状态契约，不是基于缺少构建或真机验收而提出。

## 问题

### P1：服务器明确拒绝删除后，Space 仍被持久化锁定

`SpaceConfigurationSafety.requestSpaceRemoval` 在请求前保存 `discardRequested = true`，但收到 `editorBeingUsedSpace` 等明确失败时直接返回。该标记让 `isBlocked` 为真、自动上传被禁止，`SpaceData.update` 连云端重载也直接保留旧数据。现有恢复菜单不能清除标记；应区分明确拒绝和结果未知，前者解除丢弃状态，同时保留旧回调失效保护。

### P2：列表改用独立 Switch 对象，正常解绑成功后无法完成删除

`DeviceSwitchesViewController.updateUI` 改为从数据库创建列表对象，但成功解绑回调 `commitSuccessfulEnOceanSwitchUnbind` 仍修改并保存 `MeshNetworkManager.instance.switchs` 中的实例。删除完成回调捕获的列表对象保留旧 Proxy/MAC/密钥，随后被 `SwitchRecordDeletion.remove` 的指纹比较拒绝。正常 Mesh 流程需要保持或协调同一作用域中的实例，不能仅替换列表数据来源。

### P2：Power Switch 的覆盖 copy 方法遗漏新增作用域

基类新增 `recordScope` 并在自己的 `copy` 中复制，但 `PJEightKeySwitchData.copy` 覆盖实现未复制该字段。`PJPreAddEightKeySwitchesViewModel.buildSwitchData` 使用此覆盖方法生成编辑对象，保存后经 `switchSavedAction` 返回监控页；后续删除会被新增的作用域检查拒绝，即使 Force Delete 也无法继续。应同步覆盖方法的字段传递，而不是移除删除边界的作用域校验。

### P2：完整云端替换未清除已解决的残余拓扑阻断

本次提交的删除协调器新增 `remainingTopologyNeedsReview` 原因。较新的完整云端配置通过验证并覆盖旧拓扑后，`finishImport` 的清理名单不包含此原因。结果是配置和时间戳已更新、待处理上传已清空，但 `adoptCloud` 仍报告失败，Mesh 配置仍受阻。应清除已被完整替换且验证成功的拓扑故障，同时保留真正无关的阻断原因。

## 验证

以下现有脚本均通过：

- `python3 scripts/check_space_mesh_keys.py`
- `python3 scripts/check_space_record_removal.py`
- `python3 scripts/check_space_recovery_receipts.py`
- `python3 scripts/check_switch_record_scope.py`
- `python3 scripts/check_proximity_scoped_import.py`
- `git diff --check 6b5ccbe^ 6b5ccbe`

另外在临时目录扩展现有隔离 harness，未写入仓库测试文件，复现：

1. 明确拒绝删除后，持久化阻断与云端重载跳过。
2. 模拟生产解绑回调对缓存实例的字段清理并保存，列表旧实例删除失败，而重新加载实例可删除。
3. 执行生产 Power Switch 覆盖 copy 方法，作用域丢失并触发删除拒绝；依赖属性使用最小替身。
4. 完整有效云端替换已完成，但残余拓扑原因仍使恢复返回失败。

检查 SDK 行为时使用与本工程锁文件一致的缓存 checkout（`a6246b1`），未修改 SDK。未运行新的 iOS 构建、模拟器、真机、BLE/Mesh 或真实服务器验收；隔离测试不代表这些验收已经通过。
