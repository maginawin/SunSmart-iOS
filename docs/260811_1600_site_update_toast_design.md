# Site 普通属性更新 Toast 设计

## 1. 背景

Edit Site 当前已经将属性提交分成两条 UI 路径：

- 待提交字段包含 `site.timezone` 时，返回 Sites 后展示 Time Zone 状态卡片；
- 待提交字段仅包含 `siteName`、`imageId` 时，返回 Sites 后使用 `XWHUDManager` 展示成功或失败提示。

本次需求是在仅更新 Site 名称或图标时，将返回 Sites 后的提示替换为 Figma 所示的两种 Toast 外观。成功文案保持 `Site updated.`，失败文案按确认结果保持 `Failed to update site.`，不采用 Figma 示例中的 `Sync failed. Please retry.`。

## 2. 目标

1. 为 `ToastStatusView` 增加 Site Update 专用外观，包含成功态和失败态。
2. 在线更新成功、在线更新失败、离线保存为 pending 三种返回 Sites 的结果使用新 Toast。
3. Toast 必须在 Edit Site modal 已关闭、必要的 Site 详情页返回动画已完成、Sites 页面已经可见后展示。
4. 保持现有通用 Toast 的视觉和调用行为不变，避免影响 Group、Device 等既有页面。
5. 保持 timezone 专用确认、离线提示和状态卡片流程不变。
6. English 和简体中文继续使用现有 Site 专属本地化文案。

## 3. 非目标

- 不重做全局 HUD 或其他业务页面的 Toast。
- 不修改 Site 属性 API、timestamp、pending、retrieve/merge 或响应校验规则。
- 不修改 Time Zone 状态卡片、Gateway/Mesh 同步流程。
- 不改变 Toast 的默认展示位置、动画时长和自动消失时长。
- 不新增第三方依赖。

## 4. 已确认决策

### 4.1 文案

| 状态 | English | 简体中文 | 本地化 Key |
|---|---|---|---|
| 成功 | Site updated. | 场所已更新。 | `site_updated_toast` |
| 失败 | Failed to update site. | 场所更新失败。 | `site_update_failed_toast` |

失败 Toast 只采用 Figma 的失败视觉，不采用其示例文案 `Sync failed. Please retry.`。

### 4.2 字段分支

是否进入 Toast 流程继续以最终待发送字段集合为准。该集合是历史 pending 字段与本次实际变化字段的并集：

- 集合仅包含 `siteName`、`imageId` 时进入普通 Toast 流程；
- 集合只要包含 `timezone`，包括历史 pending timezone，仍进入 Time Zone 专用流程。

因此，本次需求不会把“当前只改 name/icon、但历史 pending 仍包含 timezone”的提交降级成普通 Toast。

## 5. Figma 依据

Figma 文件：`One-SunSmart`

- 成功节点：`425:12304`，名称 `Toast/SyncSucceeded`
- 失败节点：`425:12317`，名称 `toast/failed`

两个节点共用以下视觉参数：

| 项目 | Figma 值 |
|---|---:|
| 组件尺寸 | 343 × 44 pt |
| 圆角 | 13 pt |
| 背景 | Black 60% |
| Backdrop blur | 5.5 pt |
| 阴影 | Y 2、Blur 5、Black 15% |
| 内容水平内边距 | 22 pt |
| 内容垂直内边距 | 12 pt |
| 图文间距 | 10 pt |
| 图标容器 | 30 × 30 pt |
| 实际图标 | 16 × 16 pt |
| 文案字号 | 15 pt |
| 字重 | Light |
| 行高 | 22 pt |
| 文案颜色 | White |

Figma 使用的成功和失败图标均为线框状态图标，与工程当前 `toast_success`、`toast_failed` 的实心圆图标不同，不能直接复用现有图片。

## 6. 当前源码依据

### 6.1 Toast 组件

`SunSmart/Common/View/ToastStatusView.swift` 当前具备：

- `.success`、`.failure` 两个语义状态；
- top、center、bottom 三种位置；
- 淡入、位移动画和自动销毁；
- 默认底部安全区上方 24 pt、展示 1.5 秒。

但当前布局为左右各 20 pt、最小高度 44 pt、14 pt 图标、13 pt Medium 文案，并使用现有实心图标，与 Figma 不一致。

该组件同时由 Group 和 Device 页面使用，并已加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target，不能直接全局替换默认视觉。

### 6.2 Site 普通更新

`SunSmart/Main/Site/Controller/SiteEditViewController.swift` 当前行为：

