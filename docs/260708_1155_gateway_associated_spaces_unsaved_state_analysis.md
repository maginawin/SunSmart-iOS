# Gateway Associated Spaces 未保存状态分析与方案

## 结论

问题真实存在，且同时影响 4G Gateway 与 WiFi Gateway。

原因不是 WiFi Gateway 独有逻辑，而是两个页面共用的 `GatewayViewController` / `GatewayAssociatedSpacesController` 交互模型：进入 Associated Spaces 子页后，选择页在用户点击底部确认按钮时已经直接调用云端绑定/解绑接口、修改 `GatewayModel.associatedSpaces`、写本地数据库，并通过通知触发 gateway 云同步。外层 Gateway 页面底部 `SAVE` 只负责后续设备侧 SIG Mesh 配置同步和部分页面配置保存，已经不是 associated spaces 的唯一提交点。

因此，用户在 Associated Spaces 子页改完选择后，回到 Gateway 页面即使不点击 `SAVE`，再退出页面，下一次进入仍会展示刚才未通过外层 `SAVE` 确认的 spaces 列表。

## 代码事实

- `SiteViewController.gatewayOperationClickAction` 按 `gateway.node.isWiFiGateway` 分流：WiFi Gateway 进入 `WiFiGatewayViewController`，其他 Gateway 进入 `GatewayViewController`。
- `WiFiGatewayViewController` 继承 `GatewayViewController`，没有重写 Associated Spaces 入口，因此 Associated Spaces 逻辑是共享逻辑。
- `GatewayViewController.associatedSpaces()` 将当前 `gatewayModel` 直接传给 `GatewayAssociatedSpacesController`。
- `GatewayAssociatedSpacesController.addSelectedBtnAction()` 比较选择前后的 spaces，存在变化时调用 `spacesAssociatedHandle(...)`。
- `spacesAssociatedHandle(...)` 会直接调用：
  - `gatewayBindSpace`
  - `gatewayUnbindSpace`
- 绑定/解绑成功后，`GatewayAssociatedSpacesController` 会直接修改 `self.gateway.associatedSpaces`，随后调用 `self.gateway.save()`。
- 子页成功后回调外层页面，外层页面仅刷新 UI、更新 Save 状态，并发送：
  - `siteGatewayDataChangedNotificaitonName`
  - `SiteStateChangeNotificationName`
- `SiteViewController` 收到 `siteGatewayDataChangedNotificaitonName` 后，会更新 `gateway.model.lastUpdate`、保存本地 DB，并添加 `CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncGateway(...))`。
- `CloudSynchronizationManager.syncGateway` 上传 `gateway.export()`，其中 `GatewayModel.export()` 会把 `associatedSpaces` 放入 `gatewayPreconfigured.associatedSpaces`。
- 外层 `GatewayViewController.saveBtnAction()` 才会把 `setGatewayModel.associatedSpaces = gateway.associatedSpaces`，并通过 `node.getNodeSyncGatewayData(gateway:)` 进入 `SyncDevicesViewController` 做设备侧 subnet/appkey 绑定或解绑同步。

## 实际时序

当前实际时序如下：

1. 用户进入 Gateway 页面。
2. 页面加载云端已绑定 spaces，并写入 `gatewayModel.associatedSpaces` 和 `setGatewayModel.associatedSpaces`。
3. 用户点击 Associated Spaces 的 `Add +`。
4. 用户在 Associated Spaces 子页选择或取消选择 spaces。
5. 用户点击子页底部确认按钮。
6. 子页立即请求云端绑定/解绑。
7. 子页立即修改当前 `GatewayModel.associatedSpaces` 并保存到本地数据库。
8. 外层 Gateway 页面收到回调后刷新列表。
9. Site 页收到 gateway changed 通知后立即排队云同步。
10. 用户不点击 Gateway 页面底部 `SAVE`，直接退出。
11. 下次进入 Gateway 页面时，页面会从云端或本地已变更模型读到新的 associated spaces。

这解释了用户描述的现象。

## 对预期的判断

用户提出的预期符合常理，也更符合当前页面整体交互。

理由：

- Gateway 页面底部存在明确的 `SAVE` 按钮，用户自然会理解为页面级配置的提交边界。
- 关闭 Gateway 页面时已有未保存变更确认逻辑，说明该页面本身支持“编辑态”和“已保存态”的区分。
- Associated Spaces 会影响设备侧 subnet/appkey 绑定关系，不只是纯云端展示数据；如果子页提前写云、本地，但外层 `SAVE` 未触发设备同步，会造成云端/本地认为已关联，设备侧可能尚未完成绑定或解绑。
- 预期中“仅 SAVE 成功后才持久化和同步到云”能把 UI、本地 DB、云端和设备侧同步放到同一个提交边界，行为更一致。

需要注意一个产品语义点：当前子页底部按钮本身也像一个“确认选择”动作。如果保留该按钮，就应把它定义为“确认本次编辑并返回 Gateway 页面”，而不是最终持久化。最终持久化仍由 Gateway 页面 `SAVE` 负责。

## 推荐方案

推荐改成“子页只编辑草稿，外层 SAVE 统一提交”。

核心设计：

