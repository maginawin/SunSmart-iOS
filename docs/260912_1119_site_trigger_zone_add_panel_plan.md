# Site Trigger Zone 添加面板：需求分析与开发方案（展示与筛选范围已确认）

日期：2026-09-12。工作树：`site-tz-plus`，App 基线 HEAD：`86b97c5c`。本文最初记录需求分析与方案；用户随后要求继续开发，并明确使用 MtestiPhone15 自测。实施结果见 [开发与自测记录](260912_1237_site_trigger_zone_candidate_delivery.md)。本次用户要求优先于历史方案和原型中的旧连接流程。

**结论与建议范围**

需求总体合理。Site 层先按 Space 选择，再展示该 Space 下符合 Proximity Profile 条件的设备，符合现有空间归属；未建立当前添加会话的 Mesh 连接时，Manual 展示离线设备、Trigger 不产生检测结果，也合理。

建议一个开发 session 覆盖：选中 Zone 后的添加面板、Space 选择、资格和权限筛选、三模式共享筛选状态、Manual 真实候选设备及离线样式、Quick Start 空操作、Trigger 空状态、Space Trigger Zone 的菜单文案修正，以及相应回归验证。

本轮不宜同时承诺真实成员添加、成员保存和跨 Space 设备同步。当前真实数据只支持空 Zone；非空卡片及 Remove/Reset 等成员交互位于 Debug 预览。把设备加入真实 Zone 需要补成员身份、解析、草稿、权限及持久化契约，并非把现有添加回调接上即可。

用户已于本轮后续明确确认：“本轮只展示与筛选设备”。Manual 本期仅展示真实候选设备并支持筛选，不产生成员草稿，不实现成员添加或保存。设备点击不执行操作，也不新增本地选中高亮；原方案中的高亮建议取消。其余标为建议的空态文案和交互细节仍保留方案属性，本次确认不扩展为真实成员功能。

**资料与证据范围**

| 输入 | 本轮处理 |
| --- | --- |
| [跨 Space 能力分析](260909_0934_site_trigger_zone_brainstorm_analysis.md) | 读取；保留独立业务数据、稳定身份、完整权限范围与最终设备拓扑统一规划的约束 |
| [Key 作用域与权限补强分析](260909_0959_site_trigger_zone_key_scope_permissions_analysis.md) | 读取；保留整 Zone 成员 Space 的 Owner/Editor 校验、受限摘要及显式网络上下文要求 |
| `260909_1733_site_trigger_zone_prototype_flow_comparison.md` | 当前工作树未找到；本仓库可见 Git 历史及相邻工作树搜索也未找到。不能声称已读。前两份文档包含其原型核对回填内容，本轮将这些内容作为历史摘要参考；原文补齐后可复核差异 |
| [本次 Figma：600:8516](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=600-8516) | 通过 Figma connector 的 get_design_context 获取结构、样式及参考图；不是网页或 OCR 分析 |
| 当前 App 源码与现有测试 | 重新核对；不把历史实现文档的测试成绩当成本轮结果 |
| 本地 NordicSigMeshSDK | 指定目录存在且工作树干净；HEAD `a6246b1` 与 App Package.resolved 一致。本轮仅阅读相关数据 getter/加载实现 |

方案编写阶段未构建或运行 App。后续已执行开发、品牌构建和 MtestiPhone15 独立测试宿主验证；未连接或操作 Mesh。

**已经收敛的功能规则**

