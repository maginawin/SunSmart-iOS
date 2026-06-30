# Space 删除防恢复 Review 与测试用例

## Review 结论

本次更新未发现阻断性问题。改动聚焦在 Space 本地变更提交链路：删除成功后立即刷新 Space 汇总计数、推进 `lastUpdate`、让 `needUploadCloud` 变为 true，并按变更类型触发云同步。这个方向与问题根因匹配，可以降低旧云端 Space payload 在重入 Space 时覆盖本地删除结果的概率。

## Share / Import Space 影响

- Share Space：影响是正向的。删除 Lights、Switches、Others 后，Space 会立刻进入待上传状态。现有分享入口会检查 Site / Space 的待上传状态，未同步完成前不会直接进入分享，因此更不容易把删除前的旧云端数据分享出去。
- Import Space：未看到直接负面影响。手动导入仍走 `SpaceData.import` / `SpaceData.update`，本次新增的本地变更提交 helper 不会在导入时主动触发，因此不会因为导入而额外标脏或额外上传。
- Join shared Space：未看到直接负面影响。加入分享 Space 后主要保存权限、密码和状态，不会调用本次新增 helper；后续进入 Space 时仍按既有 `SpaceData.update` 时间戳规则处理。
- 冲突边界：如果服务器端 Space 的 `updateTimestamp` 真实大于本地删除后的 `lastUpdate`，仍会按既有策略接受服务器数据。这不是本次更新新增的问题；本次修复主要覆盖“本地删除后还没及时标脏，旧云端 payload 同时间戳或旧状态回灌”的场景。

## 关联入口核对

- Lights：批量删除和强制删除成功后会直接提交 Space 本地变更，不再依赖 Space 页面通知观察者。
- Switches：删除本地 switch 数据后会直接提交 Space 本地变更，并保留原有列表刷新通知。
- Sensors：当前是空态页面，没有同类删除入口，本次更新没有改变其导入、分享或同步行为。
- Others：删除完成后会直接提交 Space 本地变更，再刷新 Others 列表。

## 正常功能影响分析

- 本次 helper 只改变“本地已有变更后如何标记并触发云同步”，不改变 `SpaceData.export` / `SpaceData.update` 的 JSON schema，因此正常的 cloud / share / import 数据结构不受影响。
- Owner / Editor 删除设备后会刷新 Space 汇总计数，并让 `lastUpdate` 大于 `lastUploadCloudTimestamp`，从而进入待上传状态。同步成功后，`CloudSynchronizationManager` 会把 `lastUploadCloudTimestamp` 更新为当前 `lastUpdate`，待上传状态会消失。
- Visitor 不具备设备删除/编辑入口；即使异常路径调用 helper，也只会本地保存汇总计数，不会进入上传队列。`needUploadCloud` 对 Visitor 为 false，因此不会产生 Visitor 上传覆盖 Owner / Editor 数据的问题。
- 对不同用户之间的数据同步，预期行为是“有写权限的一端先上传，其他端再通过 `spaceInfo` / `SpaceData.update` 拉取更新”。本次修复让删除端更快进入上传队列，属于正向影响。
- 仍需注意既有冲突策略：如果两个有写权限用户几乎同时修改同一个 Space，最终仍按服务器返回的 `updateTimestamp` 与本地 `lastUpdate` 判断是否覆盖。本次修复没有新增多端合并策略，因此并发编辑仍需要按现有产品规则验收。

## 简单测试用例

用例 ID：SDCR-001

目标：验证删除 Lights 后，立即返回并重新进入 Space，不会被旧云端数据恢复。

前置条件：

- 使用 Owner 或 Editor 权限进入一个已上传云端的 Site / Space。
- Space 的 Main - Lights 中至少有 1 个设备。
- 网络可用，App 能正常访问云端同步接口。

步骤：

1. 进入 Site 页面，点击目标 Space Item。
2. 进入 Space - Main - Lights。
3. 点击底部删除按钮，选择所有 Light 设备。
4. 点击 DELETE，等待删除成功提示。
5. 返回 Site 页面，确认目标 Space Item 上的 Luminaires 显示为 0。
6. 立即点击同一个 Space Item，再次进入 Space。
7. 查看 Main - Lights 列表。
8. 再返回 Site 页面，查看目标 Space Item 上的 Luminaires。

预期结果：

- 第 7 步 Main - Lights 不应重新出现已删除设备。
- 第 8 步 Space Item 的 Luminaires 应保持为 0。
- 如果云同步暂时失败，可以提示同步未完成或失败，但本地已删除设备不应被旧云端数据恢复。

## 轻量回归补充