1. Associated Spaces 子页不再直接调用 `gatewayBindSpace` / `gatewayUnbindSpace`。
2. 子页不再直接调用 `gateway.save()`。
3. 子页以进入时的已绑定 spaces 作为初始选择，只维护本次选择草稿。
4. 子页点击底部确认按钮后，仅把草稿列表通过 callback 返回外层 Gateway 页面。
5. 外层 Gateway 页面收到草稿后，只更新一个待保存模型，例如 `setGatewayModel.associatedSpaces`，并刷新列表和 `SAVE` 状态。
6. Gateway 页面展示 Associated Spaces 时优先展示待保存模型，而不是直接展示已持久化的 `gateway.associatedSpaces`。
7. 用户点击 `SAVE` 后，再统一：
   - 计算新增绑定 spaces。
   - 计算解除绑定 spaces。
   - 调用云端 `gatewayBindSpace` / `gatewayUnbindSpace`。
   - 只有云端绑定/解绑成功后，才把草稿写入 `gatewayModel.associatedSpaces` 并保存本地 DB。
   - 继续走现有 `node.getNodeSyncGatewayData(gateway:)` / `SyncDevicesViewController` 设备侧同步。
   - 成功后发送 gateway changed 通知，让云端 gateway preconfigured 数据同步到最终状态。
8. 用户退出 Gateway 页面且未 SAVE 时，不写 DB、不调云端绑定/解绑、不发送 gateway changed 通知。下次进入仍显示保存前状态。

## 备选方案

### 方案 A：只在退出时回滚本地列表

做法：保留子页立即绑定/解绑云端，只在外层 Gateway 页面未 SAVE 退出时，把本地 `associatedSpaces` 回滚为进入页面前的列表。

不推荐。因为云端绑定/解绑已经发生，回滚本地只会制造本地与云端不一致；下次进入页面又会被云端列表覆盖回来。

### 方案 B：子页继续立即提交，并移除外层 SAVE 对 Associated Spaces 的语义

做法：把 Associated Spaces 明确定义为即时提交项，选择页成功后就认为已保存，同时外层 SAVE 只处理设备侧同步。

不推荐。这个方案需要重新解释 UI 语义，并且仍存在云端已变、设备侧未同步的窗口期。除非产品明确接受“Associated Spaces 是即时云端提交操作”，否则不应采用。

### 方案 C：子页草稿 + 外层 SAVE 统一提交

推荐。它匹配用户预期，也能把云端、本地 DB、页面展示和设备侧同步收敛到同一个保存边界。

## 影响范围

- 影响共享 `GatewayViewController`，因此会同时影响 4G Gateway 与 WiFi Gateway。
- `WiFiGatewayViewController` 不需要单独复制 Associated Spaces 逻辑。
- 需要核查以下入口：
  - Associated Spaces 子页选择和取消选择。
  - Gateway 页面列表展示。
  - Gateway 页面底部 `SAVE`。
  - Gateway 页面关闭/返回时的未保存提示。
  - 单行删除 associated space 的行为。
  - Site 页 gateway changed 通知和 cloud sync 触发时机。

## 开发计划

1. 调整 Associated Spaces 子页职责：移除即时 bind/unbind 请求和即时本地保存，只返回选择结果。
2. 在 Gateway 页面引入“待保存 associated spaces”展示源，让列表、数量和保存按钮都基于待保存模型刷新。
3. 将云端绑定/解绑请求移动到 `saveBtnAction()` 的保存流程中，并按新增/删除差异执行。
4. 云端请求全部成功后，再更新 `gatewayModel.associatedSpaces`、本地 DB、gateway changed 通知和设备侧同步。
5. 处理失败分支：如果云端绑定/解绑失败，不写本地最终模型，不触发设备侧同步，并保留 Gateway 页面编辑态让用户可以重试或退出。
6. 单行删除 associated space 也改为草稿删除，不再即时调用 `gatewayUnbindSpace`。
7. 验证 4G Gateway 与 WiFi Gateway 两条入口行为一致。

## 验证计划

手工验证：

1. 进入 4G Gateway，修改 Associated Spaces，回到 Gateway 页面，不点 `SAVE` 直接退出，再次进入应显示修改前列表。
2. 进入 WiFi Gateway，执行同样步骤，应显示修改前列表。
3. 进入 4G Gateway，修改 Associated Spaces 后点击 `SAVE`，保存成功后再次进入应显示新列表。
4. 进入 WiFi Gateway，执行同样步骤，应显示新列表。
5. 修改 Associated Spaces 后直接关闭页面，应出现未保存提示；确认退出后不应持久化。
6. 云端 bind/unbind 失败时，本地 DB 和展示状态不应被错误提交。
7. 保存成功后，设备侧仍应进入现有 subnet/appkey 同步链路。

构建验证：

- 使用 iPhoneOS `xcodebuild` 验证 `SunSmart` target。
- 如修改共享逻辑影响品牌 target，再同步检查 `Archipelago`、`SLG Sync Plus`、`SylSmart` 是否受影响。

## 实施记录

已按推荐方案实施：

1. `GatewayAssociatedSpacesController` 不再调用 `gatewayBindSpace` / `gatewayUnbindSpace`，也不再直接保存 `GatewayModel`。
2. Associated Spaces 子页只维护选择草稿，点击底部确认后把 `selectSpaces` 回传给 Gateway 页面。
3. `GatewayViewController` 使用 `setGatewayModel.associatedSpaces` 作为 Associated Spaces 的草稿展示源。
4. Associated Spaces 子页回传后，只更新 `setGatewayModel.associatedSpaces`、刷新列表和 Save 状态，不发送 gateway changed 通知。
5. Associated Spaces 单行删除改为草稿删除，不再即时调用云端解绑。
6. `GatewayViewController.saveBtnAction()` 在真正保存时计算新增/移除 spaces，统一调用云端 bind/unbind；全部成功后才把草稿写入本地 `gatewayModel`，并继续走既有设备侧同步链路。
7. 新增 `scripts/check_gateway_associated_spaces_deferred_save.sh` 作为静态回归检查，防止子页重新引入即时提交。

已执行验证：

- `bash scripts/check_gateway_associated_spaces_deferred_save.sh`
- `bash scripts/check_wifi_gateway_network_connectivity.sh`
- `bash scripts/check_gateway_activate_header_layout.sh`
- `git diff --check`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