| 项目 | Site Trigger Zone 本轮规则 |
| --- | --- |
| 添加目标 | 当前选中的稳定 zoneId；标题继续为 Add to Zone N，编号仅作展示 |
| 候选范围 | 当前 Site 中，当前用户具备有效 Owner/Editor 权限的 Space 内设备 |
| Group 资格 | 沿用现有 `.proximityLighting` 和 `.proximityLightingWithPhotocell` 两类；普通 Profile 不符合条件 |
| 左侧选择器 | 选择 Space，不提供 All，不提供第二层 Group 选择；菜单列出当前 Site 可获得的全部 Space 摘要 |
| 默认 Space | 按 Site 原始 Space 列表顺序，选第一个有合格 Group 且有有效编辑权限的 Space；不使用当前页面搜索/收藏/网关过滤后的子集 |
| Manual 候选 | 当前 Space 内全部合格 Group 的设备并集，经去重和“已添加”过滤后展示 |
| Manual 设备状态 | 使用与 Site Zone 卡片相同的离线图标和颜色；只是本页面无连接时的展示策略，不修改 Node 在线状态缓存 |
| Quick add | 首次默认模式；保留现有控制区，Start 点击不启动任务，也不切成 Adding/Pause/Stop 状态 |
| Trigger add | 本轮不建立 Mesh 添加会话、不监听检测结果，候选结果保持为空，不复用其他页面遗留的 triggerDevices |
| 右侧菜单 | Ignore added devices / Show the devices added in other Zones，三模式一致 |
| Ignore 作用域 | 只考虑当前 Site 的 Site Trigger Zones；Group Path、Group Trigger Zones、Space Trigger Zones 均不参与这个过滤 |

这里的“离线”不等于设备物理断电，也不应成为未来离线草稿选择的资格限制。新增候选仍必须有正确 Group/Profile 和权限。

历史原型中“选 Zone 或切模式立即连接 Space”的流程，本轮由用户明确的“保持 Site 页面栈、不连接、Quick Start 暂无功能”替代。历史 Key、Relay、TTL 和同步约束保留到真实设备接入阶段，不在本轮实现。

**需要补齐的边界与推荐行为**

1. 区分 Space 可见、可选与可编辑。

下拉菜单保留当前账号在 Site 中可获得的全部 Space。Owner/Editor 且资格已确认的 Space 可选；没有合格 Group 的 Space 用现有非 Proximity Group 的置灰样式。Visitor、No access、密码待验证、权限未知也不可选，原因不能统一写成“没有 Proximity Group”。

复用 `SpaceData.canEditing` 所表达的有效权限条件，而非只检查 role 字符串；不因为用户是 Site Owner 就假定其能编辑每个成员 Space。占用、OTA 等状态如需展示，应单独表达，不改写 Owner/Editor 角色。本期纯候选浏览不申请跨 Space 编辑租约。

`site.spaces` 是现有导入的数据列表，不能证明包含服务端未公开的 No access Space。本文的首期范围是该列表及已有获授权摘要。若“所有 Space”还要求列出当前接口完全不提供的 Space，需要另补完整摘要接口，不能生成假 SpaceData 或下载其设备/密钥来凑列表。现有 Zone 中受限 Space 摘要仍按之前的完整展示规则保留。

2. “有合格 Group”与“有可添加设备”分开判断。

合格 Group 内暂时没有设备，其 Space 仍可选，也可以成为默认 Space；显示 No devices。不能因设备为空或被 Ignore 全部过滤，就跳到后面的 Space，否则不符合“默认第一个有合格 Group 的 Space”。

3. 默认值与切换记忆。

首次进入：Quick add、Ignore added devices、第一个合格 Space。页面存续期间三模式共享同一 Space 和右侧筛选值；切换 Zone 保留这两项及当前模式，并重新计算目标 Zone 的过滤。切换 Space 重置分页与 Trigger 结果，回到第一页。Site 候选设备本期不维护点击选中态。

以 spaceId 保存选择，刷新或排序不能让数组索引指向另一个 Space。原选择失效时，改选下一个按列表顺序找到的合格 Space；没有则设为无选择。刷新不能无故抢走仍有效的选择。退出页面后下次进入重新应用默认值，本期不做跨重启偏好持久化。

4. 只读 Zone 与空面板的可达性。

