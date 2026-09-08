# Create Group 保存失败修复记录

日期：2026-09-08。工作树：`trigger-zone-sep`。

## 修复结果

修复了默认日光 Profile 的 500 lux 被误当百分比拒绝，导致保存后回读失败的问题。类型 1、2、5 的默认配置现在可经过真实 SQLite 保存、关闭连接重载、云端字段导出/导入、再次保存与导出。原来的 500 lux、Profile ID 与场景数据均保留。

实施依据：`260908_1121_create_group_save_failure_analysis_plan.md`，用户已确认。

## 代码改动

### 统一字段单位与边界

`SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift` 增加共享 `levelIssue`，由本地 Profile 写入/读取及云端 Profile 完整性校验调用。

| 字段/类型 | 持久化允许范围 |
| --- | --- |
| highEndTrim、lowEndTrim，全部类型 | 0～100 |
| occupancyLevel、vacantLevel、standbyLevel、taskLevel，类型 1/2/5 | 0～65535 |
| 同上四个字段，类型 3/4/6/7/8 | 0～100 |

实际构建解析到远端 release revision `86f5ec9e40148b9cd93e0512702337fcec41dd40`。已核对该 checkout：DeviceProperty 的 illuminance 编码支持 0～167772.14 lux，但 Node+Messages 回读会转换为 UInt16，Node+Propertys 的 lux 缓存也是 UInt16。因此本次使用较小的 0～65535 上限，避免接受当前 App 无法安全回读的值。没有修改 SDK、依赖锁定或设备协议。

顶层数据与 scenes 中的亮度字段使用相同单位规则。类型 8 的日夜条件、必需场景字段及引用完整性保护继续保留。非 Photocell 的历史 scene 缺省字段仍由既有导入逻辑补默认值；字段存在但格式或数值非法时拒绝。旧顶层 standbyLevel 缺省兼容保留。

默认 Profile、校准模式、Auto min 的 0/30/255 语义和历史非法值归一化行为不变。没有对已有数值执行截断或单位换算。

### 保存与诊断

`SunSmart/Common/Data/Database.swift`：

- Profile 保存前验证顶层及所有场景的 level/time；重载时也验证场景，避免合法顶层数据掩盖损坏场景。
- 保留 Profile + GroupInfo 的 savepoint 事务与保存后回读。
- 事务失败可区分 profileWrite、groupInfoWrite、profileReadback。
- Profile 读取日志区分 rowMissing、queryFailed、databaseUnavailable、invalidField、invalidScalar、invalidTime、decodeFailed 等原因。
- GroupInfo 无法获得 Profile 时改为 profileUnavailable，避免把“存在但被拒绝”误称为物理缺失。
- 诊断只在 DEBUG 输出，不记录整份 Profile 或鉴权数据；既有日志审计通过。

没有修改 GroupAddViewController 的 UI、国际化文案、成功回调、云端通知、失败清理或 Proximity 生命周期。原有失败时删除新建 Mesh Group、清理失败阻断的逻辑保持不变。

## 新增自动回归

入口：`scripts/check_profile_persistence.py`，参数为实际 resolved SDK checkout；用例：`Tests/Group/ProfilePersistenceTests.swift`。

测试从当前生产源码抽取真实 Profile/GroupInfo 模型、默认值、拷贝、Codable、表结构、save/load、事务及云端 Profile 字段映射，使用 SDK 内的 SQLite 实现和工程内的 SwiftyJSON，在临时数据库执行。UIKit 的 Profile 介绍文案属性被移除，Mesh 环境、模板加载和无关拓扑/场景执行载体用最小替身提供；未执行真实蓝牙或整个 Space 导入事务。

已通过：

1. 八种真实默认 Profile，模拟创建页复制配置并保留新 Profile ID；SQLite 保存后关闭连接重开，确认值及日夜场景正确。
2. Profile 字段导出 → JSON 序列化 → 实际 Profile 导入字段映射 → SQLite 保存/重载 → 再导出，字段一致。
3. 完整生产表结构增加历史 regulatorAccuracy NOT NULL 无默认值列；旧值 33 保留，新行初始化为 0x14。
4. 已存在的 500 lux 数据及无 scenes blob 的旧记录可读取；Profile ID 保留；子网查询隔离。
5. 类型 7/8 更新为默认日光类型 1 后保存、重载及云端完整性校验成功。
6. lux/百分比的 -1、0、100、101、500、1500、65535、65536 边界；trim 超界；非整数、布尔、字符串、null、必需字段缺失。
7. 其他场景的 500 lux 按父类型决定是否允许；顶层合法但场景 blob 数值超界或解码损坏时，Profile 保持不可用。
8. 注入 GroupInfo INSERT 失败和 Profile SQL 写入成功但回读被篡改的失败，新建及编辑均回滚，两表计数和原配置保持一致。
9. Auto min 0、30、255、100 的保存、重载和导入归一化与既有语义一致。

临时数据库和构建产物由测试脚本自动清理，不读取或修改用户数据库。

## 既有回归与构建

| 检查 | 结果 |
| --- | --- |
| 新增 ProfilePersistenceTests | 通过 |
| check_configuration_database_safety.sh | 通过 |
| check_path_topology_persistence.sh | 通过，含拓扑/生命周期/完整性/作用域导入/恢复凭据 |
| check_profile_auto_min_compatibility.sh | 通过 |
| check_night_calibration_persistence.sh | 通过 |
| check_debug_logging.py | 通过，含 Debug、Release、ReleaseWithoutOptimization |
| git diff --check | 通过 |
| SunSmart generic iPhoneOS Debug 构建 | BUILD SUCCEEDED |
| Archipelago generic iPhoneOS Debug 构建 | BUILD SUCCEEDED |
| SLG Sync Plus generic iPhoneOS Debug 构建 | BUILD SUCCEEDED |
| SylSmart generic iPhoneOS Debug 构建 | BUILD SUCCEEDED |
| Lumineux generic iPhoneOS Debug 构建 | BUILD SUCCEEDED |

构建直接调用 xcodebuild，使用 SunSmart.xcworkspace、各品牌 scheme、iphoneos、generic/platform=iOS 与 CODE_SIGNING_ALLOWED=NO。未使用 Simulator、shell 包装或日志重定向。

已有无关编译警告仍存在，例如未使用局部变量、Info.plist 位于 Copy Bundle Resources、重复 Compile Sources；本次未扩展修改这些内容。

## 数据恢复及验收边界

- 仅被旧范围规则误拒绝且仍保存在数据库中的 Profile，可通过修正后的读取恢复；无需数据迁移、清库或重新生成配置。
- 没有自动清除已落盘的 blocked 状态。若设备此前因 invalidRemoteProfile 等原因被阻断，应先核对具体原因，通过既有恢复和重新校验流程处理；本轮没有用户设备的数据，不能证明其保护状态已恢复。
- 已读取可用设备列表，但尚未指定用于安装与新建 Group 的设备/测试 Space。本轮尚未安装 App，未执行真机创建、成员添加、重启重入、真实云上传/另一端读取或 Mesh 设备验收。
- 两表事务回滚已自动验证；真实 Mesh Group 清理及 UI 不前进仍需在上述真机流程中验收，不能用字段测试替代。
- 未提交、推送或改动用户原有分析文档。
