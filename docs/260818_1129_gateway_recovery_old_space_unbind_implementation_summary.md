# Gateway Recovery 旧 Space 解绑修复实施总结

## 实施结果

已按确认方案完成修复：保持 Force Clear Spaces 的服务器请求、本地提交、权限和 UI 流程不变，仅补齐专用 Gateway Recovery 对旧 Associated Space 配置的清理能力。

Gateway 在离线 Force Clear 后重新上线时，Recovery 现在会根据 Gateway 当前实际持有的 secondary Network Key 与本地 `gateway.associatedSpaces` 期望列表计算待移除集合。对不再属于期望关联列表的旧 Space，复用已有 `gatewayUnbindAssociatedSpace` 删除任务，执行现有的 Model App Unbind、AppKey Delete、NetKey Delete 和必要的 Vendor Subnet AppKey Delete 消息链。

## 步骤与依赖

新的恢复顺序为：

1. Initialize 完成基础 Gateway 初始化。
2. Associated Spaces 新增任务与旧 Associated Spaces 解绑任务在 Initialize 成功后执行。
3. Sync Spaces 等待全部关联新增和解绑任务成功，再下发最终 Subnet AppKey Index 列表。
4. Verify Configuration 保持依赖完整 Recovery 步骤集，因此也会等待旧关联解绑及 Sync Spaces 完成。

Wi-Fi Gateway 的服务器授权与服务器信息步骤仍只依赖 Initialize，没有被无关地串行到 Mesh 关联清理之后；最终 Verify Configuration 会统一等待 Mesh 与服务器两侧步骤收敛。

## 改动范围

- 修改 `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`。
- 新增 `Tests/Device/GatewayRecoveryAssociatedSpacesContractTests.swift`。
- 未修改 Force Clear API、`GatewayViewController` 的 Force Clear 成功提交、国际化文案或 NordicSigMeshSDK。
- 未修改本地化、资源、target 配置或依赖。

## 回归保护

新增契约覆盖：

- Recovery 必须从 Gateway 实际 Network Key 状态派生不再需要的 secondary Key。
- Recovery 必须构造既有 `gatewayUnbindAssociatedSpace` 删除任务。
- Sync Spaces 必须等待全部 Associated Space 新增和删除步骤。
- Verify Configuration 必须继续依赖完整 Recovery 步骤集。

测试采用失败先行：在原实现上因缺少旧 secondary Key 派生逻辑失败；完成实现后通过。

## 验证结果

以下检查通过：

- `GatewayRecoveryAssociatedSpacesContractTests`
- `GatewayForceClearSpacesContractTests`
- `GatewayMenuPolicyTests`
- `scripts/check_wifi_gateway_repair_recovery.sh`
- English 与简体中文 strings 的 `plutil -lint`
- `git diff --check`
- SunSmart generic iPhoneOS Debug build，关闭签名
- Archipelago generic iPhoneOS Debug build，关闭签名
- SLG Sync Plus generic iPhoneOS Debug build，关闭签名
- SylSmart generic iPhoneOS Debug build，关闭签名

构建仍有工程既有的资源符号重复、MainActor 隔离及历史 API 弃用 warning；本次改动没有新增编译错误。

## 真机验收边界

编译与源码契约不能证明真实 Gateway 已完成配置清理。仍需使用 Force Clear 后重新上电的 Gateway 验证：

1. Sync device(s) 页面出现 `Unbind Associated Spaces`，且列出旧关联 Space。
2. Model App Unbind、AppKey Delete、NetKey Delete 和 Vendor Subnet AppKey Delete 获得预期 ACK。
3. Sync Spaces 在解绑成功后下发空的最终 Subnet AppKey Index 列表。
4. Verify Configuration 成功。
5. 返回 Gateway 详情页后 `Devices not synced` 消失。
6. Gateway 无需删除重加，并可重新关联其他 Space。
7. 单个旧 Space 删除失败时，Sync Spaces 与 Verify Configuration 不应越过失败步骤；重试后可继续收敛。
