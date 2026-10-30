# Devices Scene 详情页 UI 优化方案

状态：用户已确认，2026-10-31 完成 App 实施及自动验证；真实 UI 体验待用户验收。

## 目标与结论

长按 Scene 控件进入详情后，非空 Devices Scene 按 [Figma Device Scene / Details](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=721-8046) 展示只读分组卡片。设备成员全部删除后，使用现有默认 Scene 页的空态布局（同 Groups 详情的布局），显示场景名和 No members；仅改变展示，不自动把持久化类型改成 Groups。

现有 Groups 场景、Settings、Select devices 的业务行为保持现状。本次只涉及 App，无 SDK、固件或服务器配套。

## 已核实行为

- 实际入口是 `ScenesViewController.collectionLongPressAction`，present 包含 `SceneViewController` 的导航控制器；iPad 已设置弹窗尺寸，不新增入口或新的导航体系。
- `SceneViewController.deviceMode` 目前只检查 `configuration.kind == .devices`，没有检查设备成员数。Devices 分支使用 `SceneDevicesSelectionView` 的 `displayingSavedConfiguration` 模式；Groups 分支为标题、圆角分页网格和 `scene_no_members` 空态。
- 现有只读设备布局仍来自选择组件：计数靠右、全部折叠按钮、分类折叠箭头、上下两行分类标题，以及常驻 Saved parameters / Pending sync 说明。设备区缺少设计要求的独立圆角卡片间隔。
- `SceneDevicesSelectionView` 的调用方只有详情与 Settings（包括 Select devices 模式）；后者使用 `editorStyle: true`。`SceneDeviceSettingsCell` 仅由该组件使用，扩展只读布局可复用身份匹配、分组和参数摘要，不必复制整套设备解析。
- `SceneConfigurationStore.commit` 允许已有场景保存零设备，保存后仍为 `.devices`，原设备生成 `.remove` 待清理任务。永久删除设备经 `DevicePermanentDeletionCleanup` → `removeConfirmedIdentities` 移除对应成员和任务，同样不改变类型。
- 空配置、离线、缺失身份和清理中是不同状态。`deviceMembers` 是保存的成员意图；SDK 的 `scene.addresses`、在线设备数或成功解析的 targets 数均不能作为空场景依据。
- 现有类型切换保护会阻止有成员/待清理任务的场景切换类型。仅调整详情布局不会触碰这些保护，也不会影响导入导出、定时绑定或重启恢复。

## 展示与交互

以 Figma 的 375pt 画板为尺寸参考，使用 UIKit / SnapKit 自适应约束，不把 812pt 屏高或系统状态栏写死。

| 区域 | 计划行为 |
| --- | --- |
| 页面 | 沿用现有模态导航、关闭和更多菜单；Devices 标题为场景名，内容背景沿用项目对应的浅色主题 |
| 总数 | 导航下方 12pt，居中 `Device scene · N devices`，14pt、辅助文字色；按保存成员数计数，补齐英文单复数 |
| 列表 | 左右 16pt；摘要与首卡片间距 20pt；各分类独立白底、16pt 圆角，无编辑页整块阴影；卡片间距 12pt，纵向滚动 |
| 分类头 | 左侧组名，右侧该场景在此分类的成员数；左右 16pt、上下 12pt，约 48pt 高；名称 14pt，计数 12pt；只展示有成员的分类 |
| 设备行 | 30pt 图标、12pt 图文间距，内边距左右/上下均 16pt/12pt；名称 12pt、参考行高 20pt，参数 12pt、参考行高 16pt；普通行约 60pt，长名称允许合理增高 |
| 分隔 | 分类头底部及非末尾设备行使用细分隔线；卡片最后一行圆角收尾，不出现多余分隔线 |
| 参数 | 复用保存的 SceneParameters：调光器显示亮度，支持 CCT 时追加色温，Relay 显示 ON/OFF，关闭设备显示 OFF；不拿实时灯态替换场景目标值 |
| 操作 | 详情始终只读，不显示搜索、选择、折叠、设置、删除、Identify、Preview 工具栏；点击分类或设备不发送控制命令 |