- Switches：删除一个 Switch 后，立即返回 Site 并重入 Space，Switch 不应恢复，Space Item 计数不应回弹。
- Others：删除一个 Others 设备后，立即返回 Site 并重入 Space，Others 设备不应恢复，Space Item 计数不应回弹。
- Share：完成 SDCR-001 后马上进入 Share Space，若 Space 仍待上传，应先提示或触发同步，不能直接分享包含已删除设备的旧数据。
- Import / Join：导入或加入其他 Space 后，不应因为本次删除同步 helper 产生额外本地待上传状态；导入结果应继续遵循导入文件或分享 Space 的实际内容。

## 多用户 / 角色同步测试用例

用例 ID：SDCR-002

目标：验证 Owner 删除设备后，Editor / Visitor 能看到删除后的 Space 数据。

前置条件：

- 同一个 Space 已分享给一个 Editor 和一个 Visitor。
- Owner、Editor、Visitor 三个账号均能进入该 Space。
- Space 中至少有 1 个 Light 设备。

步骤：

1. Owner 进入 Space - Main - Lights，删除一个 Light。
2. Owner 返回 Site 页面，确认 Space Item 的 Luminaires 计数减少或变为 0。
3. 等待 Owner 端同步完成，或观察不再提示同步未完成。
4. Editor 账号刷新 Site / 重新进入同一个 Space。
5. Visitor 账号刷新 Site / 重新进入同一个 Space。

预期结果：

- Editor 的 Main - Lights 不应显示 Owner 已删除的 Light。
- Visitor 的 Main - Lights 不应显示 Owner 已删除的 Light。
- Editor / Visitor 的 Site Space Item 计数应与 Owner 删除后的计数一致。
- Visitor 仍不应出现 Add / Edit / Delete 等写操作入口。

用例 ID：SDCR-003

目标：验证 Editor 删除设备后，Owner 能通过云同步看到删除结果。

前置条件：

- 同一个 Space 已分享给一个 Editor。
- Editor 具备设备删除权限。
- Space 中至少有 1 个 Light 或 Switch。

步骤：

1. Editor 进入 Space，对 Light 或 Switch 执行删除。
2. Editor 返回 Site 页面，确认对应计数已减少或变为 0。
3. 等待 Editor 端同步完成，或观察不再提示同步未完成。
4. Owner 账号刷新 Site / 重新进入同一个 Space。

预期结果：

- Owner 端不应恢复 Editor 已删除的设备。
- Owner 端 Site Space Item 计数应与 Editor 删除后的计数一致。
- Owner 仍可继续执行正常 Add / Edit / Delete / Share 操作。

用例 ID：SDCR-004

目标：验证 Visitor 不会因进入或刷新 Space 产生上传覆盖。

前置条件：

- 同一个 Space 已分享给一个 Visitor。
- Owner 删除一个设备后尚未做其他编辑操作。

步骤：

1. Visitor 进入该 Space，查看 Main - Lights / Switches / Others。
2. Visitor 返回 Site 页面，再次进入该 Space。
3. Owner 刷新 Site / 重新进入 Space。

预期结果：

- Visitor 只能控制可控设备，不应出现删除入口。
- Visitor 端不应触发 Space 待上传状态或同步失败提示。
- Owner 端设备列表和计数不应因为 Visitor 的进入 / 刷新而回滚。

用例 ID：SDCR-005

目标：验证删除后上传未完成时，App 的正常入口不会分享或导入旧数据。

前置条件：

- Owner 或 Editor 删除设备后，临时断网或保持云同步未完成。
- Space 仍处于待上传状态。

步骤：

1. 删除设备后立即进入 Share Space。
2. 返回 Site 后立即重新进入该 Space。
3. 恢复网络，等待同步完成。
4. 使用另一个账号重新进入该 Space。

预期结果：

- 第 1 步应提示同步未完成或触发同步，不应直接分享旧 Space 数据。
- 第 2 步本机不应恢复已删除设备。
- 第 4 步另一个账号在同步完成后应看到删除后的数据。

用例 ID：SDCR-006

目标：确认两个有写权限用户并发修改时仍遵循现有时间戳策略。

前置条件：

- Owner 和 Editor 同时在线，并进入同一个 Space。
- Space 中至少有 2 个设备，便于分别操作。

步骤：

1. Owner 删除设备 A，但暂不确认另一端是否已刷新。
2. Editor 在接近同一时间修改或删除设备 B。
3. 两端分别等待同步完成。
4. Owner 和 Editor 分别刷新 Site 并重新进入 Space。

预期结果：

- App 不应崩溃，不应出现本地计数与列表明显不一致。
- 最终两端展示应收敛为同一份 Space 数据。
- 如果两个修改发生冲突，最终结果按现有服务器 `updateTimestamp` 策略决定；本用例不要求本次修复提供字段级合并。