已有非空 Zone 只要任一成员 Space 为 Visitor、No access、未知或未确认，整 Zone 保持 View only，不能仅因候选列表里存在其他 Owner/Editor Space 就开放添加。

当前 Site 菜单和空 Zone 的编辑资格都要求至少一个可编辑 Space；零 Space 时通常连入口都不会出现。因此 No spaces 主要覆盖页面打开后的数据变化和预览/测试状态，不借本次需求扩大 Site 菜单权限。

若页面已打开、选中的是已确认空 Zone，随后 Space 被清空或权限失效，建议允许面板显示对应解释性空态，所有变更操作禁用。实现需将“允许显示空态”与“允许编辑”分开。未选 Zone 或整个 Zone 列表为空，维持现有引导；不会为展示 No spaces 自动创建或选中 Zone。

**空状态方案与英文文案**

优先区分：数据是否已确认 → 是否有 Space → 是否有可编辑 Space → 是否有合格 Group → 是否有设备 → 是否被过滤。加载失败不是空列表。

| 场景 | 左侧选择器 | 内容区 | 操作 |
| --- | --- | --- | --- |
| 确认 Site 没有任何 Space | No spaces | 不重复添加解释文案 | 无选中项，禁用下拉 |
| 有 Space，所有可编辑 Space 均确认没有合格 Group | No eligible spaces | Assign a Proximity Profile to a group in a space you can edit. | 无选中项；下拉仍可展开查看置灰条目 |
| 有 Space，但没有任何有效 Owner/Editor Space | No editable spaces | Owner or Editor access to a space is required. | 无选中项；菜单保留可公开的 Space 及权限原因 |
| 正在获取/读取资格 | Loading spaces… | 按实际加载状态展示 | 未知项不可选，不显示“无合格 Group” |
| Space/Group/Profile 数据缺失或加载失败 | 失败条目禁用 | Space data unavailable，提供 Retry | 可用 Space 仍可使用；不能把失败 Space 当作无 Group |
| 当前 Space 有合格 Group，但没有设备 | 保留 Space 名 | No devices | 不自动换 Space |
| Ignore 排除了全部候选设备 | 保留 Space 名 | No new devices；可提示切换右侧过滤以查看其他 Zone 中的设备 | 右侧筛选可切换 |
| Include added 下仍无候选，例如设备均在当前 Zone | 保留 Space 名 | No devices available to add | 当前 Zone 的成员不能重复进入候选 |
| Trigger 模式，Space 资格有效但本轮未连接 | 保留 Space 名 | Not connected to a space | 无检测设备；不提供无效扫描或自动重连 |

对用户提出的“有 Spaces 但都没有 Proximity Profile Group”，推荐 **No eligible spaces + 一句设置 Profile 的指引**。它同时解释为什么所有 Space 置灰，并保留用户查看已有 Space 的能力。

对应中文依次可用“无空间”“无符合条件的空间”“请在你可编辑的空间中，为一个组设置邻近照明配置。”“无可编辑空间”“需要空间的所有者或编辑者权限。”“正在加载空间…”“空间数据不可用”“无设备”“无新增设备”“无可添加设备”“未连接空间”。最终新增 Key 时两种支持语言同步补齐。

现有 `no_spaces` / `no_spaces_title` 带感叹号，本轮要准确显示 No spaces 可新增局部 Key，避免全局修改其他页面。No devices 等已有适用 Key 优先复用。

**右侧过滤的准确语义**

| 设备归属 | Ignore added devices（默认） | Show the devices added in other Zones |
| --- | --- | --- |
| 未加入当前 Site 的任何 Site Zone | 显示 | 显示 |
| 只在当前 Site 的其他 Site Zone | 隐藏 | 显示 |
| 已在当前选中 Site Zone | 隐藏 | 隐藏 |
| 同时在当前及其他 Site Zone | 隐藏 | 隐藏 |
| 只加入 Group Path / Group Zone / Space Zone | 显示 | 显示 |

