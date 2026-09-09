# Site Trigger Zone Item 组件与模拟展示开发方案

日期：2026-09-09。状态：用户已确认；代码与自动检查已完成，真机布局待验收。下文保留方案制定时的分析与验收范围。

## 1. 结论与建议范围

需求合理，适合实现为一个由数据驱动的 Site 专用组件。Space 数量、权限组合、选中状态与待同步状态应独立组合，不为每个 Figma 样例创建不同 Cell。

本期建议交付：非空 Zone 的新展示组件、独立展示模型与权限/同步展示规则、真实/模拟数据切换、覆盖 0/1/2/3/4 个 Spaces 的模拟列表，以及实际布局验收。现有 `No Data` 未选中/选中样式保持现状。

现有真实数据只支持空成员 Zone。因此本期“真实模式”继续呈现已有真实空 Zone 和原有云端保存能力；新组件的非空状态先由模拟数据完整展示，预留真实成员适配入口。真实非空成员的服务端契约、设备同步任务生成、跨 Space Mesh 操作另行开发。不能为了演示取消当前非空数据保护，或把模拟数据写入真实 Site。

## 2. 已核对的现状

| 位置 | 当前行为 | 对本次开发的影响 |
| --- | --- | --- |
| `SiteTriggerZoneContentView.swift` | 输入只有 zoneIDs；每个 Zone 为一个 section、一个 72pt 空 Cell；选中时黄边；表头复用 Group 组件 | 改为接收展示模型；空项保留原有 Cell/表头分支，非空项使用 Site 专用表头和卡片 |
| `SiteTriggerZoneViewController.swift` | 右上角为 +；选择后展开添加面板；canEdit 为整页布尔值 | 保留 +，并列增加模式切换；分开页面创建权限与单 Zone 操作权限 |
| `SiteTriggerZoneData.swift` | members 保留为原始 JSON；supportsEmptyZoneEditing 要求所有 Zone 都为空 | 不把原始未知成员强解为 UI 设备；不改变持久化 schema |
| `SiteTriggerZoneCoordinator.swift` | 已有增删、按 zoneId 保存、Site 云同步 pending；没有成员 Space 同步账本 | 当前 Site 级 pending 不能直接映射为每个 Space 都待同步 |
| `SiteData.canManageSiteTriggerZones` | 当前 Site 任一 Space 可编辑即可 | 继续用于入口/创建空 Zone，不能用它放行非空 Zone |
| `SpaceData.canEditing` | Owner/Editor 且未失权、无需密码重新验证 | 角色与当前有效编辑能力必须分开；不能只看角色字符串 |
| `Permission` | 只有 Owner/Editor/Visitor | 新增展示专用 noAccess/unknown，不修改共享权限枚举语义 |
| `GroupPathSequenceTriggerZoneViewCell` | 依赖 Node、当前节点 state、Identify/Remove、拖放 | 不直接复用整个 Cell，以免带入 Mesh 交互和在线状态 |
| `GroupPathSequencePathItem` / Metrics | 已有 44pt 圆形设备、20pt 图标、8pt 行距 | 复用低层视觉资源与尺寸；Site 绑定时始终使用静态设备外观 |

当前工作区在本轮开始时无未提交改动。此前方案中的 `extensionData` 字段名、空 Zone 即时持久化、行 Save 仅保存当前 zoneId 的语义继续保留。

## 3. Figma 结构化核对

已使用 Figma connector 的只读 Plugin API 查询六个节点的结构、可见性、文字、尺寸与样式；未修改 Figma。以下为设计事实，后文另行标明补充建议。

