# Site Gateway Online 状态修复总结

## 结果

已按方案 B 完成 Wi‑Fi 与 4G Gateway 的 Site online/offline 状态真值分离。

- `SpaceData.gatewayStatus` 保持为服务器 `siteInfo` 导入的权威状态。
- `SiteViewController.setupData()` 不再用当前 Mesh 节点解析结果反向覆盖 Space 状态。
- Gateway 运行期对象显式从 Site 主网解析，不再依赖进入 Space 后残留的当前子网上下文。
- All Spaces 与 Favourites 共用服务器状态驱动的 Internet 状态区域可见性规则。
- 绑定或解绑在服务器发生完整或部分成功后，会标记 Site 在返回时执行一次权威 `siteInfo` 刷新。
- 普通 Gateway 数据更新不会清除已经安排的服务器刷新。

## Online / Offline 判定边界

- Site 的 `Internet Online`、`Internet Offline` 与 Space 右上角 online 图标：使用服务器返回的 `SpaceData.gatewayStatus`。
- Gateway 列表的运行期展示：由同一 Space 服务器状态单向映射到 `Gateway.connectStatus`。
- Mesh `Node.state`：只表示当前 Mesh 节点可达性。
- Wi‑Fi RSSI、Wi‑Fi `networkStatus`、4G `csqRssi`：只表示各自的信号或网络诊断状态。
- 后三类本地状态不参与 Site Internet online/offline 计数。

## 自动化与构建验证

- `scripts/check_site_gateway_online_state.sh`：通过。
- `git diff --check`：通过。
- SunSmart generic iPhoneOS Debug：构建成功。
- Archipelago generic iPhoneOS Debug：构建成功。
- SLG Sync Plus generic iPhoneOS Debug：构建成功。
- SylSmart generic iPhoneOS Debug：构建成功。

## 待验收

### 真机

- Wi‑Fi Gateway：All Spaces 与 Favourites 中进入关联 Space、连接设备、返回 Site 后，online 计数和绿色图标保持正确。
- 4G Gateway：执行同样流程并确认行为一致。

### 真实服务器

- Gateway 真正 online/offline 后，`siteInfo` 返回状态与 App 展示一致。
- 绑定、解绑发生完整成功或部分成功后，返回 Site 能取得最新服务器拓扑和状态。
- 删除 Gateway 后，`siteInfo` 返回的关联关系与 Site 展示一致。

构建成功只证明代码能够在四个品牌 target 中完成静态集成，不代表 BLE、Wi‑Fi、4G 或服务器往返已经通过真实环境验收。
