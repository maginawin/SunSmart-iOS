# Site / Space 上传成功直接确认：需求分析与开发方案

日期：2026-09-11。状态：用户已确认并实施；结果见 `260911_1836_sync_success_direct_confirmation_implementation.md`。以下保留原开发方案。

## 1. 需求与推荐口径

将 `/sitespace/sync/spaceprops`、`/sitespace/sync/siteprops` 的成功边界恢复为现有网络层返回 `.success` 后直接更新本地同步时间，不再等待上传后的配置 GET 比对。

同步时间使用本次实际请求 payload 的 `updateTimestamp`，沿用已有不倒退规则，而不是回调时最新的 `lastUpdate` 或当前墙钟时间。例如上传版本 100，等待期间本地变为 101；响应成功后确认 100，101 仍待同步。

成功仍沿用 `NetworkRequest` 已有 HTTP 与业务响应解析规则，不把任意 HTTP 200 一概当成成功，也不调整响应协议。

本方案回退成功后的配置验证门槛。上传前的完整性检查、权限检查、备份、导入事务、设备删除清理、gzip、Site 时区字段同步和 Mesh 配置逻辑继续沿用。

## 2. 当前代码与依赖

| 位置 | 当前行为 | 修改方向 |
| --- | --- | --- |
| `CloudSynchronizationManager.swift:978` | 新上传前恢复历史 submission | 已接受的回执直接本地收尾；结果未知的回执单独处理 |
| 同文件 `1023–1077` | prepare → 上传 → accepted → resumeUpload 回读 | prepare → 上传 → accepted → 本地确认 |
| `SpaceConfigurationSafety.swift:437` 附近 | `finishSubmission` 仅接受 verified，确认删除/恢复回执、时间戳和基线，再清理 submission | 提取共享成功收尾逻辑，使明确 accepted 可直接完成，不伪造远端 verified |
| 同文件 `467` 附近 | `resumeUpload` 可发起三次 GET，持续不同设置冲突标记 | accepted/verified 不发 GET；prepared 的未知结果恢复独立保留 |
| 同文件 `568` 附近 | `uploadBeforeUnbind` 成功仍回读 | 复用直接确认，覆盖 Site/Space 页面解绑 |
| `ShareAuthorityViewController.swift:610` 附近 | 批量解绑直接 siteUpload，成功使用回调时的 Space.lastUpdate | 纳入共享确认，使用实际提交 Site/Space 版本；保留原解绑操作流程 |
| `SpaceData.swift:126–139` | dirty 和 pending submission 共同决定失败显示 | 成功收尾后不再残留待回读状态；新编辑仍保持 dirty |
| `SpaceConfigurationSafety.swift:164、815` 附近 | submission 会保留本地导入状态并阻止普通导出 | 必须完成/迁移旧回执，单删 GET 无法解除这些限制 |

普通 Site 上传实际对 payload 中各 Space 请求 `get/spaceprops`，并非固定请求 `get/siteprops`。同步管理器中的 `get/siteprops` 是首次 Site 创建中断后的身份/地址资源恢复，位于本轮新上传之前。

## 3. 开发步骤

### 第一步：统一成功收尾

1. 保留上传前捕获的 account、region、Site/Space 身份、generation 和 submission ID；旧回调不得确认新实例或新提交。
2. 网络层成功后持久记录 accepted，立即调用不联网的共享收尾方法。
3. 确认本次实际提交时间；清除对应同步错误；按提交时间确认已完成的删除日志和本机恢复回执，保留更晚的本地操作。
4. 更新后续权限恢复需要的提交基线和既有迁移标记；该基线代表服务器已接受的请求内容，不再宣称经过远端内容校验。
5. 幂等清理对应 submission 和纯回读冲突标记。不得清除导入中断、无效拓扑、删除未清理、失权等其他保护原因。
6. 本地保存失败保留可恢复的 accepted 回执，只重试本地收尾；不额外 GET 或重复上传已接受的旧快照。核对时间、删除日志和状态文件不同持久化步骤的失败顺序，避免回执丢失或误显示成功。

### 第二步：接入全部上传入口

- `syncSpace`：仅确认本次提交的 Space。
- `syncSite` 与 `addSpaces`：确认本次 Site 版本及 payload 实际包含的 Spaces；不确认未提交的其他 Space。
- Site-only：直接确认 Site，无逐 Space 回读。
- 首次 `siteAdd`：同样位于 sync/siteprops，处理成功响应中的地址分配并保存创建事实，再直接确认提交版本；保留首次时区 pending 的现有合并规则。
- Site/Space 单个解绑与分享权限页批量解绑：均使用相同成功收尾。仅本地持久化完成且没有更新的待上传修改后继续解绑。
- 多 Space 成功上传后逐项本地确认；某项保存失败不回滚已确认项，后续仅恢复失败项，保留清晰的错误归属。

