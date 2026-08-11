# Edit Site 弹窗退出时序优化设计

## 1. 背景

Edit Site 在提交 Time Zone 变更时会展示两类自定义弹窗：

- 在线状态：展示更新 Time Zone 的确认弹窗；
- 离线状态：展示离线保存提示弹窗。

用户在弹窗中确认后，当前实现会立即保存 Site 属性并开始退出 Edit Site。由于弹窗关闭动画尚未完成，弹窗动画、Edit Site modal 关闭动画以及部分入口下的 Site 详情页返回动画可能发生重叠，造成弹窗像是随页面一起被带走，交互显得生硬。

本设计采用已确认的方案 A：为共享 `SRAlertView` 增加向后兼容的“弹窗完全关闭后再执行业务 action”能力，并仅在 Edit Site 的两个 Time Zone 退出 action 中启用。

## 2. 目标

1. 用户在 Edit Site 的 Time Zone 弹窗中确认退出时，必须先完整关闭弹窗，再开始保存和页面退出。
2. 保持当前 Site 属性保存、pending、服务器提交、状态卡和 Toast 规则不变。
3. 保持 `SRAlertView` 其他现有调用点的 action 执行顺序不变。
4. 同时覆盖从 Sites 页面和 Site 详情页进入 Edit Site 的返回路径。
5. 防止关闭动画期间重复触发 action 或重复提交。

## 3. 非目标

- 不改变 Edit Site 的视觉布局、弹窗文案或动画样式。
- 不改变普通 Site name/imageId 更新流程。
- 不改变 Time Zone 的 API、timestamp、pending mask、响应校验或同步状态卡。
- 不统一改造所有弹窗或所有页面的退出时序。
- 不修改 `NordicSigMeshSDK`、Mesh、Gateway 或服务器协议。
- 不新增本地化 Key、资源或依赖。

## 4. 当前源码依据与根因

### 4.1 Edit Site 的两个弹窗

`SunSmart/Main/Site/Controller/SiteEditViewController.swift` 中：

- `showTimeZoneConfirmation()` 的确认 action 直接调用 `performCommit(online: true)`；
- `showOfflineTimeZoneAlert()` 的 `Got it` action 直接调用 `performCommit(online: false)`；
- `performCommit` 本地持久化成功后通过 `returnToSitesHandler` 开始返回 Sites。

### 4.2 SRAlertView 当前按钮时序

`SunSmart/Common/View/SRAlertView.swift` 中，`firstBtnClick()` 和 `secondBtnClick()` 当前顺序均为：

1. 调用 `action.actionHandler`；
2. 当 `action.closeAlert == true` 时调用 `dismiss(animation:)`。

因此，Edit Site 的 `performCommit` 和路由退出先发生，弹窗关闭动画后发生。这是转场重叠的直接原因。

### 4.3 现有组件模式

`SunSmart/Common/View/MenuPopView.swift` 已具备以下能力：

- `dismiss(animation:completion:)`；
- `MenuItem.performsActionAfterDismiss`；
- opt-in 时先完成菜单关闭，再执行 item action。

本设计在 `SRAlertView` 中沿用相同语义，降低新 API 的理解成本，同时不改变默认行为。

### 4.4 返回 Sites 的既有时序

当前两个 Edit Site 入口已经分别负责最终路由：

- `SitesViewController` 入口：关闭 Edit Site modal 后停留 Sites；
- `SiteViewController` 入口：关闭 Edit Site modal，再 pop Site 详情页，并等待导航 transition 完成。

本次只在这段既有路由之前增加“等待弹窗关闭完成”，不改写两个入口的路由职责。

## 5. 方案比较

### 5.1 方案 A：SRAlertAction 可选延后执行，推荐

为 `SRAlertView.dismiss` 增加 completion，为 `SRAlertAction` 增加默认关闭的延后执行选项。只有明确启用的 action 才在弹窗移除后执行 handler。

优点：

- 依赖真实动画完成回调，不依赖猜测时间；
- 默认行为保持不变，影响范围可控；
- API 语义与 `MenuPopView` 现有模式一致；
- 后续其他确有同类需求的弹窗可以显式复用。

代价：

- 需要修改共享弹窗组件，因此必须验证所有四个品牌 target；
- 需要明确 `closeAlert == false` 时延后选项不生效。

### 5.2 方案 B：Edit Site 固定延时后退出，不采用

