# Gateway 关联变化后立即刷新 Site 设计

## 背景

方案 B 已将 Site 的 Internet online/offline 状态收敛为服务器 `siteInfo` 真值，并在 Gateway 绑定或解绑 Space 成功后发出专用的关联拓扑变化通知。

当前通知监听只执行：

- 将 `SiteViewController.reloadData` 设为 `true`。
- 等待 Site 的下一次 `viewWillAppear` 再请求 `siteInfo`。

Gateway 页面通过 modal `NavigationViewController` 展示。使用系统自动选择的 page sheet 等展示方式时，底层 Site 页面可能始终保留在 window 中，关闭 Gateway 页面不会重新触发 Site 的 `viewWillAppear`。因此刷新标记虽然存在，却没有被消费；Site 继续显示旧的 Space 关联和 Internet 状态，直到用户下拉刷新。

## 目标

- Gateway 关联 Space 的服务器请求发生完整或部分成功后，立即请求一次 `siteInfo`。
- 用户关闭 Gateway 页面并返回 Site 时，展示服务器最新的关联关系和 online/offline 状态。
- 同时兼容 Site 仍在 window 中的 page sheet 场景，以及 Site 已离开 window 的 full-screen 或其他生命周期场景。
- 保持服务器状态为唯一真值，不直接猜测或改写 `SpaceData.gatewayStatus`。
- 不扩大普通 Gateway 名称、APN、服务器信息或设备同步变更的刷新范围。

## 非目标

- 不修改 Gateway bind/unbind API。
- 不修改 online/offline 的服务器字段和导入规则。
- 不直接根据 bind/unbind 的成功结果设置 Space online/offline。
- 不修改 Gateway 页面展示形式或关闭交互。
- 不增加加载文案、错误文案、资源、依赖或 target 配置。
- 不修改 Wi‑Fi、4G 或 NordicSigMeshSDK 协议。

## 方案对比

### 方案 A：拓扑通知触发 Site 立即刷新

Site 收到专用拓扑变化通知时：

1. 如果 Site 已加载、仍在 window 中且手机网络可用，立即调用一次 `loadSiteRequest()`。
2. 如果 Site 不在 window 中或手机无网络，保留 `reloadData = true`，由现有 `viewWillAppear` 路径补充刷新。

优点：

- 改动集中在 Site 的拓扑通知消费端。
- 不依赖 modal 是否触发页面生命周期。
- 完整成功和部分成功继续共用现有通知。
- 不需要修改多个 Gateway 页面关闭出口。

该方案为本次采用方案。

### 方案 B：Gateway 页面关闭后回调刷新

为 Gateway 页面增加关闭回调，并覆盖关闭按钮、导航返回和交互式 dismiss。

该方案没有采用，因为刷新行为会与多个页面退出路径耦合，并且需要额外处理服务器部分成功后用户继续停留在 Gateway 页面的状态。

### 方案 C：本地直接更新 Space

bind/unbind 成功后直接修改本地 Space 关联和状态。

该方案没有采用，因为 bind/unbind 结果只能确认关联变化，不能证明 Gateway 当前 Internet online/offline；这样会重新引入多套状态真值。

## 采用的设计

### 1. 收敛拓扑通知处理

在 `SiteViewController` 中增加一个仅处理 Gateway 关联拓扑变化的私有入口。NotificationCenter 监听只调用该入口，不再无条件只设置 `reloadData`。

该入口负责判断 Site 当前是否具备立即请求条件：

- `viewIfLoaded?.window != nil`：Site 已加载且仍附着在 window。
- `NetworkRequest.shared.networkable == true`：手机网络可发起请求。

满足条件时：

- 清除本次待刷新标记，避免关闭 modal 后重复请求。
- 立即调用现有 `loadSiteRequest()`。
- 继续由 `SiteData.update(siteJsonData:)` 导入新的 `gatewayId`、`gatewayOnline` 和 `gatewayLastupdate`。
- 请求成功后的现有 `setupData()` 负责刷新 All Spaces、Favourites、Internet 统计和 Space 图标。

不满足条件时：