所有“显示”仍须满足当前选中 Space、有效编辑权限和 Group/Profile 资格。第二项表示“额外包含其他 Site Zone 已添加设备”，不表示“只显示已添加设备”。

过滤按同一份 Site 成员快照计算；未来接草稿后应以有效草稿覆盖对应已保存 Zone，不能只读服务器旧值。身份至少使用 siteId、spaceId、nodeUUID；地址只作当前映射，不能按不同 Space 的短地址全局去重。一个设备被多个合格 Group 解析到时只显示一次，Group 归属歧义应记录为不可用数据，不能随意归入另一个 Group。

当前真实模式中的 Zone 都为空，因此两种过滤实际显示相同列表是正确结果。本轮用独立 Debug 样例和策略测试覆盖“已加入其他 Site Zone”的差异，不向真实 Site 塞入演示成员，也不移除现有非空数据保护。

Space Trigger Zone 三模式统一改用 Zones 文案，过滤仍限定该 Space 自己的 Trigger Zones。Group Sequence 的 Paths 文案保留。Group Trigger Zone 已有 Zones 文案，本期不必顺带改其其他行为。

菜单展开项复用 `quick_add_ignore_added_devices`、`zone_trigger_add_show_added_devices`。折叠后的短标题建议为 New only / Include added；现有 Used 容易被理解为“仅已使用设备”。Include added 是待确认的轻量文案建议，需要用实际文本测量分配左右宽度，不能把长菜单全文塞进原 90pt 短按钮。

**三种模式的交互边界**

Manual：使用真实候选数据和离线外观，仅支持浏览、分页/展开及筛选。设备点击不执行操作，不显示点击选中高亮、不调用 Identify、不二次点击加入、不拖入 Zone。不应继续展示要求点击闪灯、双击添加或拖拽的旧帮助说明。Site 单独传入符合本期能力的提示；Group/Space 原帮助不变。

Quick：Start 保持原外观，点击为明确的空操作；无 Adding…、暂停/停止按钮变化，无任务、连接、定时器或设备写入。在切换状态前执行 Site 专用启动许可检查，不能只让控制器的回调为空，因为旧按钮会先更新 UI。

Trigger：保留 Tab、Space 与右侧筛选；候选为空，解释未连接原因。切进模式不注册 Mesh messageDelegate，不发送传感器配置、不读取别的页面检测缓存。无可选 Space 时优先展示相应资格/权限空态。

以上保持 Site 浏览模式。是否有历史全局在线缓存，不决定本轮是否显示在线或接受 Trigger 回调；未来连接会话必须显式具备目标 Site/Space/Zone 身份。

**开发结构与最小改动方案**

| 模块 | 计划改动 | 目的 |
| --- | --- | --- |
| 新增 Site 候选快照与筛选策略 | 建立 Space 选项、资格/加载状态、设备展示项、稳定身份及 Site Zone 成员过滤输入 | 让权限、默认选择、空态与去重可独立验证 |
| 新增 Site 候选读取适配 | 按 siteId / meshUUID / spaceId / subNetworkId 读取已有本地 Group、Profile、设备归属和名称；首次判断所有可编辑 Space 的 Group 资格，按需载入选中 Space 的设备 | 不切换全局网络；不要求先进入 Space 页面 |
| SiteTriggerZoneViewController | 管理选中 Zone、Space、模式和过滤状态；驱动面板；控制迟到刷新结果 | 防止目标串到另一个 Zone/Space，以及预览和真实数据混用 |
| SiteTriggerZoneContentView | 必要时增加解释性空态的显示能力；继续维护列表与面板约束 | 处理选中空 Zone 后零 Space/失权的状态，不放宽编辑权限 |
| GroupPathSequenceDeviceAddView | 最小拆开引导/候选展示与实际操作许可 | 当前 canAddDevice 同时控制显示模式，不能直接把“可展示候选”当作“可执行设备操作” |
| Quick / Trigger / Manual 共享视图 | 支持 Space 选项、无选择占位、禁用原因、Site 启动许可和菜单文案；旧配置入口保持兼容 | 复用现有外观和高度计算，避免复制整个 Space Controller |
| Manual 设备渲染 | 增加轻量展示数据入口或适配层；使用现有 Cell 与尺寸，Site 指定离线资源和关闭 Identify/拖拽 | 不为 UI 构造假的在线 Node，不靠修改设备缓存实现离线 |
| 英文、简体中文资源与工程 membership | 复用现有 Key/资源，补充空态和必要短标题；新增文件同步相关品牌 | 不影响其他品牌或 Sequence 文案 |

