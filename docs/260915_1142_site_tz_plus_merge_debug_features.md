# site-tz-plus 合并到 debug-features

## 合并结果

- 当前分支 `debug-features` 从 `2e875e1f` 快进至 `cf5e5c13`，已包含本地 `site-tz-plus` 的两个新增提交：`54804a09`（同步错误任务修复）、`cf5e5c13`（启动 CPU 占用修复）。
- 使用 `git merge --ff-only --autostash site-tz-plus`，没有文本冲突，autostash 已自动应用。
- 当前工作区原有未提交内容保持未提交，未推送远端，未修改来源分支。
- 合并前 12 个工作区文件备份于 `/tmp/debug-features-before-site-tz-merge-260915_114102`。
- 除工程文件需要叠加来源分支改动外，其余 11 个原有工作区文件均已通过 SHA-256 逐字节核对。
- 工程文件结构化核对通过：保留来源分支全部对象与当前工作区原有配置变更。

## 本次验证

- `check_feature_visibility.sh`：Debug/Release 可见性矩阵、实际菜单方法、角色变化及五品牌源码和 JSON 资源引用检查通过。
- `check_site_trigger_zones.sh`：数据兼容、持久化、29 个场景、候选项和只读拓扑检查通过。
- `check_startup_ownership_loading.py`：使用本次构建 SDK checkout，真实 SQLite 身份投影、恢复候选、主队列交还及过期恢复检查通过。
- `check_site_zone_cleanup_loading.py`：空 Zone 零 Mesh 读取、按 Space 延迟加载和保守清理检查通过。
- `check_space_sync_cleanup.py`：完整快照清理、观察状态保留和幂等检查通过。
- 五个品牌 target 均仅引用一份新增清理策略、清理协调器及原有功能可见性源码。
- 工程文件 `plutil -lint`、`git diff --check` 和未解决冲突检查通过。
- SunSmart Debug iPhoneOS 构建成功：直接运行 xcodebuild，使用 generic iOS destination、`CODE_SIGNING_ALLOWED=NO`，未使用 Simulator。

## 验证边界

本次执行分支集成，未新增 UI 或业务修复。其余品牌本次检查工程引用，未重新构建；未修改 SDK 或依赖版本。未运行真机、实际 Mesh 同步或修复后 CPU 采样，不能以编译和离线测试代替实际设备验收。真实同步与性能人工检查步骤沿用来源分支的实施文档及启动 CPU 修复文档。