分组复用当前 Node 归属，未分组在最前，其余沿用现有组地址排序；设备移组后展示位置更新，但不改变场景成员或参数。设备图标继续使用实际产品图标，缺失身份保留地址占位和成员数，不能把重用相同地址的新设备当作原设备。设计中灯泡为示例，设备图标是业务动态内容。

正常同步完成时不显示常驻 Saved parameters 说明，使布局与设计一致。设计未提供异常态，建议保留最小必要的条件提示：已确认待同步时显示原 Pending sync 语义，存在移除任务时显示待清理数量；成员行保留必要的待同步标识。未拿到快照不直接当作已完成或已确认失败，不把旧快照继续用于新配置。空场景有清理任务时仍使用默认空页，仅补充简短待清理状态，不恢复设备工具栏。

## 页面判定与刷新边界

| 保存状态 | 详情展示 |
| --- | --- |
| Devices 且 `deviceMembers` 非空 | 新设备卡片详情；离线、断连、缺失 Node 均不触发空态 |
| Devices 且 `deviceMembers` 为空 | 默认 Scene 空页；隐藏设备摘要及卡片，场景名恢复默认布局 |
| Devices 零成员且有 pending remove | 同上，并保留必要的清理状态；任务、容量占用与 Sync 重试沿用现有机制 |
| Groups 或合法旧格式无 configuration | 原 Groups 详情/空态 |
| 配置读取失败或详情解析失败 | 不解释为正常零成员，不展示成功同步；给出必要的不可用反馈，保留已有权限和恢复保护 |

空态只响应已保存配置：在 Settings 删除但未保存，不提前改变详情；保存成功返回、重新长按、退出重进/重启后均按最新保存成员重建。保存失败继续显示旧配置。后续重新加入设备并保存，恢复设备卡片布局。

每次模式切换同步处理标题、设备视图、Groups 网格、分页控件及约束；不能出现设备视图已移除但网格仍隐藏，或默认空态残留标题/分页。复用现有通知、页面 revision 和 `SceneGroupDisplayState` 异步读取/取消机制。同步状态更新优先更新当前内容，避免无意义重建导致滚动位置跳回；离开页面后的迟到回调不改变已退出页面。改名后同时刷新当前使用的导航标题/内容标题。

Settings 再次进入仍依据保存类型选择 Devices；空页回退不自动切换 Settings 选项。用户若主动切换 Groups，继续服从已有空配置及待清理限制。

## 最小实施范围与复用选择

1. `SceneViewController.swift`：区分保存类型与详情布局；补零成员回退、失败状态和设备/默认布局切换；保持原菜单、权限、Groups 点击与长按行为。
2. `SceneDevicesSelectionView.swift`：扩展已有只读展示模式，复用成员/分类/身份/参数数据路径，增加居中摘要、分类计数与独立卡片；只读模式不提供折叠或控制事件。直接使用编辑模式会带入预览/删除等工具栏与整块卡片样式，因此不适用；另建完整详情组件会重复数据逻辑，本次不采用。
3. `SceneDeviceSettingsCell.swift`：明确只读布局的尺寸、白底与圆角，复用设备图标和标签；检查复用时隐藏控件、回调、字体、颜色和约束重置，避免影响 Settings / Select devices。
4. English / 简体中文：复用现有摘要、未分组、空态和同步 Key；按需要补设备计数单复数与不可用文案，避免直接复用 `%d selected`。不硬编码用户可见文案。
5. 现有 Scene 测试中补展示判定与刷新行为；不修改配置格式、持久化、删除任务或 SDK 协议。

全部品牌共享这些组件。实施时核对 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 的文案/资源归属和主题映射；图标优先复用现有资源，只有设计静态资源确实缺失时才补充并检查各品牌配置。

## 验证与验收