| 节点 | 对应状态 | 设计细节 |
| --- | --- | --- |
| [615:4211](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=615-4211) | 单 Space、Owner、未选中、无同步标记 | 2 个设备；无分隔线 |
| [615:4065](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=615-4065) | 两 Space、均 Owner、未选中、无同步标记 | 两组设备共用一张白卡；中间 1 条分隔线 |
| [615:4255](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=615-4255) | 两 Space、均 Owner、选中、待同步 | 黄边；Test/Reset/Delete/Save；第一 Space 标题右侧有同步图标，第二个没有 |
| [615:4730](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=615-4730) | 两 Space、均 Editor、未选中 | Editor 橙色标签；第一 Space 有 7 个设备，按 5+2 换行 |
| [615:4623](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=615-4623) | Editor + Visitor、选中、待同步 | Zone name 后为带眼睛图标的 View only；两个 Space 名称左边都有锁，包括 Editor；仅第一 Space 有同步图标 |
| [615:5001](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=615-5001) | Editor + No access、未选中 | 无黄边但仍有 View only；两个 Space 都带锁；No access 保留 Space 名称和设备数量，设备区域替换为无访问权限提示 |

### 3.1 尺寸与颜色基线

- 卡片参考宽度为 335pt，白色背景、圆角 10pt、内边距 16pt。宽度必须随实际容器变化，335 只是设计基准。
- Zone 标题 14pt，标题与卡片间距 8pt。Space 名称 14pt，角色/数量主要为 12pt。
- Space 标题参考高度 24pt，与设备区间距 20pt。设备圆形为 44×44pt、图标 20×20pt；参考水平间距 18pt，设备行距 8pt。
- 两个 Space 之间为 16pt 留白 + 1pt 分隔线 + 16pt 留白；N 个 Space 显示 N−1 条线，首尾无额外线。
- 选中边框 1pt 黄色，接近现有 Yellow_Color；它表示选中，不表示待同步。
- 权限标签：Owner 紫色、Editor 橙色、Visitor 蓝色、No access 红色；常见圆角 6pt、背景同色约 15% 不透明度。
- 锁图标 16pt；Space 同步图标 24pt；View only 为浅灰背景、眼睛图标加文字。
- 四个操作按钮顺序为 Test、Reset、Delete、Save；参考视觉尺寸 44×28pt、间距 8pt、圆角 5pt。

### 3.2 设计样例中需要归一化的地方

1. 部分 Space name 包含 `owner 4 devices`，同时旁边又存在独立角色/数量节点；这是样例内容重复。实现分别绑定 Space name、role、Zone 内设备数，不拼接重复文本。
2. 615:4255 第一 Space 的计数为 2，但设备图标有 3 个。实现按实际成员统计；模拟数据也保证计数与成员一致。
3. 同组设计存在 Space header 18/24pt、权限字体 11/12pt 的差异。建议统一为主要组件的 24pt 标题基线和 12pt 标签，内容不足时不硬编码整个卡片高度。
4. 选中态 Figma 的按钮局部 y 为 −7，超出 17pt 标题容器。实现使用可容纳按钮的完整约束，不复制越界坐标。
5. 现有设备名称使用约 8–10pt 的自适应文字，Figma 为 12pt。建议仅在 Site 设备展示中使用 12pt 基准和长名称截断/必要适配，不改变 Group/Space 的字体行为。
6. Figma 角色为小写，现有英文国际化值为 Owner/Editor/Visitor。建议复用现有大小写与 Key；新文案使用 No access、View only。若要求严格小写，再新增 Site 专用 Key，不修改共享翻译。
7. 按钮文字沿用各品牌 Bar_Color，而不是将 Figma 的紫色硬编码到全部品牌；标题、辅助文字、黄色边框优先使用已有主题色。

## 4. 状态与权限规则

### 4.1 状态独立建模

| 维度 | 建议内容 |
| --- | --- |
| 内容 | 已确认空 Zone；有成员且有完整 Space 摘要；摘要不完整/未知格式 |
| 选择 | 未选中 / 选中，以稳定 zoneId 管理，不依赖 indexPath |
| Space 访问状态 | owner / editor / visitor / noAccess / unknown；另有角色确认、有效授权等信息 |
| Zone 编辑能力 | 来自完整成员 Space 清单的统一计算；与按钮业务是否已实现分开 |
| 云同步 | 已知无待处理 / 待处理 / 未知；保留 Zone 级与可归属 Space 级范围 |
| 设备同步 | 同上；独立于云同步，不能因为云端成功就清零 |
| 设备外观 | Site 专用静态灰色展示，不订阅 Node.state 或连接状态 |