数据读取的具体注意点：

- SDK 的 `Group.nodes` 使用 `MeshNetworkManager.instance.realNodes`，不是 Group 自己所属网络的设备；不能对多 Space 对象直接调用它。
- `MeshNetwork.load` 虽不负责 BLE 连接，但存在补齐已使用地址后调用 `network.save()` 的分支，不能把它描述成完全无副作用的只读 API。
- 优先在 App 的候选读取适配中使用明确 Space 范围的现有数据读取能力；对需要显示的 UUID、名称、Group 订阅、Profile 类型生成不可变快照。必要时做局部只读数据投影，避免为了显示候选加载/修复整张网络或读取、生成 Auth/Key。
- 节点业务 Group 的判定保持与现有 Space 候选逻辑一致；不能为了绕开 getter，就直接套用更宽的“任意 Model 有订阅即算成员”策略而改变基础资格。缺失归属不借全局当前 Key 猜测。
- 读取失败必须能与成功读取零条区分；旧 API 的 try? / 空数组兜底不可直接作为“已确认无数据”。本轮只处理实际用到的候选字段完整性，不建立完整跨 Space 拓扑规划器。
- 页面刷新只读取候选和重算资格，不调用 Space 页面会清理 Zone 成员的 sanitizeSetZones，不自动删除 Profile 失效的既有成员。
- 异步读取绑定页面会话、siteId、spaceId 与请求版本；返回时校验仍有效。退出、切账号、切预览或选择变化后，旧结果不覆盖当前 UI。

Figma 差异已明确：参考节点是 Manual 选中态，包含 All eligible groups、New only、44pt 设备圆控件、分页、帮助和折叠控件。Site 将左侧改为 Space，右侧按本次语义配置；设备复用 `path_device_offline` 和 Site 卡片样式。沿用现有主题色、字体、尺寸与动态高度，不照搬参考代码的固定 343pt 内容宽度/160pt 高度。

**实施顺序与 session 工作量**

1. 按已确认的“只展示与筛选设备”边界，收敛 Space/过滤/空态细节；建立稳定身份和候选策略。
2. 实现按 Space 的本地读取适配；确认缺失数据不会变成“无 Group”，不会切换 Mesh 上下文。
3. 接入选择器和三模式共享状态，支持无选中项；调整 Space Trigger Zone 菜单文案。
4. 接入 Manual 离线设备、Quick 空操作、Trigger 未连接空态，并处理旧 Identify/拖拽/帮助入口。
5. 执行策略与既有数据回归、相关品牌构建、实际布局验收；记录证据及尚未验收项。

| 范围 | 工作量判断 |
| --- | --- |
| 上述候选展示与筛选阶段 | 中等且聚焦，适合一个开发 session；不是只改两段菜单文字，但边界可控 |
| 再加 Manual 临时成员草稿 | 可以单独作为下一 session；需要确定点击方式、Zone/Space 切换保留、离开提示、Reset/Remove、未保存标记，以及 Save 如何处理 |
| 再加真实成员保存 | 独立阶段；需冻结成员格式、允许非空数据解析、整 Zone 权限、持久化/云回读及冲突语义 |
| 再加真实 Quick/Trigger、Key 部署、拓扑与设备同步 | 明显超出本轮；按前两份文档拆分 SDK/协议、服务端、执行与恢复任务 |