- 展示判定：非空、零成员、全部离线、缺失身份、零成员待清理、旧 Groups、配置损坏；零成员回退不能改变 kind、pending operations 或保存数据。
- 状态转换：编辑删除最后一台后保存成功/失败，详情即时更新、退出重进；重新加入后恢复；名称/设备分组变化；同步完成/取消/迟到快照；单复数与空分类不显示。
- 复用回归：运行现有 selection 与详情同步展示回归，并针对共享 cell 检查两种编辑页面仍保留设置/删除/Identify；若改动触及事件路由，再运行相关 Devices 实时控制回归。持久化路径只复用既有语义，不为纯布局改动机械全量运行存储测试。
- 布局核对：Figma 正常态的摘要位置、卡片间距、圆角、图标、字号与分隔；1/多设备、长名称、中英文、小屏、iPad 弹窗、大列表滚动；隐藏控件不留下占位。
- Swift 修改完成后核对实际 workspace/scheme/SDK realpath，运行一次 SunSmart Debug generic iOS 构建，使用该工作树固定 DerivedData、关闭签名；文案/资源有跨品牌编译风险时按项目规则补覆盖。此次规划未执行这些检查。
- 用户最短验收：长按有成员 Devices Scene 核对卡片 → Settings 移除全部并保存 → 回详情及重新进入均显示默认 No members → 再加入设备保存恢复卡片。补测离线成员仍显示、清理失败仍可重试，以及普通 Groups 页面不变。自动化与编译不代替真实 UI 体验验收，不自动操作真机。

## 实施与验证记录（2026-10-31）

已按用户确认范围实施：

- 详情使用明确的只读展示模式：居中摘要、各分类独立圆角卡片、右侧成员数、设备图标/名称/保存参数；不挂接选择、设置或 Identify 回调，不显示搜索/折叠/编辑工具栏。
- 非空 Devices 使用新布局；保存成员为零时恢复默认标题、网格空态和分页状态。读取或解析失败显示不可用提示；离线与缺失设备仍保留原身份成员。缺失设备使用已有未知设备图标。
- 保留 pending remove，不改保存类型、存储、删除及同步协议；零成员待清理使用默认空页加条件提示。已确认的同步状态与持久任务才显示提醒，不将未返回/过期快照当作待同步证据。
- 更新已保存草稿时复用详情实例，列表刷新后保留并按内容范围约束滚动偏移；改名同步更新导航标题。设备视图移除、默认视图恢复与反向切换统一处理。
- 复用现有图标、颜色和布局组件；补齐英文单复数及简体中文文案。未新增资源、工程配置、依赖或 SDK API。

已通过的自动验证：

| 检查 | 结果与边界 |
| --- | --- |
| `SceneDetailsPresentationTests.py` | 22 项：执行生产展示判定、页面更新、空态及状态方法，验证非空→零成员→重新加入、实例复用、改名、权限、失败/旧格式、清理提示及过期快照；UIKit 使用值接收替身，不证明实际布局或滚动体验 |
| `SceneDetailSyncDisplayTests.py` | 6 项：原 Groups 详情同步状态及取消/迟到读取 |
| `check_scene_configuration.py --suite selection` | 35 项及 DeviceNameFilterSession 测试，覆盖既有选择、共享草稿、退出、离线、分类/单台入口 |
| `SceneDeviceLiveControlTests.py` | 46 项通过，Devices 单台 UNACK 与分类不发送等既有行为回归 |
| `SceneGroupLiveControlTests.py` | 22 项通过，Groups 原实时控制回归 |
| 文案/资源 | 两种语言 strings 格式检查通过；五个品牌均引用同一 Localizable.strings 变体；复用导航和未知设备资源存在且非空 |
| SunSmart 编译 | 11:42 Debug generic iOS 编译通过，`SunSmartLocal.xcworkspace` / `SunSmart`，固定 `SunSmart-feat-device-scene-261028-cli` DerivedData，`CODE_SIGNING_ALLOWED=NO` |
| 差异检查 | `git diff --check` 通过 |

SDK 实际来源为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `ccdf101`；构建沿用已有 `MeshMessageManager.swift` 未提交修改及 `MeshGroupControlSession.swift` / `check_group_control_session.py` 未跟踪文件，本任务未触碰 SDK。正式依赖未变。

共享 Swift 无品牌条件差异，文案沿用已存在的共享资源变体，因此本轮以 SunSmart 为代表构建；其余品牌仅核对资源归属，未运行品牌完整编译。未运行 Simulator、未安装或自动运行真机。

待用户验收：按上文最短步骤检查真实卡片布局、长名称、中英文、小屏/iPad、滚动刷新、全部移除后的默认空页及再加入恢复；设备离线或身份缺失时仍有成员，待清理状态仍可走原同步重试。编译和隔离回归不代表这些真实运行路径已验收。