1. `plan.includesTimezone == false` 时进入普通更新分支；
2. 本地保存成功后先通过 `returnToSites` 返回 Sites；
3. 在线时调用 `coordinator.submit`；
4. submit 成功使用 `XWHUDManager.showSuccessTipHUD`；
5. submit 失败或离线使用 `XWHUDManager.showErrorTipHUD`；
6. 本地保存失败时停留 Edit Site 页面并展示原错误 HUD。

`coordinator.submit` 的成功表示请求成功且 timestamp、已发送字段均与响应完全匹配，不把 HTTP 成功直接等同为 Site 更新成功。

### 6.3 返回路径

- 从 `SitesViewController` 进入编辑：关闭 Edit Site modal 后仍停留当前 Sites 页面。
- 从 `SiteViewController` 进入编辑：先关闭 Edit Site modal，再从 Site 详情页返回 Sites。

当前第二条路径在调用 `popViewController` 后立即执行 completion，不能保证 Toast 展示时 Sites 返回动画已经完成。

## 7. 架构设计

采用“复用 ToastStatusView、增加独立 Appearance”的方案。

### 7.1 状态与外观分离

`ToastStatusView` 保留成功/失败语义状态，并增加外观维度：

- Standard：保持现有默认视觉、图标、约束和所有既有调用不变；
- Site Update：使用本设计定义的尺寸、字体、背景、阴影及 Figma 图标。

现有 `show` API 的外观参数默认使用 Standard，确保不修改 Group、Device 等调用点也不会发生视觉变化。

### 7.2 视图层次

Site Update 外观采用两层容器：

1. 外层 `ToastStatusView` 负责阴影，不裁剪；
2. 内层内容容器负责 13 pt 圆角裁剪，包含 blur、Black 60% overlay 和水平内容布局。

这样可以同时保留圆角内部裁剪与外部阴影，避免当前 `masksToBounds` 导致阴影不可见。

UIKit 无法直接指定 Figma 的 5.5 pt backdrop blur 半径，因此使用工程现有原生 blur 体系中最接近的系统材质，再叠加 Black 60% overlay；最终以截图和真机视觉对照验收，不自行绘制非系统模糊算法。

### 7.3 响应式尺寸

- 在 375 pt 宽设备上保持 343 pt，即左右各 16 pt；
- 在窄屏上保持左右至少 16 pt，不超出安全显示区域；
- 在 iPad 或其他宽屏上最大宽度保持 343 pt 并水平居中；
- 高度固定 44 pt；
- 当前中英文文案均保持单行居中，不扩大组件高度。

### 7.4 图标资源

从 Figma 下载并提交原始成功、失败图标资源，放入共享 Assets：

- `site_update_toast_success`
- `site_update_toast_failure`

资源采用工程现有 asset catalog 可稳定编译的格式和倍率，不手工重画、不替换现有 `toast_success`、`toast_failed`，从而隔离其他业务页面。

共享 `SunSmart/Assets.xcassets` 已被四个品牌 target 引用，新增 imageset 不需要单独修改 target membership，但实施后仍需验证四个 target 的资源编译。

## 8. 返回 Sites 与展示时序

### 8.1 回调契约

将 `returnToSitesHandler` 改为初始化时必传的路由依赖，其 completion 由路由方提供最终 Toast host view。`SiteEditViewController` 不查找全局 window，也不把 Toast 添加到已经 dismiss 的编辑页。当前只有 Sites 和 Site 详情两个入口，二者都必须在创建编辑器时提供该 handler。

两个入口分别保证：

- Sites 入口：modal dismiss completion 中传入 `SitesViewController.view`；
- Site 详情入口：modal dismiss 后执行 pop，等待导航 transition 完成，再传入返回后的 `SitesViewController.view`。

Site 详情入口在 pop 前从导航栈定位 `SitesViewController`。当系统没有 transition coordinator 时，pop 后立即把该控制器的 view 传给 completion；若异常导航栈中不存在 Sites 控制器，则使用仍可见的 navigation controller view 作为 host，并触发仅 Debug 可见的 `assertionFailure`，不把 Toast 添加到离屏页面。

### 8.2 请求与 Toast 顺序

保持当前“先返回 Sites，再提交”的顺序：

1. 本地原子保存 Site 和 pending；
2. 完成返回 Sites；
3. 在线时提交 update；
4. 根据经过完整响应校验的结果展示成功或失败 Toast；
5. 离线时直接展示失败 Toast 并保留 pending。

Toast 只表达本次 Site props 云端 update 结果，不代表 Gateway、Mesh 或整包云同步成功。

## 9. 行为矩阵