### 第三步：兼容已安装版本的回执

| 历史状态 | 推荐处理 |
| --- | --- |
| accepted + 回读冲突/未确认 | 已有业务成功证据，按历史提交版本直接收尾，无 GET；最新本地修改继续待同步 |
| verified，但本地收尾未完成 | 重试本地收尾，无 GET |
| prepared：可能超时、断网或进程中断 | 不能当作成功。保留现有未知结果的只读恢复；成功确认后收尾，否则维持真实失败/冲突 |
| 仅旧 `uploadReadbackUnconfirmed` 标记、无可靠 accepted 记录 | 保留已有迁移/未知结果处理，不根据标记凭空推进时间 |
| 创建请求中断且本地 Site 未保存创建事实 | 保留已有 `get/siteprops` 创建事实和 provisioner 恢复，避免再次 siteAdd；它不是正常成功后的配置比对 |

兼容收尾必须覆盖启动/网络恢复、手动同步、解绑前检查等入口，并在普通导出/阻塞判定之前生效。仅因回读留下的旧冲突不应继续拦截已接受回执；真正权限或本地数据问题仍遵守既有生命周期约束。

不全局清空恢复目录、UserDefaults 或删除日志，不批量更改所有 Space 的时间。

## 4. GET 请求的保留边界

正常上传成功后不新增任何用于确认该次配置的 `get/spaceprops` 或 `get/siteprops`，不执行三次比对，也不因随后读取旧数据而把该次上传改判失败。

以下 GET 仍可能出现，属于其他既有用途：进入页面/刷新、上传前升级基线或孤立成员检查、失权恢复、用户明确选择云端/本机恢复、上传结果未知的恢复、首次创建中断后的资源恢复。

这是按“sync 成功后直接更新同步时间”制定的推荐范围。若要求连结果未知的恢复 GET、上传前基线检查也一并取消，需要另行扩大回退范围；本方案不默认删除这些流程。

## 5. 验证计划

优先调整并运行现有生产方法测试 `scripts/check_space_recovery_receipts.py`，补充共享成功路径的行为测试；不能只依赖源码字符串断言。

| 场景 | 预期 |
| --- | --- |
| Space 上传成功，模拟远端配置不同或 GET 不可用 | 成功回调直接确认提交版本，上传后的 GET 次数为 0 |
| Site-only / Site 多 Space / addSpaces | 只确认本次 payload 覆盖的对象；无上传后 GET |
| 首次 Site 创建成功 | 地址资源与首次时区 pending 正确处理，无配置回读 |
| 请求期间再次编辑、旧响应晚到 | 仅确认旧提交版本，最新修改仍 dirty；时间不倒退 |
| 业务失败、HTTP 错误、超时 | 不推进同步时间；权限错误继续沿用既有处理 |
| accepted/verified 旧回执和回读冲突 | 无 GET 本地收尾，删除对应旧标记，重启后不再恢复同一回执 |
| prepared、创建结果未知 | 不伪造成功，保留相应恢复路径 |
| 删除/本机恢复后上传成功 | 只确认覆盖的已清理日志；较新的删除和本地修改保留 |
| 磁盘失败、部分 Space 保存失败 | 保留 accepted 本地恢复依据；已确认项不重复上传 |
| 切换账号/区域、失权、解绑重导入、新 generation | 旧回调不能修改新状态 |
| Site/Space 单个解绑与批量解绑 | 上传成功直接确认；存在新修改或本地收尾失败时不提前解绑 |

同时运行相关拓扑持久化、数据库安全回归，并核对既有测试中以 accepted 必须回读为前提的断言，仅替换已回退语义，保留未知结果恢复和导入保护测试。

共享代码影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个品牌，开发后对五个 scheme 直接执行 generic iPhoneOS、Debug、关闭签名的 xcodebuild。无需修改 SDK、依赖、资源或新增文案。本轮不执行构建；后续不使用 Simulator，也不默认进行真机测试。

## 6. 结果与影响

完成后，明确成功的上传不再因为回读旧数据、读服务延迟或配置比较差异显示 Synchronization failure；确认语义变为服务器接受请求。客户端不再通过该次成功路径验证服务端完整保存了所有配置。

本方案不包含服务端修改或历史云数据恢复，不整体 revert 原提交，因为原提交混有需要保留的导入、拓扑、删除及持久化修复。

当前工作树原有两份未跟踪分析文档保持原样。本轮仅新增本方案，等待确认后实施。