选择、权限、同步互不覆盖。只读 Zone 可以被选中，也可以需要同步；全为 Owner/Editor 的 Zone 可以选中但不需要同步。

### 4.2 编辑规则

- 非空 Zone：完整成员 Space 清单已知，且每个 Space 都有有效 Owner/Editor 编辑授权，才具有编辑能力。Owner 与 Editor 混合也允许。
- 任意 Visitor、No access 或未确认的成员 Space 会阻止编辑；不能只遍历本地已导入 Spaces 后计算全部可编辑。
- 仅角色为 Editor，但密码待验证或授权已失效时，不改写其角色为 Visitor；使用独立能力/状态表达。
- 已确认空 Zone：沿用现有入口/创建空 Zone 的权限，不使用“空数组的 allSatisfy 为真”来自动授权。
- 全部 Visitor 或全部 No access 的 Zone 仍保留。它们可以与其他可编辑 Zone 位于同一 Site；本期不扩展“仅有 Visitor 的用户进入页面”的入口规则，模拟模式可独立展示这些卡片。
- 未来接入真实变更时，控制器/协调器仍须重新验证 zoneId 和权限；只隐藏按钮不构成业务权限检查。旧新成员清理和跨 Zone 影响范围按后续业务方案检查。

### 4.3 展示规则

| Zone 状态 | Zone 标题 | 卡片 | Space 标题 | 添加面板 |
| --- | --- | --- | --- | --- |
| 可编辑、未选中 | 名称 | 无黄边 | 实际角色，无锁 | 保持未选中行为 |
| 可编辑、选中 | 名称 + Test/Reset/Delete/Save | 黄边 | 实际角色，无锁 | 沿用可编辑选择流程 |
| 只读、未选中 | 名称 + View only | 无黄边 | 每个 Space 都有锁，保留实际角色 | 不作为添加目标 |
| 只读、选中 | 名称 + View only，不显示按钮组 | 黄边 | 每个 Space 都有锁，保留实际角色 | 隐藏，不保留上一可编辑 Zone 的目标 |

`View only` 与锁始终表达整个 Zone 的不可编辑状态；锁不表示该 Space 的角色被降级。unknown 状态也禁止操作，但辅助文案为权限待确认，不能显示成已确认 No access。

点击标题、卡片空白或设备区域都可选择 Zone；本期设备点击不出现 Identify/Remove，不进入 Space、不连接 Mesh。重复点击已选项保持选中，沿用当前行为。

所有设备固定使用类似离线的中性图标和文字色。这里表示 Site 上下文未连接 Mesh，不新增“设备已确认离线”的事实性文案。

### 4.4 No access / 未知摘要

No access 使用设计中的红色权限标签，设备区域显示：`You don't have access to this space · Contact the space owner to request access`。整段支持换行和国际化；本期为提示文字，不增加联系或申请操作。

只显示服务端明确允许公开的名称与设备数量，不读取受限 Space 的节点或密钥，不创建假的 SpaceData。数量未知时隐藏数量，而不是显示 0；名称未知时显示本地化的 Space 占位名称。Visitor 仅展示其授权范围允许的设备摘要。

Space 数量按完整引用列表计算，所以 3 个全 No access 的 Space 仍有 3 个分区、2 条线，不能退化为 No Data。未导入、加载失败或数据不完整也不等同于零成员。

## 5. 同步标记规则与待补充设计

- Zone 待同步 = Zone 自身有云端待提交任务，或任意成员 Space 有属于该 Zone 的云端/设备待处理任务。
- Space 待同步只统计此 Zone 在该 Space 的任务，不能拿整个 Space 的通用云同步状态代替。
- 有明确归属的任务：在受影响 Space 标题右侧显示 Figma 的同步图标。只读、未选中时也显示；与黄色选中边框无关。
- 同一 Space 同时有云端和设备任务：仍为一个图标，展示模型保留两种原因，供后续详情使用。
- 只有 Zone 元数据的云任务、无法归属某个 Space：建议在非空 Zone 标题处补一个相同语义的同步图标。此位置是补充方案，六个设计未覆盖，需要确认；不把图标任意放到第一个 Space。
- 真实空 Zone 的云同步继续使用现有页面提示，本期不改变 No Data 两种外观。Site 级删除等没有可见 Zone 可归属的任务也保留页面提示。
- 当前 Site 级 pending 如可通过 base/target 的稳定 zoneId 差异准确归属，则可生成 Zone 级显示状态；无法归属时保留页面级状态，不能将所有行标为待同步。
- 失败但任务尚未完成仍属于待同步；进行中、失败详情、点击重试等丰富视觉留到功能期。本期展示模型保留未知状态，不能因任务数据尚未加载就宣称已完成。

