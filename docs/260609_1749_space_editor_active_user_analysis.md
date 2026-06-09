# Space Editor Active User 问题分析

## 背景

场景：

- 手机 A 是 Site Owner。
- 手机 A 分享 Space 给手机 B。
- 手机 B 以 Editor 权限导入 Space。
- 手机 A 进入 Site - Space 后，再退出到 Sites 页面并停留。
- 手机 B 再进入同一 Site - Space 时，提示当前有人在编辑，只能以 Visitor 访问。

## 代码证据

客户端存在两套不同概念：

1. 成员权限：`SpaceData.permission`，例如 Owner、Editor、Visitor。
2. 当前会话编辑能力：`SpaceData.disableEditorPermission`，用于在发现其他 Owner/Editor 活跃时临时关闭本机编辑能力。

进入 `SpaceViewController` 时，如果当前 Space 是云端 Space：

- Visitor 直接启动心跳。
- Owner/Editor 先调用 `checkTheSpaceMembersRequest()` 查询当前活跃用户。

相关代码：

- `SunSmart/Main/Space/Controller/SpaceViewController.swift:233-240`
- `SunSmart/Main/Space/Controller/SpaceViewController.swift:705-735`

`checkTheSpaceMembersRequest()` 会请求 `/sitespace/get/activeuser`。如果 active users 里存在非当前用户的 Owner 或 Editor，就弹出 `space_permission_transition_message`，提示“当前有编辑者正在操作该空间，是否以访客身份进入？”。

确认后，客户端只执行：

- `space.disableEditorPermission = true`
- 发送 `spacePermissionChangedNotificaitonName`

它不会把 B 的云端成员权限从 Editor 改成 Visitor。

相关代码：

- `SunSmart/Main/Space/Controller/SpaceViewController.swift:724-728`
- `SunSmart/Main/Space/Controller/SpaceViewController.swift:885-902`

心跳逻辑：

- 心跳 API 是 `/sitespace/user/hb`。
- 活跃用户查询 API 是 `/sitespace/get/activeuser`。
- 心跳间隔是 30 秒，并且进入 Space 后立即 fire。

相关代码：

- `SunSmart/Common/Network/NetowrkReqeustApi.swift:101-105`
- `SunSmart/Common/Network/NetowrkReqeustApi.swift:296-305`
- `SunSmart/Main/Space/Controller/SpaceViewController.swift:780-810`

退出页面逻辑：

- `viewWillDisappear` 只隐藏引导视图，没有停止心跳，也没有通知服务端释放 active user。
- `stopHeartbeatTimer()` 在 `deinit` 中执行。

相关代码：

- `SunSmart/Main/Space/Controller/SpaceViewController.swift:263-281`

## 结论

### 1. 手机 B 要如何获取 Editor 权限并进入 Space？

手机 B 已经以 Editor 权限导入时，云端成员权限本身通常已经是 Editor。当前提示 Visitor，不代表 B 的成员权限变成 Visitor，而是进入 Space 时发现另一个 Owner/Editor active，客户端把本次会话降为非编辑状态。

B 要以可编辑状态进入，需要满足：

- 手机 A 不再作为该 Space 的 active Owner/Editor。
- 服务端 `/sitespace/get/activeuser` 不再返回 A 作为 active Owner/Editor。
- B 重新进入 Space，触发 `checkTheSpaceMembersRequest()` 后没有检测到其他 active Owner/Editor。

从当前代码看，客户端没有提供“B 抢占 Editor”或“Owner 主动让出编辑锁”的入口。能做的是让 A 真正离开并等待服务端 active user 过期，或者由 Owner 在分享管理里清除 Editor/重置权限，但清除 Editor 是成员权限操作，不是当前编辑会话释放。

### 2. 手机 A 停留在 Sites 页面，会干扰手机 B 进入 Space 吗？

可能会。

关键在于 A 从 Space 退到 Sites 页面时，`SpaceViewController` 是否已经释放：

- 如果只是从 Space pop 回 Site/Sites，并且 `SpaceViewController.deinit` 已执行，心跳会停止。此时是否还干扰 B，取决于服务端 active user 的过期时间。
- 如果某种导航路径、弹窗、异步引用或导航栈状态导致 `SpaceViewController` 未释放，则心跳可能继续存在，A 会持续被服务端视为 active Owner/Editor，从而干扰 B。

即使 `deinit` 已执行，A 刚退出后 B 立即进入，也可能仍被 active user 缓存/心跳有效期影响，需要等待服务端超时。

### 3. 手机 A 退出 App 后，手机 B 能顺利以 Editor 权限进入吗？

大概率可以，但不一定是“立刻”。

退出 App 后，A 的客户端心跳会停止；只要服务端根据心跳超时清理 active user，B 再进入就应当以 Editor 可编辑状态进入。

但当前客户端代码没有在 `applicationWillTerminate` 或后台生命周期里调用释放 active user 的接口，也没有看到专门的 leave/unlock API。因此是否能立刻进入，取决于服务端 `/sitespace/user/hb` 的超时策略，而不是 App 主动释放。

## 可能根因

最可能原因是：服务端 active user 锁以心跳维持，但客户端离开 Space 时没有主动释放编辑会话。A 退出到 Sites 页面后，如果心跳尚未过期，或者 SpaceViewController 未释放导致心跳继续发送，B 就会被判断为“有其他 Owner/Editor 正在编辑”，只能以 Visitor 模式进入。

## 建议验证

1. 在 A 从 Space 返回 Site/Sites 时观察 `SpaceViewController.deinit` 是否打印。
2. 在 B 进入时抓 `/sitespace/get/activeuser` 响应，确认是否仍返回 A 的 userId 和 Owner role。
3. 记录 A 退出 Space 后，B 每隔 10 秒尝试进入，确认服务端 active user 超时时间。
4. 如果要优化体验，应考虑增加“离开 Space 主动释放 active user”的服务端 API，或在 `viewWillDisappear` 判断真正离开 Space 时停止心跳并通知服务端释放。
