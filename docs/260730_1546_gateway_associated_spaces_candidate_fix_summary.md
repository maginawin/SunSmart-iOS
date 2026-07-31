# Gateway Associated Spaces 候选修复总结

## 结论

方案 A 已完成。Gateway Associated Spaces 的本地候选不再从全局
`MeshNetworkManager.instance.meshNetwork` 查找 AppKey，而是在首次进入及
Retry 时，使用当前 Site 的 `meshUUID` 和 Primary `meshNetworkId` 重新加载
显式 MeshNetwork 快照。

这会修复以下数据源错位：Site 页面可从正确 Site 主网解析并进入 Gateway，
但 Associated Spaces 曾从另一个 Site、旧内存快照或尚未切换完成的全局
MeshNetwork 查找 AppKey，导致业务上合格的 Space 被 `compactMap` 静默丢弃，
最终误显示 `No Data!`。

## 实施内容

1. 新增纯 Swift 候选策略，集中处理编辑权限、Gateway 绑定归属和 AppKey 匹配。
2. 两个可编辑且未绑定的 Space，只要在显式 Site 网络快照中命中 AppKey，
   就会返回两个候选。
3. 业务上合格的 Space 缺少 AppKey 时，返回“候选数据不可用”，不再伪装成
   真实空列表。
4. Associated Spaces 页面首次进入和点击 Retry 时都会重新获取候选。
5. 云端已绑定 Space 仍可补入列表；真正没有候选时仍显示 `No Data!`。
6. 复用现有获取失败与 Retry 文案，没有新增本地化、资源、依赖或 Auth 信息。
7. 新策略文件已加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个
   target。

## TDD 与验证

- RED：候选策略尚不存在时，聚焦 runner 按预期失败。
- GREEN：候选策略测试通过，包括两个未绑定 Space、缺失 AppKey、无编辑权限、
  已绑定其他 Gateway，以及 Gateway ID 大小写匹配。
- Gateway Associated Spaces 延迟保存契约通过。
- Site Gateway 在线状态及数据源所有权契约通过。
- `git diff --check` 通过。
- SunSmart generic iPhoneOS 构建通过。
- Archipelago generic iPhoneOS 构建通过。
- SLG Sync Plus generic iPhoneOS 构建通过。
- SylSmart generic iPhoneOS 构建通过。

构建期间仅出现工程已有的资源或重复引用警告，没有构建失败。

## 验收边界

自动化验证证明候选策略、静态契约、四 target membership 和编译成立；尚未替代
真实账号、服务器数据、4G Gateway 硬件及真机交互验收。

建议真机复测：

1. 当前 Site 存在两个可编辑、未绑定任何 Gateway 的 Space。
2. 从 Site 页面进入该 Site 的 4G Gateway。
3. 打开 Associated Spaces。
4. 确认两个 Space 均展示且可选择。
5. 保存后重新进入，确认关联结果与服务器数据一致。

本次未执行 Git commit、push 或 merge。
