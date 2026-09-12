# Debug Site / Space Export Json 需求分析与开发方案

日期：2026-09-12  
状态：待用户确认；本次仅分析与规划，未修改业务代码。

## 1. 结论

需求合理，适合辅助排查本地配置与服务器保存结果的差异。菜单位置、图标、权限和 Debug / Release 边界已明确，但还需要确定导出数据的时间语义、Site 包含哪些 Space、请求体层级，以及异常状态下的行为。

建议第一版定义为：**将当前本地数据按指定同步接口的完整 JSON 请求体结构导出为文件，通过系统分享面板分享。导出本身只读、离线可用，不触发同步，不修复数据。**

该文件代表当前本地候选请求数据，不保证等于某次历史同步实际发送的数据，也不代表当前同步流程一定允许上传。精确判断“发送前、传输中、服务器保存后”的故障位置，还需要对应同步请求记录和服务器记录；本功能先解决当前本地内容的可观察性。

## 2. 已核实的实现现状

| 位置 | 发现及影响 |
| --- | --- |
| `SunSmart/Main/Site/Controller/SiteViewController.swift` 的 `moreClick()` | `Share&Authority` 使用 `menu_share`；其后可插入新入口。Site 菜单宽度为 `SCRXFrom(154)`。 |
| `SunSmart/Main/Space/Controller/SpaceViewController.swift` 的 `moreClick()` | `Share` 使用 `menu_share`；新入口应位于其后、现有 Debug 项之前。菜单宽度为 `SCRXFrom(108)`，英文新文案需要实际测量。 |
| `SunSmart/Common/Cloud/CloudSynchronizationManager.swift` 的 `getNetworkApi()` | Site 上传明确传入待同步的 Space IDs，可以为空或为子集；尚未上传的 Site 实际走创建接口。不能将 Site 的任意一次同步理解为全量 Space 上传。 |
| `SunSmart/Common/Network/NetowrkReqeustApi.swift` | Site 同步请求体顶层是 `site`、`user`；Space 同步请求体顶层是 `siteId`、`spaceId`、`spaces`、`userId`，其中 `spaces` 为单元素数组。 |
| `SunSmart/Common/Data/ExportData.swift` | `site.export()` 不传 Space IDs 时可能产生 `spaces: [{}]` 占位结构；不能直接当作全量导出。Space 的 `.cloudSync` 导出可能读取服务器并调用 `prepareUpload`。局部校验失败还可能调用 `block`。 |
| `SunSmart/Common/Data/SpaceConfigurationSafety.swift` | `prepareUpload` 会执行恢复检查、远程读取、保存错误或恢复状态、记录快照等操作；直接复用会改变排查现场。 |
| Site 页面已有 `exportSpace()` | 入口被注释，导出的是裸 Space 对象；缺少同步请求外层、时间文件名和完善错误处理，不建议直接启用。 |
| `SunSmart/Common/View/MenuPopView.swift` | 已支持菜单消失后执行回调，可复用以避免菜单与系统分享面板叠加。 |
| `Config/` 与 Xcode 工程 | 五个品牌 target：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux；Debug 配置存在 `DEBUG` 编译条件，Release 品牌条件不含 `DEBUG`。 |

Site 与 Space 都有独立的 `permission`。Site 角色从服务器 `role` 读取；部分现有 Site 操作还会参考其 Space 中是否存在 Editor。因此新功能需明确使用哪个角色口径，不能直接套用 Share 的展示条件。

## 3. 建议确认的功能约定

### 3.1 展示与权限

- 入口、调试专用导出协调器和相关动作使用 `#if DEBUG` 编译隔离；Release 不包含该功能入口和专用执行路径。
- Site 菜单按 `site.permission` 为 Owner / Editor 展示。
- Space 菜单按 `space.permission` 为 Owner / Editor 展示。
- Site 角色为 Visitor、但某个 Space 为 Editor 时，建议只显示该 Space 的导出入口，不据此扩展 Site 入口权限。
- 菜单展示、点击和异步生成结束后检查权限及账户、区域、对象身份；权限已降为 Visitor 时停止分享。
- 网络不可用、蓝牙断开、云同步报错或有待上传修改，不单独作为隐藏入口条件。临时禁止编辑与“只读查看本地数据”分开处理；导入等不稳定状态仍需保护快照一致性。
- 仅修改两个页面右上角菜单，不扩展 Site 页面内 Space 卡片的快捷菜单。

