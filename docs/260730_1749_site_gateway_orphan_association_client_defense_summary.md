# Site Gateway 孤儿关联客户端防御实现总结

## 结论

已按确认方案完成客户端防御：当 Owner 获取到完整且结构有效的 Site Gateway 列表时，以该列表作为 Site 的服务器真值；如果 Space 保留的 `gatewayId` 不在列表中，则清除这条孤儿关联及其在线缓存。

对于本次日志中的数据：

- Site 返回 `gateways: []`
- 两个 Space 仍返回旧的 `gatewayId`
- 两个 Space 仍返回 `gatewayOnline: true`

导入完成后，这两个 Space 会被修正为未绑定状态，因此 Site 页面应展示：

- `Internet Online = 0`
- `No Gateway = 2`

## 实现范围

### 1. 新增纯策略层

新增 `SiteGatewayAssociationConsistencyPolicy`，负责构建服务器 Gateway 身份快照并判断 Space 关联是否有效。

快照只有在以下条件全部满足时才具有权威性：

- 当前用户是 Site Owner，可获取完整 Gateway 集合
- 响应中存在 `gateways` 数组
- 数组内每个 Gateway 都有非空 `macAddress`

`gateways: []` 是合法且权威的空集合，表示该 Site 当前没有 Gateway。

### 2. 接入 Site 数据导入

在同一次 Site 数据响应中先构建 Gateway 身份快照，再检查本次响应返回的每个 Space：

- Space 未绑定 Gateway：保持不变
- Space 的 Gateway 仍存在于服务器列表：保持服务器下发的在线状态
- Space 的 Gateway 不在权威列表中：清除孤儿关联

清理字段包括：

- `relevanceGatewayId`
- `gatewayState`，设为未绑定
- `gatewayLastOnline`

修正结果保存到本地数据库，不触发云端绑定、解绑或删除请求。

### 3. 权限和异常响应保护

以下情况不执行清理，避免把“不可见”误判为“不存在”：

- Editor、Visitor 等非 Owner 权限
- 响应缺少 `gateways`
- `gateways` 结构异常
- Gateway 标识为空或不完整

### 4. 保持状态真值边界

本次防御只解决服务器 Gateway 集合与 Space 缓存关联之间的不一致：

- 不使用本地 Mesh `Node.state` 判断 Internet 状态
- 不因为本地 Node 暂时不可用而清除有效关联
- 不修改 Gateway 绑定、解绑、删除业务流程
- 不修改 Site 页面计数算法

## 测试与验证

采用测试驱动方式完成：

1. 策略文件缺失时，新增策略测试先失败
2. 导入流程未接入策略时，合同测试先失败
3. 新文件未加入全部品牌 target 时，target 合同检查先失败
4. 分别完成最小实现后恢复为通过

聚焦回归通过：

- Site Gateway 在线状态与孤儿关联策略测试
- Gateway Associated Spaces 候选数据源测试
- Gateway Associated Spaces 延迟保存测试
- `git diff --check`

四个 App target 的通用 iPhoneOS Debug 构建均成功：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

构建日志仍包含工程原有警告，包括 AppIntents 元数据跳过、部分品牌 target 的 Info.plist 资源警告，以及已有的 FSCalendar 重复引用警告；未出现本次改动引入的编译错误。

## 验收边界

静态测试与四品牌构建已覆盖客户端规则和接入范围，仍建议使用真实 Owner 账号和服务器数据验证：

1. Site 无 Gateway、Space 带历史 Gateway 在线缓存时，进入 Site 后显示 `Internet Online = 0`
2. 两个 Space 均显示未绑定 Gateway
3. Site 存在有效 Gateway，但本地 Mesh Node 尚未加载时，不错误清除关联
4. Editor、Visitor 账号进入同一 Site 时，不因 Gateway 列表受限而清除关联

## Git 状态

未执行 commit、push 或 merge；当前 `fix` 分支及 linked worktree 保持原状。
