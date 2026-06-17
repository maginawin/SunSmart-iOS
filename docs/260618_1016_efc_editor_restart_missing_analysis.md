# EFC Editor 重启后设备偶发不见分析

## 结论

这次没有发现 EFC 协议同步或 Editor 保存权限本身的明确错误。更可能的问题是 App 侧用于 Others 列表展示的 EFC 本地记录，在重启后的 Space 云端导入阶段被旧的或更高时间戳的远端 payload 覆盖清空。

现象“EFC 设备不见了，但功能正常”是合理的：功能已经通过 mesh/vendor 配置写进真实控制器和灯端；Others 页面显示依赖 `DeviceEmerFireStore` / `emergencyFireControllers` 本地数据，不等同于设备端配置状态。

## 证据链

- Others 列表不是直接展示所有 `realNodes`，而是读取 `DeviceEmerFireStore.shared.devices(in: space)` 后拼成 UI item。
- EFC 保存会进入 `emergencyFireControllers` 导出字段；云端导入时也会先删除本地全部 EFC 记录，再按远端 `emergencyFireControllers` 重建。
- `SpaceData.update()` 的覆盖条件只看远端 `updateTimestamp` 是否更新，或同时间戳下 summary count 是否变化。summary 只包含 device/group/scene/schedule/switches 数量，不包含 `emergencyFireControllers`。
- EFC 编辑保存发的是 `.common` 变更，Space 层把 `.common` 放到 slow sync，默认 10 秒后才上传。
- 真实设备添加成功发的是 `.network(.address)`，这一路是 promptly sync；但如果刚添加/配置后直接退出 App，pending cloud sync 仍可能未完成。
- `applicationWillTerminate` 没有 flush cloud sync 队列，只 reset UART debug 状态。

## 可能触发路径

1. Editor 在 Space > Others 添加真实 EFC，App 本地创建 EFC 记录，设备端配置正常。
2. 配置保存后触发 `.common`，进入 10 秒 slow sync；或添加后的 address/site sync 仍在进行中。
3. 用户退出 App，pending cloud sync 未完成。
4. 下次打开 App 时先从云端拉 Space 数据。
5. 如果云端 payload 里没有这条 EFC，或者远端有更高 `updateTimestamp` 但 `emergencyFireControllers` 仍是旧数组，导入流程会删除本地 EFC 表并按远端数组重建。
6. UI 看不到 EFC；但设备端和灯端的已下发配置仍在，所以 EFC 功能继续正常。

## 为什么后续不一定复现

如果后续测试时同步已经完成，或等待超过 slow sync 的 10 秒窗口，云端 payload 会包含 `emergencyFireControllers`，重启后就不会丢。

## 当前判断

这是一个真实存在的时序/同步一致性风险，不是高概率必现 bug。最可疑点是 `emergencyFireControllers` 被作为 Space payload 的附属数组处理，但导入保护和退出同步兜底没有把它当成独立关键数据看待。