### 3.2 内容与范围

| 项目 | 建议默认行为 |
| --- | --- |
| Site 文件 | Site 属性及当前本地已加载、属于该 Site 且当前用户具备 Owner / Editor 权限的 Space 完整数据，使用 `/sitespace/sync/siteprops` 的请求体外层。 |
| Space 文件 | 仅当前 Space 完整数据，使用 `/sitespace/sync/spaceprops` 的请求体外层。 |
| 已同步 / 未同步内容 | 都包含，不按 `needUploadCloud` 过滤，便于完整对比。 |
| 远程但本地尚未获取的数据 | 不自动拉取，不将导出描述为服务器整个 Site 的完整备份。 |
| Site 无可导出的 Space | `spaces` 使用空数组，仍可导出 Site 属性。 |
| 尚未上传的 Site / Space | 允许生成对应 sync 接口结构的本地候选数据；不执行创建，也不伪称它就是下一次实际创建请求。 |
| JSON 外层 | 保持现有接口原有结构，不另加 `metadata` 包装，便于直接按字段与服务器数据对比。 |
| 字段处理 | 保留现有值、类型、数组顺序、空数组、null 与缺失字段语义；不新增字段、不修复异常、不用空集合替代读取失败。 |

Site 默认全量导出符合权限的本地 Space，是显式选定的一种同步请求范围，可能大于某次实际同步的 Space 子集。比对时以 UUID 定位对象，不以数组下标判断差异；现有 Site 导出并发收集 Space，数组顺序本身可能变化。

完整请求体保留原有业务字段，包括原有 Mesh key 等配置值，否则无法做原值对比；不额外收集 HTTP Header、登录 Token 或新增 Auth 信息，也不把完整 payload 输出到普通日志或提交仓库。

### 3.3 文件和分享

- UTF-8 `.json`，缩进排版、对象键排序；只改善可读性，不改变字段含义，不以文件字节相同作为业务一致性的判据。
- 文件名建议：`Site_<SiteName>_<yyyyMMdd_HHmmss_SSSZ>.json`，例如 `Site_Office_20260912_093600_123+0800.json`。
- Space 文件名建议：`Space_<SpaceName>_<yyyyMMdd_HHmmss_SSSZ>.json`，例如 `Space_MeetingRoom_20260912_093600_123+0800.json`。
- 使用快照生成时间和设备时区偏移。清理路径分隔符、控制字符，处理空名称、过长名称；独立临时子目录避免同名覆盖。
- 写入成功后才打开 `UIActivityViewController`，分享文件 URL；iPad 设置有效锚点。
- 生成期间防止重复点击，按项目方式显示等待状态；用户取消分享不显示失败。
- 文件读取或写入失败、序列化失败、权限变化提供国际化错误提示；不弹出空分享面板。
- 完成或取消分享后清理本次临时文件；对异常中断留下的导出目录做有限期清理，不触碰其他临时文件。
- 新增文案英文 `Export Json`、中文 `导出 JSON`；错误文案优先复用现有通用 key，缺少时补齐英文和简体中文。

### 3.4 异常数据与并发

- 导出复用同步字段组装，绕开有副作用的上传准入流程；不调用同步队列、`prepareUpload`、`prepareSubmission`，不修改上传时间、dirty 状态、恢复记录或原同步错误。
- 不能仅把 `.cloudSync` 改成 `.localBackup` 就认为只读完成，现有导出内部仍存在 `block` 等副作用，需逐项隔离。
- 仅因断网、等待上传确认或上传保护而不能同步，但数据本身可完整读取时，允许只读导出；不清除对应保护状态。
- 数据损坏、拓扑无法一致组装、关键对象无法读取时，第一版明确失败并定位失败 Space / 原因，不跳过失败 Space 后宣称全量导出成功。此类场景不存在可保证完整的同步 JSON。
- 导入尚未完成、删除中、生成期间账户或数据版本发生变化时，拒绝不一致结果并提示重试；不暂停或取消原同步任务。
- 利用现有数据库版本机制检查生成前后版本，并捕获对象身份及内存元数据。必要时做有界重试，不能无限重试，也不能把数据库版本检查视为覆盖全部内存变化。
- 在同一操作上下文中读取固定对象的数据；序列化及文件写入处理不可变快照，避免后台线程直接遍历持续变化的模型。