在 action 中按当前动画时长延迟执行 `performCommit`。

问题：动画时长调整、系统负载或主线程阻塞都可能让固定延时失真，无法形成“弹窗已经移除”的可靠契约。

### 5.3 方案 C：全局改为所有 SRAlertView 先关闭再回调，不采用

直接交换所有 action handler 与 dismiss 的执行顺序。

问题：会改变大量现有弹窗行为，输入框校验、权限跳转、连续弹窗等流程可能依赖当前时序，回归范围与本需求不匹配。

## 6. 推荐设计

### 6.1 SRAlertView 关闭完成契约

扩展 `dismiss`，支持可选 completion，并保证：

- 有动画时：完成现有 dismiss 过渡、执行 `removeFromSuperview()` 后调用 completion；
- 无动画时：先执行 `removeFromSuperview()`，再同步调用 completion；
- completion 每次关闭最多执行一次；
- 调用 dismiss 时继续立即设置 `isDismiss = true`，阻止动画期间重复点击。

本次不调整既有动画参数、缩放方式或遮罩透明度。

### 6.2 SRAlertAction opt-in 语义

为 `SRAlertAction` 增加 `performsActionAfterDismiss`，默认值为 `false`。

行为规则：

| closeAlert | performsActionAfterDismiss | 行为 |
|---|---|---|
| true | false | 保持现状：先执行 handler，再关闭弹窗 |
| true | true | 新能力：先关闭并移除弹窗，再执行 handler |
| false | false | 只执行 handler，不关闭弹窗 |
| false | true | 不存在可等待的关闭过程，仍立即执行 handler；调用方不应组合使用这两个值 |

不把全局默认值改为 `true`，确保现有调用点无需修改且行为不变。

### 6.3 按钮事件路由

`firstBtnClick()` 与 `secondBtnClick()` 必须使用相同规则处理 action，避免左右按钮产生不一致的时序。

对 opt-in action：

1. 当前点击通过 `isDismiss` 防重检查；
2. 调用带 completion 的 dismiss；
3. dismiss 立即进入不可再次响应状态；
4. 完成现有 dismiss 过渡并从 window 移除弹窗；
5. 在 completion 中执行原 action handler。

非 opt-in action 继续沿用当前顺序。输入框的 `inputDoneBack` 既有行为不在本次修改范围内；Edit Site 两个目标弹窗均不包含输入框。

### 6.4 Edit Site 接入范围

仅为以下两个 action 设置 `performsActionAfterDismiss = true`：

1. 在线确认弹窗的 `Update Time Zone`；
2. 离线提示弹窗的 `Got it`。

以下交互保持不变：

- 在线确认弹窗的 Cancel；
- 点击弹窗遮罩关闭；
- Edit Site 导航栏 Close；
- 无变化时直接关闭 Edit Site；
- 普通 name/imageId 的 Done；
- Time Zone Selection 页的 push/pop 和下拉关闭保护。

## 7. 完整交互时序

### 7.1 在线 Time Zone 更新

1. 用户点击 `Update Time Zone`；
2. `SRAlertView` 阻止重复点击并播放关闭动画；
3. 弹窗从 window 移除；
4. 执行 `performCommit(online: true)`；
5. 本地持久化成功后开始返回 Sites；
6. Sites 入口等待 Edit Site modal dismiss 完成；Site 详情入口还需等待详情页 pop transition 完成；
7. 展示 Time Zone saving 状态卡并提交服务器；
8. 根据经过完整响应校验的结果更新为 success 或 failure。

### 7.2 离线 Time Zone 保存

1. 用户点击 `Got it`；
2. 弹窗完整关闭并从 window 移除；
3. 执行 `performCommit(online: false)`；
4. 本地保存 Time Zone 与 pending；
5. 返回 Sites；
6. 不发送网络请求，也不展示 saving 状态卡。

### 7.3 本地持久化失败

1. 弹窗先正常关闭；
2. `coordinator.persist` 返回失败；
3. `isCommitting` 恢复为 `false`；
4. 停留在 Edit Site 并展示现有失败 HUD；
5. 用户可再次点击 Done 重试。

该行为比当前更清晰：失败 HUD 不会叠在仍处于关闭动画的弹窗上。

## 8. 异常与边界处理

