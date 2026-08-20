# SLG Sync Plus Space 内容消失复现方案

## 1. 目标

通过控制 Site 详情请求和 Space 详情请求的完成顺序，将偶发的全局 Mesh 上下文竞态转换为可重复验证的场景。

本方案不修改业务代码。若无代码方案仍无法稳定复现，再考虑增加仅 DEBUG 生效的延时和诊断开关。

## 2. 首选复现方法：关闭 Gateway 详情后立即进入 Space

### 前置条件

- Site 已上传云端；
- Site 内存在可进入的 Gateway 详情页；
- `Space1` 内至少有一个产品、一个场景或一个定时，便于观察；
- 手机网络可用；
- 建议先等待 Site 首次加载完成，排除首次加载 HUD 的干扰。

### 操作步骤

1. 进入目标 Site，等待页面和 Gateway 状态加载完成。
2. 打开任一 Gateway 详情页。
3. 不需要修改 Gateway，直接关闭 Gateway 详情页返回 Site。
4. 返回 Site 后立即点击进入 `Space1`，尽量控制在 0.2 至 1 秒内。
5. 看到产品后，立即依次切换 Products、Scenes、Timed 页面，促使各子页面执行 `viewWillAppear` 和数据源刷新。
6. 每轮退出 `Space1` 后重复步骤 2 至 5，建议连续执行 10 至 20 轮。

### 为什么该方法更容易触发