- 设置 `reloadData = true`。
- 不做本地状态推断。
- 由 Site 的现有 `viewWillAppear` 路径执行补充请求。

### 2. 保持通知生产端不变

`GatewayViewController` 已在以下情况发出专用通知：

- bind/unbind 全部成功且拓扑发生变化。
- 前序请求成功、后续请求失败，服务器已发生部分拓扑变化。

本次不调整该生产端，避免重新改变已经验证的保存和错误处理语义。

关联集合未变化时不发通知，因此不会产生无意义的 `siteInfo` 请求。

### 3. 与普通 Gateway 更新隔离

`siteGatewayDataChangedNotificaitonName` 继续负责 Gateway 本地保存和云同步，不触发额外的 Site 权威刷新。

专用拓扑通知仍是唯一新增 `siteInfo` 请求来源。普通名称、APN、服务器信息、修复和设备同步操作保持现状。

## 数据流

### Site 仍在 window

1. Gateway bind/unbind 至少一次服务器成功。
2. Gateway 发出关联拓扑变化通知。
3. Site 收到通知并立即请求 `siteInfo`。
4. 服务器状态导入 `SiteData` 与 `SpaceData`。
5. `setupData()` 更新 All Spaces 和 Favourites。
6. 用户关闭 Gateway 页面时，Site 已具有最新状态，不需要下拉刷新。

### Site 不在 window

1. Gateway 发出关联拓扑变化通知。
2. Site 只保留 `reloadData = true`。
3. Site 下一次 `viewWillAppear` 请求 `siteInfo`。
4. 请求成功后按服务器状态刷新页面。

### 手机无网络

1. Site 收到拓扑变化通知。
2. 不立即发起失败概率确定的请求。
3. 保留 `reloadData = true` 和最后一次有效服务器状态。
4. Site 再次出现且网络恢复后，沿用现有生命周期刷新路径。

## 失败处理

- 立即 `siteInfo` 请求失败时，保留现有 Site 请求错误处理与最后一次有效服务器状态。
- 不使用 Gateway 本地关联列表推断 Internet online/offline。
- 用户仍可使用下拉刷新再次获取权威状态。
- 本次不新增自动重试、请求队列或去重基础设施。

## 影响文件

### 生产代码

- `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - 将拓扑通知从“仅设置刷新标记”改为“可见且有网络时立即请求，否则保留刷新标记”。

### 自动化验证

- `Tests/Site/SiteGatewayOnlineStateContractTests.swift`
  - 要求拓扑通知调用专用刷新入口。
  - 要求专用入口同时包含立即请求和延迟刷新两条路径。

- `scripts/check_site_gateway_online_state.sh`
  - 继续作为契约测试入口，无需改变用户可见行为。

### 不需要修改

- `GatewayViewController.swift` 的通知生产逻辑。
- `ImportData.swift`、`SpaceData.swift` 和 Space 图标映射。
- Wi‑Fi/4G Gateway 协议、资源、本地化、依赖和 target 配置。

## 测试策略

### TDD 契约

先扩展现有契约并在当前实现上确认失败，失败原因应为拓扑监听仍然只设置 `reloadData`，没有立即请求入口。

修复后要求契约确认：

- 拓扑通知调用专用刷新入口。
- Site 在 window 且手机有网络时调用 `loadSiteRequest()`。
- Site 不在 window 或无网络时设置 `reloadData = true`。
- 普通 Gateway 数据更新不会清除待执行的权威刷新。

### 静态与构建验证

- 运行 `scripts/check_site_gateway_online_state.sh`。
- 运行 `git diff --check`。
- 构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 generic iPhoneOS Debug scheme。

### 真机验收

Wi‑Fi 与 4G Gateway 分别验证：

1. 在 Gateway 页面改变关联 Spaces 并保存。
2. 不进行 Site 下拉刷新。
3. 关闭 Gateway 页面返回 All Spaces，确认关联关系、Internet Online 计数和 Space online 图标正确。
4. 切换到 Favourites，确认相同 Space 状态一致。

构建成功不代表 modal 生命周期、真实服务器数据传播或真机 Gateway 行为已经验收。
