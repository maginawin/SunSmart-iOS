# EFC Delete 返回 Others 设计

## 背景

在 EFC 设备中仅有一个空 Group 时，从 EFC 监控页右上角菜单选择 Delete，删除流程可以成功完成，但页面仍停留在 EFC 页面，没有返回到上级 Others 页面。

同时需要确认 Others 页面是否有类似问题：删除成功后，Others 设备列表是否可能不刷新。

## 代码事实

- EFC monitor 从 Others 打开时，使用 `NavigationViewController(rootViewController: vc)` 以 modal 方式展示。
- EFC monitor 右上角 Delete 成功后会调用 `finishDeleteDevice()`，再调用 `closeOrBack()` 收尾。
- 当前 `closeOrBack()` 只识别“当前 VC 自身被 present 且 navigation 栈只有一个页面”的情况。
- 从 Others 打开的实际结构是“承载当前 VC 的 navigationController 被 present”，当前 VC 自身的 `presentingViewController` 为空。
- 因此删除成功后会落入 `navigationController?.popViewController(animated:)`，但当前 EFC monitor 已是 modal navigation 的 root VC，pop 不会离开页面。
- Others 页面自身的 EFC 删除入口已经在 completion 中调用 `finishDeleteOthersItem()`，会重新加载 `DeviceEmerFireStore`、刷新 collection view，并发送 Others / Devices / Space 相关刷新通知。

## 采用方案

采用最小共享修复：只收紧 EFC monitor 的 `closeOrBack()` 关闭判断。

新的收尾规则：

1. 如果当前 VC 自身是被 present 的单页 navigation root，则保持现有 dismiss 行为。
2. 如果当前 VC 所在的 navigationController 是被 present 的单页 navigation root，则 dismiss 当前 navigationController。
3. 其他普通 push 场景继续 pop 当前页面。

这样从 Others 打开的 EFC monitor 删除成功后会关闭 modal navigation，回到 Others 页面；Others 在 `viewWillAppear` 中会重新执行 `updateUI()`，列表会从 `DeviceEmerFireStore` 重新加载。删除 completion 已经会发送 `deviceOthersRefreshNotificationName`，可继续作为辅助刷新信号。

## 不变范围

- 不改变 EFC Delete 的 mesh reset / local-only / delete cleanup 语义。
- 不改变 empty group 的 delete cleanup planner。
- 不改变 Others 页面自身的删除 completion 和列表数据来源。
- 不新增来源参数或页面专用分支。
- 不调整本地化、资源、target 配置或依赖。

## 影响面

主要影响 `EmerFireAlarmMonitorVC.closeOrBack()` 的所有调用场景。

预期影响：

- 从 Others modal 打开的 EFC monitor：Delete 成功后 dismiss，返回 Others。
- 从 push 进入的 EFC monitor：Delete 成功后继续 pop。
- 普通左上角关闭按钮：modal root 场景仍 dismiss。

## 验证计划

1. 增加或更新 EFC contract，覆盖 modal navigation root 下 `closeOrBack()` 应 dismiss navigationController 的语义。
2. 实现 `closeOrBack()` 的导航容器判断。
3. 运行 EFC contract，确认回归用例通过。
4. 运行 `git diff --check`。
5. 运行 iPhoneOS 构建验证：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 自检

- 范围聚焦在删除成功后的页面收尾，不触碰删除流程本身。
- Others 页面“不刷新”的疑点已拆分：当前代码有 completion 刷新和通知刷新，主要缺口是 EFC 页面没有返回。
- 方案不依赖新增状态字段，因此不会影响 share/import、sync planner 或设备数据结构。
