# Gateway Force Clear Spaces 实施总结

## 实施结果

已完成 Gateway 页面强制清空关联空间及服务器优先删除 Gateway 的改造。

- Gateway 蓝牙状态为 Offline、Associated Spaces 非空且当前用户满足 Owner 或全部关联空间 Editor 权限时，在 Identify 下方展示 Force clear spaces。
- 菜单使用 `menu_clear_spaces`，弹窗依据 Figma 节点 `494:13837` 的结构化设计信息实现，并复用现有 `SRAlertView`、Loading HUD 和 Site Update Toast。
- Force Clear 成功后才清空 `gatewayModel` 与编辑副本的 Associated Spaces，并保存本地数据库；失败、网络错误或超过 30 秒均不修改本地关联数据。
- 普通 Associated Spaces 编辑流程保持原行为：仅对用户删除的 space 逐条调用单项解绑接口。
- Gateway Delete 改为服务器优先：权限确认后先等待可能已发出的 Gateway 注册请求结束，阻止新的云端注册，再请求服务器删除。只有服务器确认成功后才进入蓝牙 Reset 和现有 Force Delete 流程。
- 服务器删除失败或超过 30 秒时不执行蓝牙 Reset、不清理本地数据，并显示 `Failed to delete gateway from server`。
- 服务器删除成功但蓝牙 Reset 失败或用户取消 Force Delete 时，本地 Gateway 保留并持久化“服务器已删除、待本地重置”状态，防止 App 重启或 Site 自动同步将 Gateway 注册回服务器。用户再次 Delete 时直接重试本地 Reset。

## 服务器接口调用说明

### 清空全部 Associated Spaces

- 请求路径：`/sitespace/sapce/gateway/unbind`
- 请求属性：传 `gatewayId` 与当前 `userId`
- 关键语义：必须完全省略 `spaceId`；服务器据此原子清空该 Gateway 的全部 Associated Spaces
- App 最大等待时间：30 秒；网络或 API 明确失败可提前结束

### 删除 Gateway

- 请求路径：`/sitespace/sapce/gateway/delete`
- 请求属性：传 `gatewayId` 与当前 `userId`
- 服务器职责：删除 Gateway 并同时清除 Associated Spaces，且对服务器上已不存在的 Gateway 按幂等成功处理
- App 最大等待时间：30 秒；只有收到成功结果才确认服务器删除成功并继续本地 Reset/Force Delete

## 关键状态边界

1. Force Clear 的权限在菜单展示时使用本地状态判断，用户确认后会基于服务器返回的最新关联空间再次校验非 Owner 用户的 Editor 权限。
2. Force Clear 与 Delete 共用互斥的破坏性操作状态，避免重复点击产生并发请求。
3. Delete 在发请求前取消待执行的 Gateway 云同步，并等待已经进入服务器授权阶段的注册请求完成；删除进行中与待本地重置状态均会阻止后续 Gateway 注册。
4. `gatewayDelete` 成功前不预清 MQTT、Associated Spaces、上传时间戳或其他本地数据。
5. `gatewayDelete` 成功后持久化待本地重置状态；蓝牙 Reset 成功或用户确认 Force Delete 后才执行原有本地 Gateway 清理。

## 文案与国际化

新增文案已同步 English 与简体中文。英文结果文案为：

- `All associated spaces cleared from server`
- `Failed to clear all associated spaces`
- `Failed to delete gateway from server`

## 验证结果

- Gateway 菜单策略测试通过。
- Force Clear/Delete 契约测试通过，覆盖清空接口参数、普通逐项解绑回归、30 秒超时、菜单条件、成功/失败本地提交、服务器优先删除、防回注册与断点续删。
- English 与简体中文 strings 文件 `plutil -lint` 通过。
- `git diff --check` 通过。
- generic iPhoneOS、关闭签名构建通过：SunSmart、Archipelago、SLG Sync Plus、SylSmart。

## 仍需联调验收

- 使用真实服务器验证省略 `spaceId` 的原子清空响应、`gatewayDelete` 的幂等成功及服务器数据最终一致性。
- 使用真机验证蓝牙 Offline 判定、Reset 成功、Reset 超时、Force Delete、取消后重试及 App 重启后的防回注册。
- 在四个品牌 App 中进行弹窗、菜单宽度、图标和 Toast 的视觉验收。
- 使用可控延迟或代理环境验证完整 30 秒超时边界。