## 6. 组件与接入结构

| 建议组件/文件 | 职责 |
| --- | --- |
| `SiteTriggerZoneItemModel.swift` | 不依赖 UIKit、Node、数据库的展示快照；Zone/Space/设备稳定 ID、顺序、名称、授权摘要、同步状态；设备数量有明确已知/未知语义 |
| `SiteTriggerZoneItemPolicy.swift` | 完整性、编辑能力、只读标记、锁、同步聚合等纯规则；供真实和模拟模式共用 |
| `SiteTriggerZoneItemCell.swift` | 非空 Zone 的白卡、黄边与动态内容高度；只负责渲染和选择回调 |
| `SiteTriggerZoneItemHeaderView.swift` | 非空 Zone 标题、View only、四按钮、补充同步图标；自动高度，不修改共享 Group 表头 |
| `SiteTriggerZoneSpaceSectionView.swift` | Space 头部、权限 badge、数量、同步图标及设备区/受限提示 |
| `SiteTriggerZoneDeviceGridView.swift` | 无独立纵向滚动的设备网格；复用现有 tile 的可配置视觉、资源和 Metrics，逐行左到右排列 |
| `SiteTriggerZonePreviewFixtures.swift` | Debug 内存模拟数据；稳定 ID、可读场景名，不包含 Auth 或真实 SpaceData |
| 修改 `SiteTriggerZoneContentView.swift` | 接收展示模型；空数据走原分支，非空走新组件；以一个完整快照刷新，处理可复用 Cell 状态 |
| 修改 `SiteTriggerZoneViewController.swift` | 模式切换、独立选择状态、真实数据适配、面板和操作路由 |

以上可按实现规模合并小型内部类型，不为文件数量拆分代码。展示层不新增 SDK 依赖、不发网络请求、不读写真实配置。

设备身份至少使用 Space 身份 + 设备稳定身份组合，防止不同 Space 出现同地址、同名设备时串行。Space ID 和 zoneId 不能由名称或展示序号替代。

真实适配器本期只接受当前支持的空成员格式；未知或不支持的数据保持现有保护与提示。模拟适配器直接创建展示快照；它与后续服务端 members 编码没有绑定关系。

### 6.1 布局要求

- 保留现有 safe area → 状态栏 → 列表 → 底部面板约束链；非空 Cell 采用自动高度和合适 estimatedRowHeight，不继续使用固定 72pt。
- 空 Cell 仍使用现有 72pt、圆角、边距、No Data 字体/颜色与选中边框。
- 新非空项的标题与卡片左右对齐；页面横向边距复用当前体系，335pt 仅作为视觉参考。
- Space 数量是数组，不设 4 个上限。1 个无分隔线，2/3/4 个分别 1/2/3 条，更多时同规则。
- 网格按实际可用宽度计算列数；标准参考宽度为每行 5 个设备，窄屏减少列数，iPad 宽窗口可增加。不能只通过 isIPad 固定 8 列。
- 设备内容、No access 提示和标题换行共同决定高度；宽度变化时重新布局并更新列表高度，避免一次性 frame 高度缓存。
- Space name 优先压缩/截断，角色、锁、同步图标保持可辨认；窄窗口放不下时数量移至下一行。Zone 长标题给按钮留空间，极窄窗口允许操作组独立一行。
- 28pt 是按钮视觉高度，触控区域应在不与邻近卡片重叠的前提下扩展；通过实际布局验证。
- 复用时完整重设边框、View only、锁、同步图标、角色颜色、设备/受限文案、回调及约束，避免 4 Space → 1 Space 或只读 → 可编辑残留。

## 7. test 切换设计

