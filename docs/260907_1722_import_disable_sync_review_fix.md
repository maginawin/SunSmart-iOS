# 导入后 Disable 同步任务遗漏修复

## 问题与修复

处理 `6c49683` 审查中的 P2：导入将 Group 改为普通 Profile 并清除拓扑后，设备实际保存的邻近照明状态仍可能启用。生命周期 `preview` 只为拓扑候选节点生成任务，因此页面重算时得到空列表，清除了待同步请求。

`SpaceViewController.presentProximityLightingRepairSyncIfNeeded()` 继续读取最新 Space，保留网络身份、权限、配置保护和拓扑有效性校验。通过校验后，使用已验证的拓扑计划，遍历目标网络全部真实节点调用实际 Node 任务生成方法，包含已退出拓扑但仍需 Disable 的设备；完成重算后才消费请求。

改动聚焦于导入后的页面重算，不改变通用生命周期候选节点策略。没有修改 SDK、依赖、资源、本地化或 UI 布局。原有审查文档保留，未执行 Git 提交。

## 回归验证

扩展现有适配层脚本，直接提取并编译页面实际重算代码，与生产 Context、Planner、Coordinator、Node 任务生成代码共同运行。SDK 和存储边界仍使用测试替身。

- 修复前：新用例失败，断言为 `deferred import sync must retain both Disable tasks after devices leave topology`。
- 修复后：普通 Profile、空拓扑、两个仍启用的节点生成两个 Disable，与导入时的任务一致。
- 核验生成任务引用网络激活后的新 Node 对象。
- 已禁用设备不产生重复任务；Profile 加载失败时不生成任务，保留请求。
- `bash scripts/check_path_topology_persistence.sh`：八组测试全部通过，包含新增执行用例和更新后的页面源码契约。
- `git diff --check`：通过。
- 直接运行 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet build`：退出码 0。输出存在既有资源符号重名和弃用 API 警告。

本轮只构建 SunSmart，未构建其他品牌，未运行 Simulator。自动化覆盖任务生成，不代表真实 BLE/Mesh 下发已验收；仍需在手机上导入普通 Profile、空拓扑配置，确认同步页包含两个 Disable，并验证设备完成禁用。