过滤器界面只根据 Site Zones 排除候选，与后续设备最终拓扑需要合并 Group/Space/Site 关系并不矛盾。界面筛选独立，不能推导未来下发也能忽略旧 Path/Zone。

**验收清单与完成口径**

| 类别 | 必须覆盖 |
| --- | --- |
| Space 与权限 | 空 Site、仅 Visitor、Owner/Editor 混合、密码待验证、无合格 Group、两类 Proximity Profile、未知数据、长名称、同名 Space |
| 默认和切换 | 首个 Space 不合格而第二个合格；首个合格 Group 无设备仍选中；刷新重排保持 ID；切模式共享筛选；切 Zone 更新排除集合；选中 Space 失效回退或无选择 |
| 设备身份与过滤 | 多合格 Group 合并去重、跨 Space 同地址/同名不冲突；当前 Zone 永不重复；只在其他 Site Zone 的成员受开关影响；Group/Space Zone 成员不影响 Site 候选 |
| 零副作用边界 | Manual 点击不改变设备选中态、不 Identify、不添加、不拖拽提交；Quick 点击无状态变化；Trigger 不监听；不改当前 Mesh 网络/Key、设备缓存、Zone members 或候选读取无关的数据库内容 |
| 原功能回归 | Space 三模式菜单为 Zones，All eligible groups 保留；Group Sequence 仍为 Paths；Group/Space 原添加与 Identify 流程不因 Site 参数变化而被禁用 |
| UI 实际布局 | 中英文，iPhone 窄屏/常规宽度、iPad 宽度、旋转/窗口宽度变化；下拉边界、长名称截断、两行空态、分页/展开收起、设备离线图标、列表与底部面板不互相覆盖 |
| 预览隔离 | Debug 样例覆盖已添加过滤和零 Space 等边界；真实 Space 候选不与预览 Zone ID/成员混算；Release 不引入演示成员 |
| 构建与资源 | 新文件和资源 membership；受影响的 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 构建；英文与 zh-Hans Key 完整 |

实际布局测试使用生产 UIKit 视图扩展现有 `Tests/UI/SiteTriggerZoneItemLayoutProbe.swift` 或同类探针。遵守用户规则：直接运行 generic iPhoneOS 的 xcodebuild，不使用 Simulator，不以编译或静态检查替代实际布局。

用户已明确要求“使用 MtestiPhone15 自测”，覆盖默认不做真机测试的限制。本次在该设备的独立宿主中运行生产 UIKit 控件和页面交互探针；中英文均通过。XCTest runner 连接失败的限制及替代验证证据见开发记录，不把未执行的 XCUITest 报为通过。

本轮已执行 `bash scripts/check_site_trigger_zones.sh`，两组现有检查均通过：空 Zone 身份/数量/兼容/pending/冲突/重启；29 个 Item 样例、权限、完整性、受限摘要、同步范围和预览隔离。这只是当前基线，不是拟议新功能的验收成绩。

**确认记录与其余建议**

- 已确认：本期只展示与筛选真实候选设备；Manual 设备点击不执行操作，成员添加、草稿、保存后续安排。
- 接受 No eligible spaces 及设置 Proximity Profile 的指引；无权限、无设备和加载失败分别提示。
- 接受菜单中可获得的全部 Space，只有有效 Owner/Editor 且有合格 Group 的 Space 可选；完整隐藏 Space 摘要接口若当前缺失，单独安排。
- 接受三模式共享 Space/过滤状态、Quick Start 完全空操作、Trigger 未连接空态；右侧短标题建议 New only / Include added。

本期成员功能的范围选择已完成，不再重复询问。后续仅在用户明确新增成员添加或保存需求时另行规划，不能在本方案名义下默认接入旧 Space 的设备写入回调。