建议导航栏同时保留 `+` 与 `Test`，后者复用已有 test 国际化 Key，默认仅在 `#if DEBUG` 开放。导航 Test 为“切换模拟展示”，行内 Test 为未来设备测试，两者使用不同回调与 accessibilityIdentifier。

| 流程 | 行为 |
| --- | --- |
| 页面首次进入 | 真实模式，正常加载已有数据 |
| 点击导航 Test | 保存真实选中 ID/滚动位置/面板状态；切入固定模拟列表，显示明确的 Preview mode 提示和按钮高亮 |
| 模拟模式选择卡片 | 同一时刻一个选中项；每个样例均可查看未选中/选中样式；只读项显示 View only |
| 模拟可编辑项的四按钮 | 可演示按钮点击反馈，但只显示本地化预览提示，不增删模拟项、不清空同步标记、不声称业务成功 |
| 模拟模式 +、空态 Add、添加面板、页面重试 | 不调用真实业务入口；创建/添加禁用，真实状态重试控件隐藏；只读项隐藏添加面板 |
| 再次点击导航 Test | 回到最新真实数据，若原选中 ID 仍存在则恢复；不存在则清除；滚动位置按当前内容校正 |
| 退出页面重新进入 | 默认真实模式，模拟模式与数据不持久化 |
| 真实异步同步在模拟期间返回 | 更新真实状态，但不覆盖模拟列表、模拟选择或展示成功 HUD；切回后显示最新真实结果 |

切入模拟不主动中断已开始的真实上传，也不清理真实 pending。模式切换只是展示切换；所有操作入口显式区分模式，避免遗漏某个回调把 fake zoneId 传入 coordinator。

## 8. 模拟数据覆盖矩阵

表中“待同步”拆分 Cloud、Device、Both。每个基础样例可交互切换选中/未选中；自动验收应分别覆盖两态。默认可选中一个可编辑且待同步样例，方便观察四按钮。

| ID | Space 数量 | 权限/内容 | 同步安排 | 目的 |
| --- | --- | --- | --- | --- |
| E01 | 0 | No Data | 沿用旧展示 | 两种空项外观回归 |
| S01 | 1 | Owner，2 设备 | 无 | Figma 单 Space |
| S02 | 1 | Editor | 无 | 用户补充 |
| S03 | 1 | Visitor | 无 | 单 Space 只读 |
| S04 | 1 | No access | 无 | 受限摘要，不能显示 No Data |
| S05 | 1 | Owner | Cloud | 单 Space 云同步 |
| S06 | 1 | Editor | Device | 单 Space 设备同步 |
| S07 | 1 | Visitor | Both | 只读仍显示待同步 |
| S08 | 1 | No access | 已知待同步 | 受限摘要与同步共存 |
| D01 | 2 | Owner/Owner，4+4 设备 | 无 | Figma 双 Owner |
| D02 | 2 | Owner/Owner | 仅首 Space 待同步 | Figma 选中同步，验证第二 Space 无图标 |
| D03 | 2 | Editor/Editor，7+4 设备 | 无 | Figma 设备换行 |
| D04 | 2 | Editor/Visitor | 仅首 Space 待同步 | Figma 黄边、View only、两处锁 |
| D05 | 2 | Editor/No access | 无 | Figma 受限分区 |
| D06 | 2 | Owner/Editor | 两 Space 分别 Cloud/Device | 混合可编辑，验证按分区同步 |
| T01 | 3 | 全 Owner | 无 | 2 条分隔线 |
| T02 | 3 | Editor/Visitor/No access | 各类已知待同步 | 用户补充混合只读 |
| T03 | 3 | 全 Editor | 无 | 全可编辑 |
| T04 | 3 | 全 Visitor | 无 | 所有 Space 仍可见、整体只读 |
| T05 | 3 | 全 No access | 无 | 三段受限提示、无设备网格 |
| Q01 | 4 | 全 Owner | 无 | 3 条分隔线、长卡片 |
| Q02 | 4 | Owner/Editor/Visitor/No access | Cloud/Device/Both 混合 | 用户未指定的四 Space 组合，建议重点覆盖 |
| Q03 | 4 | 全 Editor | 待同步 | 长卡片可编辑与按钮布局 |
| Q04 | 4 | 全 No access | 已知待同步 | 最长受限文案与滚动 |
| B01 | 2 | Owner/Editor | 仅 Zone 元数据 Cloud | 验证新增 Zone 级同步位置 |
| B02 | 2 | Owner/unknown | 同步未知 | 不误放行，不伪装 No access/No Data |
| B03 | 1 | Editor 角色但授权待验证 | 无 | 角色与编辑能力分离 |
| B04 | 1 | 名称/计数摘要不完整 | 未知 | 隐藏未知数量、稳定占位、不丢分区 |
| B05 | 1/4 | 长 Zone/Space/设备名称，同名 Space、跨 Space 同地址设备 | 混合 | 身份隔离、截断与换行 |

