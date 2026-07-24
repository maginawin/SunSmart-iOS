# Gateway 关联变化后立即刷新 Site 实施总结

## 结果

- Gateway 关联拓扑发生服务器确认的完整或部分变化后，Site 会立即请求一次 `siteInfo`。
- 如果 Site 不在 window 或手机无网络，保留生命周期刷新标记。
- 返回 All Spaces 与 Favourites 后，不再依赖下拉刷新才能显示最新关联和 online 状态。
- Space 关联及 Internet online/offline 仍完全使用服务器状态，不增加本地推断。

## 验证

- Site Gateway 状态契约测试：通过。
- `git diff --check`：通过。
- SunSmart generic iPhoneOS Debug：构建成功。
- Archipelago generic iPhoneOS Debug：构建成功。
- SLG Sync Plus generic iPhoneOS Debug：构建成功。
- SylSmart generic iPhoneOS Debug：构建成功。

## 待真实环境验收

- Wi‑Fi Gateway 修改 Spaces 关联并保存，关闭 Gateway 页面后确认 All Spaces 与 Favourites 无需下拉刷新。
- 4G Gateway 执行相同流程。
- bind/unbind 部分成功时，确认 Site 展示服务器最终拓扑。
- 手机无网络时保存失败或无法刷新，恢复网络后通过现有生命周期或下拉刷新取得权威状态。

构建成功不代表 modal 生命周期、真实服务器数据传播或真机 Gateway 行为已经验收。