- 快速重复点击：`isDismiss` 在 dismiss 开始时已置为 true，第二次点击不再执行。
- 动画关闭：completion 必须以视图已经移除为前置条件。
- 无动画关闭：移除与 completion 在同一主线程调用栈按顺序执行。
- action handler 中控制器释放：Edit Site action 使用弱引用；若控制器已释放，则不再提交或路由。
- Cancel/遮罩关闭：只关闭弹窗，不保存、不退出 Edit Site。
- 本地保存失败：停留 Edit Site，不触发 `returnToSitesHandler`。
- 服务器失败：仍按现有状态卡规则显示 failure，不回退到 Edit Site。
- iPad：Edit Site modal 尺寸和 dismiss 路由保持现状，新顺序同样适用。

## 9. 文件范围

计划修改：

- `SunSmart/Common/View/SRAlertView.swift`
  - 增加 dismiss completion；
  - 增加 action 延后执行选项；
  - 统一左右按钮的 opt-in action 路由。
- `SunSmart/Main/Site/Controller/SiteEditViewController.swift`
  - 仅为两个 Time Zone 确认 action 启用新选项。
- `Tests/Site/SiteEditAlertTransitionContractTests.swift`
  - 新增聚焦时序契约测试。

不修改：

- `SitesViewController.swift` 和 `SiteViewController.swift` 的返回路由；
- Site 数据模型、Coordinator、API、本地化、资源和 target 配置；
- SDK 仓库。

## 10. 测试设计

### 10.1 RED→GREEN 聚焦契约

新增独立契约测试，先验证旧实现缺少目标能力而失败，再完成最小实现。检查内容：

- `SRAlertView.dismiss` 提供 completion；
- 动画和无动画分支都先移除弹窗，再调用 completion；
- `SRAlertAction.performsActionAfterDismiss` 默认值为 false；
- opt-in 且会关闭的 action 把 handler 放在 dismiss completion 中；
- 非 opt-in action 保留 handler 先于 dismiss 的行为；
- `firstBtnClick()`、`secondBtnClick()` 使用相同的 action 时序规则；
- Edit Site 在线确认和离线 `Got it` 两个 action 显式启用；
- Cancel action 不启用、不提交。

### 10.2 现有回归契约

继续执行：

- `SiteTimeZoneUIContractTests` 完整 UI 路由与本地化/target 契约；
- `SiteUpdateToastUIContractTests` component 与 routing 契约；
- Site 属性 policy、persistence 与 API 聚焦测试。

### 10.3 静态与构建验证

- `git diff --check`；
- generic iPhoneOS Debug、关闭签名构建 `SunSmart`；
- 同样构建 `Archipelago`；
- 同样构建 `SLG Sync Plus`；
- 同样构建 `SylSmart`。

共享 `SRAlertView.swift` 被多个品牌 target 使用，因此四个 target 均需要验证。构建成功只证明源码、依赖和 target 集成有效，不替代交互验收。

### 10.4 真机交互验收

至少覆盖以下路径：

| 入口 | 网络 | 操作 | 期望 |
|---|---|---|---|
| Sites | 在线 | Update Time Zone | 弹窗完全消失后 Edit Site 才退出，随后出现 saving 状态卡 |
| Site 详情 | 在线 | Update Time Zone | 弹窗消失后依次完成 modal dismiss 和详情页 pop，无重叠转场 |
| Sites | 离线 | Got it | 弹窗消失后退出，pending 保留，不出现 saving 状态卡 |
| Site 详情 | 离线 | Got it | 弹窗消失后再执行两段返回动画，无生硬叠加 |
| 任一入口 | 在线 | Cancel | 只关闭弹窗，仍停留 Edit Site，不提交 |
| 任一入口 | 任意 | 快速连续点击确认 | 仅保存和退出一次 |
| 任一入口 | 任意 | 模拟本地保存失败 | 弹窗先关闭，停留 Edit Site 并显示失败 HUD |

## 11. 验收标准

1. 两个目标弹窗都已从 window 移除后，才允许调用 `performCommit`。
2. Edit Site 与弹窗关闭动画不重叠。
3. 从 Site 详情进入时，弹窗关闭、Edit Site modal 关闭、详情页 pop 三段动画严格串行。
4. 其他 `SRAlertView` action 默认顺序无变化。
5. Site 的本地保存、pending、服务器提交和最终状态提示语义无变化。
6. 聚焦契约、既有回归契约、`git diff --check` 和四品牌 generic iPhoneOS 构建通过。
7. 最终完成报告明确区分自动化/构建证据与真机交互验收结果。