补充边界采用数据变体覆盖：每 Space 设备数 1、2、5、6、7、10、11；已知 Space 暂无设备但仍被引用时显示 0 devices/分区内空提示，不自动删除引用；100 个 Zone 的滚动与复用；中英文。设备数没有另设未经确认的业务上限，组件按输入渲染，容量约束留给业务层。

## 9. 实施顺序与验收

1. 确认本文的本期范围、只读规则、同步补充位置、Debug test 行为和视觉归一化。
2. 增加展示模型/纯策略和 fixture；优先测试完整成员权限、No access/unknown、同步归属、稳定身份与空 Zone 特例。
3. 实现 Site 专用非空表头、卡片和 Space 分区，复用现有主题、设备资源、尺寸；空项维持现有实现。
4. 接入真实/模拟模式、选择、面板与回调路由；验证切换期间异步结果不会替换模拟内容。
5. 补充中英文本地化与必要资源；资源是否能复用现有 locked/sync 图标需在视觉对照中确认，不能只根据文件名认定相同。
6. 检查新增源文件/资源在 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个 target 的 membership 和共享翻译；不修改 SDK/依赖。
7. 运行现有 `bash scripts/check_site_trigger_zones.sh` 与新增的状态/模式隔离测试；检查构建及实际布局。

构建按项目要求直接运行 xcodebuild，使用 SunSmart.xcworkspace、各品牌 scheme、Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO。不使用 Simulator，不通过 shell 包装或日志重定向。另检查 Release 配置不会显示 Debug test 入口。

实际 UI 验收必须在可用真机运行生产组件，通过预览模式检查 iPhone 窄/标准宽度、横竖屏、iPad 可变窗口；覆盖长文本、中英文、设备换行、四 Space、滚动复用、选中/只读/同步组合、底部面板展开收起。核对无裁切、遮挡、约束冲突及状态残留，保留截图/布局结果。设备暂不可用时明确标记布局验收未完成，不能用编译通过替代。

真实模式回归：已有空 Zone 的创建/删除/单行 Save、原 Zone 范围重试、未支持数据保护、页面云同步提示，以及切入/切出模拟后的数据与选择恢复。模拟操作不得写数据库、发业务网络请求或 Mesh 命令。

本轮未运行构建、测试或真机布局，也未验证服务端成员/权限摘要接口；上述为确认后的实施与验收计划。

## 10. 建议确认项

1. 本期先完成“新组件 + 模拟全状态 + 现有真实空 Zone 接入”；真实非空成员与跨 Space 操作后续接入。
2. View only 在选中、未选中时都显示；整个 Zone 只读时所有 Space 都带锁；选中只读项隐藏添加面板。
3. Space 图标按各自任务显示；无法归属 Space 的非空 Zone 云任务在 Zone 标题补充同步图标，空项继续保持现状。
4. 导航 Test 仅 Debug 开放；模拟模式保留操作外观、只做预览反馈；保留 +，但模拟模式禁用真实创建。
5. 四 Space 至少采用全 Owner、全 Editor、Owner/Editor/Visitor/No access 混合、全 No access 四组；接受本文列出的补充边界。
6. 设计重复名称/不一致计数按数据修正；角色复用现有英文大小写；主要尺寸统一并随容器自适应。

用户已确认以上建议，后续实施不再重复请求方案确认。
