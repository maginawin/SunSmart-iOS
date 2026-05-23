# PJEightKeySwitchMonitorVC 页面问题分析

## 背景

`PJEightKeySwitchMonitorVC` 是 8 键开关的详情页面。当前从开关列表点击 8 键开关时，会以 `present(NavigationViewController(rootViewController: vc))` 的方式展示详情页；详情页右上角菜单点击 Edit 后，会进入 `PJPreAddEightKeySwitchesVC`。

## 当前实现

### Edit 后进入的页面

- 页面类：`PJPreAddEightKeySwitchesVC`
- 入口：`PJEightKeySwitchMonitorVC.pushEditor()`
- 当前方式：`present(NavigationViewController(rootViewController: vc), animated: true)`
- 该页面同时承担创建 8 键开关和编辑 8 键开关两种模式：
  - `init(space:)`：创建模式
  - `init(space:switchData:)`：编辑模式

### 当前保存逻辑

`PJPreAddEightKeySwitchesVC.submitAction()` 会调用 `persistSwitchData(_:)`：

- 替换或追加 `MeshNetworkManager.instance.switchs` 中的开关数据。
- 调用 `switchData.save()` 保存通用开关数据。
- 调用 `PJEightKeySwitchRepository.shared.save(switchData)` 保存 8 键开关扩展数据。
- 发送 `switchsRefreshNotificationName` 和 `spaceDataChangedNotificaitonName`。

## 数据库结论

sunsmart 数据库中没有按 `0x2A01` 或 `0x2A02` 单独建表。

Battery Power Switch 作为 Switch 数据保存到通用开关表和 8 键扩展表：

- `switchs` 表：保存开关通用字段。
  - `switchId`
  - `name`
  - `enabled`
  - `panelType`
  - `linkGroupAddress`
  - `subLinkGroupAddress`
  - `bindGroupAddresses`
  - `unbindGroupAddresses`
  - `sceneA`
  - `sceneB`
  - `sceneC`
  - `sceneD`
  - `proxyAddresses`
  - `enOceanMacAddress`
  - `enOceanSecurityKey`
  - `deleteProxyAddress`
- `pjEightKeySwitchs` 表：保存 8 键开关扩展字段。
  - `meshUUID`
  - `subNetworkKey`
  - `switchId`
  - `panelType`
  - `periodicReporting`
  - `ledIndicatorEnabled`

`0x2A01` 和 `0x2A02` 本身仍是设备 PID，用于识别 Battery Power Switch 节点；开关编辑数据通过虚拟 Switch 的 `switchId` 关联，而不是通过 PID 建表。

## 问题

### 1. Edit 页面使用 present，不符合交互要求

当前 Edit 页面再次 present 一个新的 `NavigationViewController`。这会导致：

- Edit 页面不是当前详情导航栈的一部分。
- 页面可以通过 modal 下拉手势关闭。
- 保存完成后默认 dismiss 当前 modal，无法自然回到原详情页并刷新标题。

### 2. 未保存编辑内容退出时需要提示

`PJPreAddEightKeySwitchesVC` 已经有 `Snapshot` 和 `hasUnsavedChanges` 判断，也会在自定义返回按钮 `closeAction()` 中提示。

但当前 Edit 以 modal 方式展示，系统下拉关闭绕开了自定义返回按钮；改为 push 后，下拉手势问题消失，但还需要处理系统侧滑返回。否则用户侧滑退出时，未保存内容可能丢失。

### 3. 仅修改名称保存后 Monitor 标题不会刷新

保存后 `PJPreAddEightKeySwitchesVC` 会更新数据库和 `MeshNetworkManager.instance.switchs`，但 `PJEightKeySwitchMonitorVC` 持有的 `viewModel.switchData` 仍是进入页面时的对象引用/快照。当前只发送通知，Monitor 页没有订阅或回调刷新自身 `title`。

因此仅修改设备名称后返回详情页，标题仍可能显示旧的 switch name。

## 推荐修复方案

### 导航

- `PJEightKeySwitchMonitorVC.pushEditor()` 改为 `navigationController?.pushViewController(vc, animated: true)`。
- 保留 `PJEightKeySwitchMonitorVC` 自身从开关列表被 modal 展示的方式。
- Edit 页进入后是 push 页面，不再支持下拉手势关闭。

### 未保存退出提示

- `PJPreAddEightKeySwitchesVC` 增加编辑态的导航返回拦截。
- 点击自定义返回按钮时继续使用现有 `hasUnsavedChanges` 提示。
- 处理系统侧滑返回：如果存在未保存内容，禁止直接 pop，并展示同样的退出确认；用户确认退出后再执行 pop。

### 保存后刷新标题

- `PJPreAddEightKeySwitchesVC` 增加保存完成回调，例如 `switchSavedAction`。
- `PJEightKeySwitchMonitorVC` 在 push Edit 时设置回调，收到最新 `PJEightKeySwitchData` 后：
  - 更新 Monitor 的 viewModel 数据。
  - 更新 `title = viewModel.title`。
  - 调用 `updateUI()`。
- Edit 保存成功后从导航栈 pop 回 Monitor 页面，而不是 dismiss。

## 验证点

- 从 `PJEightKeySwitchMonitorVC` 点击 Edit 后，进入 `PJPreAddEightKeySwitchesVC` 且是 push 方式。
- Edit 页面不能通过下拉手势关闭。
- Edit 页面未保存时点击返回或侧滑退出，需要弹出确认提示。
- 仅修改名称并保存后返回详情页，Monitor 标题更新为最新 switch name。
- 数据仍写入 `switchs` 与 `pjEightKeySwitchs`，不新增 `0x2A01`、`0x2A02` 独立表。
- 开关列表仍通过 `switchsRefreshNotificationName` 刷新。