第一版不额外提供损坏数据库原始记录导出，也不把旧的 `last-complete-export.json` 静默当作当前结果。这两者如需加入，应明确命名为其他取证材料。

## 4. 实施步骤与改动范围

1. 在 `ExportData.swift` 中最小范围分离字段组装和上传校验 / 写入，增加 Debug 只读调用路径。正式同步保留现有授权、完整性及恢复流程，不复制整套字段映射，不修改 SDK。
2. 增加共用的 Debug JSON 导出协调器：捕获上下文、选择 Space、生成只读数据，复用 `NetowrkReqeustApi.siteUpload` / `spaceUpload` 的请求参数外层，完成序列化、命名和临时文件管理；不发起请求，也不使用日志脱敏参数代替真实业务值。
3. Site / Space 页面分别在规定位置接入，复用 `menu_share` 和菜单结束回调，统一处理加载、错误、系统分享与 iPad 锚点。
4. 补齐国际化及五个 target 的源文件 / 资源成员关系；先实测菜单约束，需要时只调整这两个调用处的 Debug 菜单尺寸。
5. 完成数据与副作用回归、Debug / Release 编译验证和真机布局 / 分享验证，将实际结果记录到 `docs/`。

## 5. 验证与验收

| 维度 | 必须覆盖 |
| --- | --- |
| 数据结构 | Site / Space 请求体外层；健康固定数据与正式组装路径语义一致；嵌套配置、Unicode、空集合、null、原值与时间戳保持。 |
| Site 范围 | 空 Site、多 Space、混合角色、失败 Space、尚未上传 Site；不出现占位 Space，不静默丢失应导出对象。 |
| 只读性 | 监测导出期间网络请求数为零；数据库、恢复文件、上传状态及同步错误不被导出改变；成功和失败路径都验证。 |
| 并发 | 快照期间配置变化、切账号 / 区域、页面离开、角色变化、连续点击；不得分享跨上下文或过期权限的数据。 |
| 文件 | 名称含时间和级别；特殊字符、长名称、重名、写入失败、分享取消及临时文件清理。 |
| 角色与编译 | 五个品牌 Debug 下 Owner / Editor 可见，Visitor 不可见；Release 各角色均无入口及专用动作。 |
| UI | 真机实际布局测试覆盖 iPhone / iPad、英文 / 中文、支持的屏幕方向和最大菜单项数量；无文字截断、约束冲突、越界，分享 popover 锚点正确。 |

使用直接 `xcodebuild`、真机 SDK、generic iOS destination、关闭签名完成相关 Debug / Release 构建；不使用 Simulator。UI 验证使用可用真机，缺少对应设备时明确记录未验证项，不能仅靠编译宣称完成。

重点回归现有 Space 导出、完整性保护及恢复相关测试；新增测试围绕数据等价、只读副作用和权限等真实风险，不堆叠源码字符串检查。

## 6. 后续可选增强

如果目标升级为证明“某次同步到底发了什么”，建议另行增加 Debug 下实际发送请求的本地留档，记录对应时间、接口、对象 ID 和请求关联标识，再与服务器保存结果配对。该增强涉及实际请求边界及留存策略，第一版不默认加入。

## 7. 待用户确认

建议一次确认以下默认约定后开始开发：

1. 导出当前本地候选数据的完整请求体；Site 包含符合权限的全部本地 Space，不限定为最近一次同步子集。
2. Site / Space 分别按自己的 Owner / Editor 角色展示；只读、离线可用，数据无法完整组装时明确失败。
3. 所有五个品牌 Debug target 生效，Release 不提供；首版不增加历史实际请求留档或损坏数据库原始记录导出。
