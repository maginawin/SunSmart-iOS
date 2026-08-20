# SLG Space Mesh 上下文修复实施总结

## 结论

已按确认范围完成修复。问题根因不是服务端返回空数据，而是并发的 Site Load 在 Space 已完成子网加载后，又把全局 `MeshNetworkManager` 切回 Site Primary 网络。随后 Products、Scenes、Timed 等页面读取全局 Manager 时，拿到错误 Network ID 下的数据，因此出现 `No devices` 或定时数量从 1 变成 0；重新进入 Space 会重新激活 Space 子网，所以数据恢复。

## 已实施改动

1. 移除后台 Site Load 完成回调中的全局 Primary Mesh 切换。Site 页面仍在自身可见生命周期中激活 Primary 网络，后台请求不再覆盖当前 Space 的 Mesh 上下文。
2. Site 数据导入只有在 Mesh UUID、Network ID 和 Primary 标记都完全匹配时才复用全局 Manager；否则显式加载该 Site 的 Primary Network ID。
3. Space 定时导入只有在 Mesh UUID 和 Space Network ID 都匹配当前全局上下文时，才更新全局 schedules，避免同一 Mesh 下不同子网相互污染。
4. 新增 Site/Space Mesh 上下文所有权契约，固定 Site 可见生命周期、Space 进入生命周期、Site 导入和 Space schedules 写入的职责边界。

## 自动化验证结果

以下契约均通过：

- 新增 Site/Space Mesh 上下文所有权契约。
- 现有 Site Gateway 在线状态与同步契约。
- 现有 Timed Scheduler 持久化、读取完成和单一所有者契约。
- `git diff --check`。

以下四个品牌均通过 Debug、generic iPhoneOS、关闭签名的构建：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

## 影响范围判断

改动没有修改请求接口、服务端数据结构、Mesh 协议、用户可见文案、本地化、资源、依赖或 target 配置。Site 页面主动显示时仍会激活 Primary 网络，Space 页面主动显示时仍会激活自己的子网；变化仅是禁止已退到后台的 Site Load 完成回调抢占当前页面的全局 Mesh 上下文。

现有契约和四品牌构建没有发现其他功能回归，但自动化结果不能等同于真机运行验收。仍建议在 SLG Sync Plus 真机上重点执行“打开网关详情并立即关闭，立刻进入 Space，再快速切换 Products、Scenes、Timed”的连续压力验证，并确认设备控制、场景和定时读取均保持正常。

## 明确未实施

- 请求会话或取消机制重构。
- Site/Space 导入事务化。
- Empty UI Auto Layout 警告修复。

这些项目与本次 Mesh 上下文竞态修复保持隔离。