关闭 Gateway 详情会调用 `finishGatewayDetailPresentation(...)`，随后启动 `performSiteLoad(presentation: .silentGatewayReconcile)`：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:880-888`

该刷新模式不显示加载 HUD，因此 Site 页面仍可操作。用户可以在 Site 请求尚未完成时进入 `Space1`。当旧 Site 请求稍后完成，当前代码会发现全局 Network Key 不是 Primary，并将 Mesh 上下文切回 Site 主网：

- `SunSmart/Main/Site/Controller/SiteViewController.swift:598-600`

这比首次进入 Site 的交互式加载更容易制造“先进入 Space，旧 Site 响应后返回”的顺序。

## 3. 最稳定方法：代理工具只延迟 Site 响应

可以使用 Charles 或 Proxyman 对响应设置断点，但只控制时序，不修改响应内容。

### 操作步骤

1. 只对 `/sitespace/get/siteprops` 的响应设置断点或延迟 3 至 5 秒。
2. 不要延迟 `/sitespace/get/spaceprops`。
3. 先完成 Site 首次加载。
4. 打开并关闭 Gateway 详情页，触发静默 `/siteprops` 请求。
5. 当代理工具截住该 `/siteprops` 响应时，App 的 Site 页面应仍可操作。
6. 立即点击进入 `Space1`，让 `/spaceprops` 正常返回。
7. 等待产品、场景或定时显示正常。
8. 在代理工具中放行之前被截住的 `/siteprops` 响应。
9. 回到 App 观察列表是否在放行响应后消失，并切换 Scenes、Timed 页面确认。

如果每次放行 `/siteprops` 后都出现数据消失，这将形成接近确定性的竞态证据。

### 注意事项

- 只延迟响应，不要把 `nodes`、`scenes`、`schedules` 改为空数组；当前导入逻辑可能真实覆盖本地数据。
- 不要记录或导出 NetKey、AppKey、密码、Token 等授权信息。
- 如果 HTTPS 代理无法解密，可采用 DEBUG 延时方案，不要降低正式包的网络安全配置。

## 4. 无代理工具的网络放大方法

### 方法 A：弱网环境

在 Network Link Conditioner、Charles Throttling 或测试路由器中选择高延迟网络，建议先尝试：

- 延迟 800 至 1500 ms；
- 带宽 1 至 3 Mbps；
- 丢包先保持 0%，避免请求直接失败。

然后重复“关闭 Gateway 详情后立即进入 `Space1`”。高延迟会扩大两个请求完成顺序交错的时间窗口。

### 方法 B：使用数据量较大的 Site

优先选择以下测试数据：

- Site 包含多个 Space；
- 每个 Space 有较多 Node、Group、Scene、Schedule；
- Site 有 Gateway 数据。

`SiteData.update(...)` 会并发导入所有 Space。数据量越大，Site 导入越可能在 `Space1` 已进入后才执行到全局网络切换。

### 方法 C：重复快速路径

按以下固定节奏循环：

1. Site → Gateway Detail；
2. 关闭 Gateway Detail；
3. 立即进入 `Space1`；
4. Products → Scenes → Timed；
5. 返回 Site。

建议录屏并记录每轮时间，连续执行 20 至 50 轮。不要在每轮之间等待 Site 静默刷新完成。

## 5. 次选复现入口

### 5.1 首次进入 Site 后快速进入 Space

1. 强制关闭 App 后重新启动。
2. 进入目标 Site。
3. Site 卡片出现后立即点击 `Space1`。
4. 进入后快速切换 Products、Scenes、Timed。

该方法受 HUD 挂载时机和首次请求速度影响，因此稳定性低于 Gateway 静默刷新入口。

### 5.2 完成 Gateway 或时区相关流程后快速进入 Space

当前源码还有多处会触发 Site 刷新：

- Gateway 详情关闭后的静默刷新；
- Edit Site 时区同步结果后的静默刷新；
- Gateway 关联关系变化后的 Site 刷新；
- Gateway 添加完成后的 Site 刷新。

其中优先使用“不修改数据、直接关闭 Gateway 详情”的方法，副作用最小。涉及修改时区、Gateway 关联或添加 Gateway 的方法应只在专用测试数据上使用。

## 6. Xcode 断点确认方法

如果现象仍未出现，可以在以下位置设置断点：

- `SiteViewController.swift:598`：Site 导入完成后准备切回 Primary 网络；
- `SpaceViewController.swift:673`：进入 Space 时准备切换到 Space 子网；
- SDK `MeshLibManager.swift:183`：所有 `setMeshNetworkConnected(...)` 调用入口。

重点观察：

- 命中 `SiteViewController.swift:598` 时，导航栈顶是否已经是 `SpaceViewController`；
- 当前 `currentNetworkKey.networkId` 是否等于 `Space1.meshNetworkId`；
- 条件中的 `!currentNetworkKey.isPrimary` 是否为真；
- 单步执行网络切换后，`currentNetworkKey.isPrimary` 是否变为真。

如果在 Space 页面显示期间命中该断点，继续执行后列表消失，即使手工测试不稳定，也足以确认竞态执行链。

## 7. DEBUG 延时注入方案

如果需要稳定自动化复现，建议后续单独增加一个仅 DEBUG 生效、由 Launch Argument 控制的测试开关：

1. 只对 `.silentGatewayReconcile` 的 Site 响应生效；
2. 在 `site.update(...)` 完成后、切换 Primary 网络前异步延迟 3 至 5 秒；
3. 延迟期间允许进入 `Space1`；
4. 同时打印请求编号、页面栈顶、目标/当前 Network ID 和数量快照；
5. Release 配置不编译或不开启该行为。

该方案不应直接写死延时，也不应改变服务器响应。实现前需要单独确认修改范围。

## 8. 复现成功判据

满足以下条件可判定复现成功：

1. `Space1` 首次加载时产品、场景或定时数量正确；
2. 随后出现来自 Site 刷新完成路径的 Primary 网络切换；
3. 切换后全局 `currentNetworkKey` 不再等于 `Space1.meshNetworkId`；
4. Products、Scenes、Timed 随后读取到空或错误数据；
5. 重新进入 `Space1` 后切回正确子网并恢复。

仅看到 UI 变空但没有 Network ID 变化，不能直接判定为同一根因，还需要继续检查 `/siteprops`、`/spaceprops` 的数组数量和 `updateTimestamp`。

## 9. 推荐执行顺序

1. 先执行“Gateway Detail 关闭后立即进入 Space”，重复 10 至 20 次。
2. 未复现时增加弱网延迟，丢包保持为 0%。
3. 仍未复现时，用代理工具精确截住并延迟 `/siteprops` 响应。
4. 代理条件不允许时，用 Xcode 断点确认 `SiteViewController.swift:598` 是否在 Space 可见时命中。
5. 最后再评估增加可开关的 DEBUG 延时注入。

