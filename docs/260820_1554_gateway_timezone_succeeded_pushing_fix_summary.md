# Gateway timezone `SUCCEEDED` 状态兼容修复总结

## 修复结果

已修复 Gateway request status 返回 `SUCCEEDED` 后，Edit Site timezone 状态页持续显示 `Pushing...` 的问题。

修复后，服务器返回的 `SUCCEEDED` 会映射为现有内部成功状态，对应 Gateway 从 `.pushing` 转为 `.synced`；单 Gateway 场景可以立即结束 session，不再等待 60 秒超时。

## 代码改动

### 响应状态兼容

修改：`SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneResponseParser.swift`

- 新增对服务器真实返回值 `SUCCEEDED` 的识别；
- 保留既有 `SUCCEED` 兼容；
- 保持原有大小写和首尾空白归一化；
- 未扩大到没有服务器证据的其他成功拼写；
- 未修改 API、状态机、轮询间隔、超时、UI 文案、国际化、权限或 SDK。

### 真实响应回归测试

修改：`Tests/Site/SiteGatewayCloudTimeZoneResponseParserTests.swift`

新增生产响应形状测试，覆盖：

- 大写 Gateway MAC；
- `SUCCEEDED` 状态；
- MAC 归一化；
- Parser 输出内部成功状态；
- 将解析结果应用到 batch 后，Gateway 从 `.pushing` 转为 `.synced`；
- 成功 batch 满足 `canDismiss`。

实施前先运行新增测试，旧实现按预期失败，错误为生产 `SUCCEEDED` 未映射到内部成功状态。完成 Parser 修改后，聚焦测试通过。

## 自动化验证

以下检查均已通过：

1. `SiteGatewayCloudTimeZoneResponseParserTests` 聚焦测试；
2. 完整 `scripts/check_site_sync_gateways.sh`，最终输出 `SiteSyncGateways checks passed`；
3. `git diff --check`；
4. SunSmart generic iPhoneOS Debug unsigned build；
5. Archipelago generic iPhoneOS Debug unsigned build；
6. SLG Sync Plus generic iPhoneOS Debug unsigned build；
7. SylSmart generic iPhoneOS Debug unsigned build。

四个 target 均输出 `BUILD SUCCEEDED`。构建直接使用 `xcodebuild`，目标为 `generic/platform=iOS`，未使用 Simulator、shell 包装或日志重定向。

## 改动边界

本次业务改动仅包含 Parser 的一个兼容分支和对应回归测试。未修改：

- `SunSmart.xcodeproj/project.pbxproj` 中已有的其他改动；
- `SLG Sync Plus.xcscheme` 中已有的 Debug 配置改动；
- Site timezone 保存和上传顺序；
- Gateway target 构造、权限与 Gateway 列表；
- 网络请求路径和参数；
- 3 秒轮询及 60 秒超时；
- 用户可见文案、本地化、资源、target 配置或依赖。

## 尚未完成的真实环境验收

自动化检查与四 target 构建不能证明服务器和真实 Gateway 的端到端行为。仍建议在 SLG Sync Plus 真机环境复验：

1. Edit Site 修改 timezone；
2. request status 返回 `SUCCEEDED`；
3. 对应行立即由 `Pushing...` 更新为 `Synced`；
4. 已成功 Gateway 不再继续轮询；
5. 多 Gateway 场景中，成功项和仍在处理的项可独立更新。

其余三个品牌 target 共享已修复代码并已通过构建，但仍未逐一完成真实服务器/Gateway 验收。

