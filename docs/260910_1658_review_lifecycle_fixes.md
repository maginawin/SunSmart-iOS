# 删除与云端恢复的四项审查问题修复

日期：2026-09-10。工作区：`site-trigger-zone`。基于 `6b5ccbe0`。

## 修复结果

1. **Space 删除被明确拒绝后恢复状态。** `requestSpaceRemoval` 区分已知业务拒绝、无底层传输错误的 HTTP 4xx（排除 408）与结果未知。明确拒绝时，在锁内重新核对当前 generation，清除 `discardRequested` 并生成新的 generation；保留待上传内容和其他恢复原因。权限或密码错误沿用已有权限恢复处理。断网、超时、服务器失败、未知错误仍保留丢弃保护；成功或资源不存在仍沿用原删除流程。旧回调不能撤销新一次删除意图。
2. **正常解绑与列表共享开关实例。** 新增 `DeviceSwitchData.loadForDisplay`，仍按明确 Site/Space 作用域从数据库确定列表成员。仅在允许使用 Mesh 且当前网络作用域匹配时，复用相同作用域、ID、记录指纹的缓存实例，并将缺失或已变化的持久化记录同步到该缓存。列表和生产解绑回调因此共享对象，解绑后删除使用最新 Proxy/MAC/密钥字段。缺 Key、上下文不匹配或受阻时，只读取目标作用域的持久化记录。删除指纹校验保持生效。
3. **Power Switch 编辑副本保留作用域。** `PJEightKeySwitchData.copy` 同步复制 `recordScope`，覆盖电池和 AC 两类 Power Switch 的编辑返回路径。Force Delete 继续校验目标作用域。
4. **完整云端替换解除残余拓扑阻断。** 验证成功的 `finishImport` 清理名单加入 `remainingTopologyNeedsReview`。不完整云端输入不能清除该保护；无关阻断仍保留。

## 回归验证

本次新增用例直接执行提取的生产逻辑，外部网络、Mesh 设备和部分模型依赖使用隔离替身。

- `python3 scripts/check_space_recovery_receipts.py`：通过。新增明确删除拒绝后可重新进入云端导入准备、自动上传资格恢复、旧 generation 失效、待上传内容保留、无关阻断保留、权限保护、未知结果保持阻断，以及较新删除意图不被旧拒绝回调清除。完整有效云端替换新增残余拓扑原因及删除回执的清理验证；不完整输入和无关阻断验证通过。
- `python3 scripts/check_switch_record_scope.py`：通过。扩展 harness 提取生产 Power Switch 属性与覆盖 copy、生产 Node 解绑提交方法和绑定清理策略。新增正常绑定开关解绑后删除、旧指纹拒绝、缓存更新、跨 Space/受阻浏览、Battery/AC 编辑副本保存后 Force Delete；原 SQLite 事务和恢复用例通过。
- `python3 scripts/check_space_record_removal.py`：通过。
- `python3 scripts/check_proximity_scoped_import.py`：通过。
- `python3 scripts/check_space_mesh_keys.py`：通过。
- `git diff --check`：通过。

直接运行 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`，结果为 **BUILD SUCCEEDED**。构建解析的 NordicSigMeshSDK 为 `release` 分支 `a6246b1`。本次没有修改 SDK、依赖、资源、本地化或品牌 target 配置；未重新构建其他品牌。

## 验收边界与工作区

未做模拟器、真机、实际 BLE/Mesh 或真实服务器验收；隔离测试中的解绑提交与云端替换不代表设备或服务器验收完成。本次未改变 UI 布局或用户可见文案。

保留已有未跟踪文档 `docs/260910_1650_commit_6b5ccbe_review.md`。未提交、推送或修改 Git 历史。
