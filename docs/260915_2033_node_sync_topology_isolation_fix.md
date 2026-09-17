# 同步拓扑跨空间错误传播修复

## 问题与方案

审查指出 `c81fb38` 的只读拓扑读取器在检查当前空间的 Site Zone 参与关系之前，会解码同一 Site 所有空间的 `triggerZones`。无关空间损坏会使当前空间提前返回不可用，并触发错误同步提示。

将空间枚举与区域解码分开：枚举时保留原始区域数据，先解码当前空间并生成本地计划；只有当前或历史 Site Zone 成员涉及当前空间时，才在既有跨空间分支解码其他空间。真正依赖的数据损坏继续返回不可用，保留已有版本、保护状态和 Site 确认检查。

## 回归范围

扩展生产读取器与真实 SQLite / SDK 的隔离夹具，覆盖：

- 无 Site 扩展、空 Site Zone、不包含当前空间的 Site Zone / 历史成员：其他空间区域损坏仍返回可用的本地拓扑；同时覆盖无 Vendor Model 的普通节点输入。
- 当前 Site Zone 或历史成员涉及当前空间：依赖空间区域损坏继续返回不可用。
- 沿用当前空间区域损坏、跨空间合并、旧地址解析、Key 不一致、保护状态和只读等既有用例。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 修复前生产读取器 + 新回归用例，MtestiPhone15 | 如预期失败：`STORAGE FAIL: unrelated corrupt Space zones blocked a Site without extension data`，随后断言终止（signal 5）。 |
| 修复后生产读取器 + 同一套回归，MtestiPhone15 | `STORAGE PASS`；无关损坏隔离、普通无 Vendor 节点、当前/历史依赖损坏及全部既有存储检查通过。 |
| 真机既有 SDK、保护读取、同步刷新与 Cell 复用夹具 | 全部通过，测试 App 最终退出码 0。 |
| `python3 scripts/check_node_sync_status_refresh.py` | 通过，包含取消、失效、保护准备竞态及压力用例。 |
| SunSmart Debug / iPhoneOS 构建 | 直接执行 `xcodebuild`，使用 `generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`，`BUILD SUCCEEDED`。 |
| `git diff --check` | 通过。 |

存储夹具通过 `prepare_node_sync_topology_storage_tests.py` 装配进已有的 `/tmp/P1NodeSyncStatusTests` 隔离测试工程。使用 Release、启用既有 `DEBUG SUNSMART_PERFORMANCE` 测试条件，SDK revision 为 `a6246b1b0409824a3227a9c7cad8140219feb182`。通过 `xcrun devicectl` 在 MtestiPhone15 上安装并带 `--self-test` 启动，输出直接从命令结果读取。

修复前验证只在临时装配文件中使用 HEAD 的生产读取器，工作区修复保持不变；修复后重新从工作区装配并构建。两轮使用同一新增测试集，确认失败来自被修复分支。

## 范围与边界

- 生产变更仅涉及 `NodeSyncTopologyStorage.swift`；同时扩展存储测试并保存本文。未修改 SDK、依赖、target 配置、资源或本地化，也未创建 Git commit。
- 本次完整 App 构建范围为 SunSmart；其他品牌未重新构建。
- 真机运行使用临时 SQLite 与隔离数据，GroupInfo 等既有夹具边界保持不变。未用真实账户数据验证生产页面，也未进行云端同步或蓝牙 Mesh 配置操作。
- 正式 App 的人工确认仍应检查：A 不参与 Site Zone、B 区域损坏、A 普通设备已同步时无额外同步提示；A 实际依赖损坏空间时继续提示不可用。隔离测试通过不代表生产 UI 人工验收完成。
