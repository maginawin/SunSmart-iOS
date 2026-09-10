# 同步异常 Space 的 Owner 删除例外

日期：2026-09-10。工作区：site-trigger-zone。本次按用户最新要求，调整此前“所有 Space 必须先清空设备”的限制；未执行任何用户数据删除。

## 当前规则

| Space 状态 | Owner | Editor / Visitor |
| --- | --- | --- |
| 正常且非空 | 不允许删除 | 不允许删除 |
| 正常且为空 | 沿用原删除流程 | 不允许删除 |
| 同步异常，可包含设备 | 允许确认后删除 | 不允许删除 |

同步异常使用明确判定：仍需上传且存在 `syncCloudError`，或 `SpaceConfigurationSafety.isBlocked` 为真（例如 Key 冲突、导入/设备清理未完成）。普通待上传状态，以及已同步完成后残留的旧错误，不单独开放非空删除。

仍检查目标作用域、数据库可用性、Primary Network 保护和同 Site 下重复 Network ID。无法安全区分目标和其他 Space 时不会清理其他项目记录。请求入口继续要求有效 Owner 身份，密码待验证或编辑权限被关闭时拒绝。

## 实现

- 新增共享 `SpaceData.canDeleteSpaceRecords`；保留 `canDeleteEmptySpaceRecords` 的真实空记录检查。Site 页面、Space 页面和 `requestSpaceRemoval` 都使用新共享入口。
- 异常 Space 必须请求原云端 spaceDelete，即使本地还没有成功上传时间戳。云端失败保留本地；成功或确认不存在后进入可恢复的本地清理。晚到响应继续检查身份 generation 和 Owner 权限。
- 确认文案明确说明删除 App/云端中的 Space 及全部设备记录，不重置实体设备；复用现有确认框，补充英文和简体中文。
- 放开非空删除后补齐 Group Switch、Dongle、EFC 的按 Site + Network ID 清理；八键开关侧表的批量删除失败现在会返回失败，保留 Space 清理重试入口。
- 本次不调用 Mesh Reset；实体设备以后手动恢复出厂再添加。保留其他 Site/Space 的记录，未修改 SDK、依赖或 Key 索引策略。

## 自动验证

- `check_space_record_removal.py`：执行生产删除规则和本地清理方法，覆盖异常 Owner、Editor/Visitor 拒绝、正常非空、普通待上传、陈旧错误、Primary Network、共享 Network ID，以及 EFC 清理失败后的重试和其他 Space 保留。
- `check_space_recovery_receipts.py`：执行生产请求/恢复逻辑，覆盖异常非空 Owner 无上传时间戳仍请求云端、云端失败保留数据、重试成功、Editor 不发删除请求、请求中 Owner 降为 Editor 不清理本地、晚到响应拒绝、正常非空仍拦截。
- `check_switch_record_scope.py`：实际临时 SQLite 验证 Switch 作用域、侧表和回执回归通过。
- `check_path_topology_persistence.sh`：原拓扑、设备删除、导入和恢复回归通过。
- 英文/简体中文 strings 的 plutil 检查与 git diff --check 通过。
- generic iPhoneOS Debug 构建全部通过：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux；无签名、无模拟器、无真机操作。

## 验收边界

没有调用生产删除接口，也没有替用户删除该异常 Space。现场需更新 App 后，由 Owner 在 Site 或 Space 页面点击 Delete 并确认，检查云端删除结果、返回列表和再次拉取数据。Editor 应无法删除。服务器是否接受删除、实体设备状态及确认框真机显示仍需现场验收；自动测试与构建不代替这些结果。