| 场景 | 本地状态 | 页面路由 | 最终提示 |
|---|---|---|---|
| 仅 name/imageId，在线，update 响应完整匹配 | 保存并清除对应 pending | 返回 Sites | Success / `Site updated.` |
| 仅 name/imageId，在线，请求失败 | 保存并保留 pending | 返回 Sites | Failure / `Failed to update site.` |
| 仅 name/imageId，在线，响应 timestamp 或字段不匹配 | 保存并保留 pending | 返回 Sites | Failure / `Failed to update site.` |
| 仅 name/imageId，离线 | 保存并保留 pending | 返回 Sites | Failure / `Failed to update site.` |
| 本地数据库保存失败 | 回滚本地修改 | 停留 Edit Site | 保持现有错误 HUD |
| 无变化且无 pending | 不修改 | 关闭编辑页 | 无 Toast |
| 最终字段集合包含 timezone | 按原 timezone 规则 | 返回 Sites | 原 Time Zone 状态卡 |

## 10. 本地化

继续复用现有 `site_updated_toast`、`site_update_failed_toast`，不新增重复 Key，不硬编码用户可见文案。

需要同步确认 English 与简体中文资源仍包含一致 Key，并检查四个品牌 target 均引用共享 `Localizable.strings`。

## 11. 测试设计

### 11.1 Focused contract

新增独立 `Tests/Site/SiteUpdateToastUIContractTests.swift`，避免继续扩大 timezone UI contract 的职责。覆盖：

- Standard 外观仍为默认值；
- Site Update 外观包含 343 pt 最大宽度、16 pt 最小边距、44 pt 高度、13 pt 圆角、30/16 pt 图标、10 pt 间距和 15 pt Light 文案；
- 成功/失败态使用两个 Site 专属 Figma 资源；
- 普通更新返回后调用 `ToastStatusView`，不再调用全局成功/失败 HUD；
- 本地保存失败仍停留编辑页并使用原错误 HUD；
- timeout、字段不匹配、离线均选择失败状态；
- timezone 分支仍使用 `SiteTimeZoneSyncStatusView`；
- 两个入口都把最终 Sites host 交给 completion；
- Site 详情入口等待 pop transition 完成后再执行 completion；
- English 和简体中文保留确认后的精确文案；
- 两个 imageset 的 Contents 和共享 target 资源引用有效。

现有 `SitePropsEditPolicyTests`、`SitePropsAPIContractTests`、`SiteTimeZoneUIContractTests` 继续执行，防止字段分支和 API 真值回归。

### 11.2 构建验证

依次使用 generic iPhoneOS、关闭签名构建：

1. SunSmart
2. Archipelago
3. SLG Sync Plus
4. SylSmart

直接运行 `xcodebuild`，不使用 shell 包装、日志重定向或 Simulator。

### 11.3 人工验收

至少覆盖：

- 从 Sites 直接编辑 name，仅更新成功；
- 从 Site 详情编辑 icon，仅更新成功并完成返回动画后显示；
- 在线请求失败；
- code 成功但响应 timestamp/字段不匹配；
- 离线编辑；
- 本地保存失败模拟；
- 历史 pending timezone 加本次 name/icon 修改；
- 无变化关闭；
- English、简体中文；
- 小屏 iPhone、常规 iPhone 和 iPad；
- 成功/失败图标、背景模糊、阴影、圆角、单行文案及安全区位置与 Figma 对照。

构建和静态 contract 只能证明源码、资源和 target 集成，不等于真实网络响应、导航动画和真机视觉验收。

## 12. 影响文件

预计修改：

- `SunSmart/Common/View/ToastStatusView.swift`
- `SunSmart/Main/Site/Controller/SiteEditViewController.swift`
- `SunSmart/Main/Site/Controller/SitesViewController.swift`
- `SunSmart/Main/Site/Controller/SiteViewController.swift`
- `SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/`
- `SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/`
- `Tests/Site/SiteUpdateToastUIContractTests.swift`

核对但原则上不修改：

- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `SunSmart.xcodeproj/project.pbxproj`

若实施时发现资源格式必须新增显式工程引用，先核对四个 target 的 Resources phase，再做最小 project 配置修改；不得只修主 target。

## 13. 完成标准

1. 普通 name/imageId 更新在 Sites 页面使用 Figma 成功/失败 Toast。
2. 失败文案保持 `Failed to update site.`，中英文均从本地化读取。
3. timezone 分支、无变化、本地保存失败行为保持设计矩阵不变。
4. 其他页面使用的 Standard Toast 外观无回归。
5. Focused contracts、既有 Site contracts、`git diff --check` 全部通过。
6. 四品牌 generic iPhoneOS build 全部通过。
7. 真机视觉和真实网络验收结果与静态/构建验证分开报告。
