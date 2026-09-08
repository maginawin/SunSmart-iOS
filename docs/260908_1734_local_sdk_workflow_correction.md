# 恢复 SunSmartLocal 和 one-dev 的 SDK 开发流程

日期：2026-09-08。

## 错误与更正

用户明确使用 SunSmartLocal.xcworkspace 开发和运行 App。现场确认该 workspace 通过 `.local-sdk/nordic-sig-mesh-sdk` 指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，链接与 workspace 本身均正确。

此前修复误放到了另建的 SDK 工作树，导致用户实际使用的 one-dev 缺少 databaseReadRevision。随后把正式 project 改为本地 package、要求用户换 workspace，也是错误处理。不能将其他入口构建通过视为用户开发入口已修好。

此次检查时，正式 project、workspace 和远端锁文件已经恢复到 Git 基线，不再覆盖这些配置。将三项 SDK 修改直接应用到 one-dev 的 MeshDatabase.swift：数据库快照版本、地址 Set membership、节点地址标量查询。应用前 one-dev 工作区干净，HEAD 为 8bdbd5a；未替换其已有开发提交。

保留原 SunSmartLocal.xcworkspace 和 SDK 软链接；删除误加的 prepare_site_entry_sdk.sh 与独立 patch 文件，标记前一份依赖配置方案作废。另建 SDK 工作树不再参与依赖解析，本轮没有强制清理该目录。

## 验证记录

- SunSmartLocal 的 package resolve 成功，解析到 `.local-sdk/nordic-sig-mesh-sdk`，现场核实该软链接指向 one-dev。
- SDK diff 检查通过，正式工程配置无 diff。
- 本轮所有 App 构建均通过 SunSmartLocal.xcworkspace 执行，使用 generic iOS Debug、关闭代码签名，不使用 Simulator。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个品牌构建全部通过，退出码均为 0。
- 针对 one-dev 运行 check_site_entry_performance.py 通过：真实 SQLite 标量查询、地址语义、快照失效和 gzip 字节还原。

本地 SDK 发布和正式远端 pin 更新保持用户原有发布流程，未提交或推送；原 iPad 的加载性能仍需运行验收。
