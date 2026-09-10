# 异常 Space 中不可见 Switch 的显示与删除修复

日期：2026-09-10。工作区：site-trigger-zone。基于 `61b7e8b9` 的未提交改动。

## 修复结果

Switch 列表、筛选前总数和 Space 摘要按明确的 Site UUID + Space Network ID 读取持久化记录。目标缺失 NetKey 时，不再借用 SDK 当前 Key 对应的 Switch 缓存显示空列表。记录携带自己的作用域，复制和转换为八键开关后仍保留作用域；Key 不匹配时，代理、Group 和 Scene 引用不从其他 Space 的活动网络解析。

进入 Space 时先校验目标 Key；缺 Key 的本地浏览不自动打开 Mesh 连接。扩展加载捕获目标 Network ID，在主队列检查调用方 generation 和 manager 身份后再发布缓存；不匹配时清空相关扩展缓存。Schedule、Dongle 查询显式指定 Network ID，GroupInfo 查询也明确指定子网。调试连接页使用相同的明确作用域接口。

Switch 页面在 Mesh 上下文不可用时保留删除入口，使用英文/简体中文的 Force Delete 确认。普通详情页、八键开关回调与旧共享删除入口接到同一按作用域删除的持久化逻辑。删除失败不再无条件显示成功。

## 数据边界

- 删除以目标 Space、Switch ID 和所选记录指纹校验，避免晚到回调或自动重试删除已改变的记录。新一次明确确认可以替换旧的未完成意图。
- 先记录 Switch 删除回执，清理匹配的代理绑定与未被其他 Switch 使用的私有虚拟 Group；清理前验证 Site 内地址归属，清理后回读。灯具代理只解除局部绑定，不删除灯具 Node。
- 实体 Power Switch Node 复用已有持久化设备删除流程；Force Delete 不发 Mesh Reset。正常路径沿用既有 Reset 发送方式，发送成功不等于实体设备已恢复出厂。
- Switch 基础行、八键侧表、Space 数量和待上传时间戳通过 App 数据库事务提交。数据库不可用、删除失败或回读失败均不视为完成。
- 回执随重进 Space/导入恢复；旧云端快照不能复活待确认的本地删除。只有达到该次删除时间戳的已确认云端回执才清理本地删除凭据。
- 非空 Space 仍不可删。仅在所有实际设备分类记录清空后，进入原有独立 Space 删除接口。
- 未修改任何现存 Key 值、Key index、SDK、依赖或品牌配置。历史 journal 使用可选 Switch 字段兼容读取。

## 自动验证

- `scripts/check_switch_record_scope.py`：提取生产 Switch 模型、作用域 SQL、侧表删除、删除执行器和 journal，在临时 SQLite 中执行。覆盖缺 Key 浏览、跨 Space 同 ID 隔离、错误代理不解析、基础表/侧表事务回滚、删除完成回执写失败后恢复、记录变化后拒绝自动重放、重新明确确认、权限拒绝、正常虚拟 Switch 删除、灯具代理保留、私有 Group 清理、旧 journal 和数据库不可用。
- `scripts/check_space_recovery_receipts.py`：原恢复流程通过；新增 Switch 回执保留/旧回执不能提前清除/对应时间戳清除的生产逻辑验证通过。
- `scripts/check_proximity_scoped_import.py`、`scripts/check_path_topology_persistence.sh`：设备删除、拓扑、作用域、恢复及相关原回归通过。
- `scripts/check_space_record_removal.py`：缺 Key 的空 Space 删除、其他 Space/Site 保留和失败重试通过。
- `scripts/check_space_mesh_keys.py`：Key 缺失、冲突、Site 聚合拒绝不完整上传、metadata-only Site 同步回归通过。
- 英文/简体中文 Localizable.strings 经 plutil 检查通过；git diff --check 通过。
- 五品牌 generic iPhoneOS Debug 最终增量构建全部通过：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。使用直接 xcodebuild，禁用签名。已有资源重名、重复编译文件和 UIKit 弃用警告未纳入本次修改。

## 现场验收

未安装 App、未操作用户手机、未调用生产删除接口，也未做模拟器测试。新确认框与列表交互的实际显示仍需现场验收；本次沿用现有 UICollectionView/底部编辑区/筛选空态及 SRAlertView 约束，没有新增布局结构。

推荐现场路径：进入异常 Space → Devices → Switches → 清除名字筛选（若启用）→ Edit → 删除可见 Switch → FORCE DELETE → 返回 Site，确认 Switch 数归零 → 删除已空 Space。若其他分类仍有实际记录，仍需先删除这些记录。

自动测试和构建不能证明真实云端已删除 Space，也不能证明硬件已重置。空间 Key 冲突仍保留为同步保护；本修复解决的是本地记录可见、可明确删除、删除不被旧云端数据覆盖，而不是迁移或重建旧项目密钥。
