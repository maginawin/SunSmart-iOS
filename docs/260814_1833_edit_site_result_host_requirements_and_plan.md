# Edit Site 结果宿主页需求分析与开发方案（已确认）

## 1. 结论

需求方向合理，但当前描述还不完全。核心规则应从“更新后统一返回 Sites”改为“更新后关闭 Edit Site，并在发起编辑的宿主页面展示结果”：

- 从 Site 详情页进入 Edit Site：关闭 Edit Site 后保留 Site 详情页，在 Site 详情页展示结果；
- 从 Sites 列表进入 Edit Site：关闭 Edit Site 后保留 Sites 列表，在 Sites 列表展示结果。

为避免实现时对“失败”和“结果弹窗”产生不同理解，建议同时确认以下边界：

1. 本地持久化失败继续停留在 Edit Site，保留输入内容并允许重试，不关闭编辑页；
2. 普通名称/图标更新的在线成功、在线失败和离线 pending 结果，均在来源宿主页展示现有 Site Update Toast；
3. 包含 Time Zone 的在线更新，继续使用现有 Time Zone 状态卡；关闭 Edit Site 后保留来源页，并由 active window 全屏承载状态卡（包括 navigation bar）；
4. Time Zone 离线保存沿用现有行为：保存本地 pending 后回到来源宿主页，不新增成功或失败结果弹窗；
5. 无变化、Cancel、Close 均只关闭 Edit Site 并回到来源宿主页，不展示更新结果。

以上五项是推荐默认口径。若产品希望“本地持久化失败也退出 Edit Site”或“Time Zone 离线也展示结果”，需要单独改写现有交互和重试语义，不建议隐含在本次需求中。

## 2. 当前源码事实

### 2.1 两个入口复用同一个编辑器

`SitesViewController` 和 `SiteViewController` 都创建 `SiteEditViewController`，并各自传入返回路由闭包。编辑器本身不判断来源页面。

### 2.2 当前退出 Site 详情是显式设计

- Sites 列表入口：关闭 Edit Site modal 后，把 `SitesViewController.view` 交给结果展示逻辑；
- Site 详情入口：关闭 Edit Site modal，更新标题，再显式 pop `SiteViewController`，等待导航动画结束后把 Sites 页面交给结果展示逻辑。

因此当前问题是入口路由契约不符合新需求，不是 Toast 层级或展示时机的偶发错误。

### 2.3 更新结果分为三类

1. 本地持久化失败：不执行返回路由，停留 Edit Site，并显示现有失败 HUD；
2. 普通属性提交结果：关闭编辑页后，在路由闭包提供的 host view 上展示成功或失败 Toast；
3. Time Zone 提交结果：关闭编辑页后展示现有 Time Zone saving/success/failure 状态卡。

当前普通提交与 Time Zone 提交都会复用同一个返回路由，所以 Site 详情入口会在两条路径上都被 pop 到 Sites。

## 3. 需求合理性与完整性评估

### 3.1 合理性

合理。编辑操作结束后回到发起操作的页面，符合上下文保持原则，也避免用户在 Site 详情页只修改名称或图标后丢失当前浏览位置。

该规则对两个入口是对称的：来源页负责关闭编辑器并提供自身作为结果展示宿主，不需要编辑器了解导航栈结构。

### 3.2 当前缺失项

原描述至少缺少四个明确边界：

- “失败”是否包括本地数据库保存失败；
- “更新 Site”是否同时包括普通名称/图标和 Time Zone；
- 离线保存 pending 是否继续按现有失败 Toast/无状态卡规则；
- 无变化、Cancel、Close 是否不展示结果。

若不补齐，开发可能只移除 Site 页的 pop，却遗漏 Time Zone contract、离线分支或本地失败重试行为。

## 4. 方案比较

### 4.1 方案 A：来源页提供结果宿主，推荐

把现有“返回 Sites”闭包重命名并收敛为“结束编辑并返回结果宿主”的契约：

- Sites 入口关闭 modal 后刷新列表，并返回 Sites 自身 view；
- Site 入口关闭 modal 后刷新 Site 标题/必要视图，并返回 Site 自身 view；
- Site 入口不再查找 `SitesViewController`，不再 pop，也不再等待 pop transition；
- 编辑器继续在宿主准备完成后发起提交或展示结果。

优点：改动最小、职责清晰；普通 Toast 使用来源页 view，Time Zone 状态卡在保留来源页后使用 active window 全屏展示，不引入全局通知或导航栈猜测。

代价：需要同步重命名编辑器接口和更新两个现有源码契约测试。

### 4.2 方案 B：向编辑器传入来源枚举

向 `SiteEditViewController` 传入 Sites/Site 来源枚举，由编辑器自己决定 dismiss、pop 和结果宿主。

优点：入口参数直观。

缺点：编辑器会耦合外部导航结构和两个宿主控制器，未来增加入口时还要继续扩展分支；不如方案 A 符合现有依赖注入结构。

### 4.3 方案 C：所有结果通过全局通知或 active window 展示

编辑器只发通知，来源页监听并展示；或直接把结果视图添加到当前 window。

优点：可绕开回调改名。

缺点：页面归属隐式、生命周期和重复监听更难验证；普通 Toast 没有必要扩大到 window。不建议把它作为所有结果的统一方案，但 Time Zone 全屏状态卡应继续使用 active window。

## 5. 推荐设计

### 5.1 路由契约

路由闭包只保证两件事：

1. Edit Site modal 已完全关闭；
2. completion 获得当前来源页的可见 view。

编辑器不直接查找 `SitesViewController` 或 `SiteViewController`，也不自行 pop 外部页面。

### 5.2 Sites 列表入口

保持当前可见行为：

1. dismiss Edit Site modal；
2. 刷新被编辑 Site 的列表数据；
3. 把 `SitesViewController.view` 作为结果宿主；
4. 普通更新在 Sites view 显示 Toast；Time Zone 更新由 active window 全屏显示状态卡。

### 5.3 Site 详情入口

调整为：

1. dismiss Edit Site modal；
2. 根据已落库的 Site 数据刷新当前页面标题；
3. 不执行 `popViewController`；
4. 把 `SiteViewController.view` 作为普通结果宿主；
5. 普通更新在 Site view 显示 Toast；Time Zone 更新由 active window 全屏显示状态卡。

Time Zone 状态卡与普通 Toast 的层级需求不同：普通 Toast 归属于来源页 view；Time Zone 状态卡需要遮罩整个界面，因此在 Edit Site 完全关闭后调用参数为空的 `show()`，由 active window 承载并覆盖 navigation bar。其底层页面仍由来源路由决定。

### 5.4 提交顺序

保留现有顺序与真值边界：

1. 先执行本地原子持久化；
2. 本地成功后关闭 Edit Site 并回到来源宿主页；
3. 在线时提交服务器；
4. 仅当响应及字段校验通过才显示成功，否则显示失败并保留 pending；
5. 本地持久化失败不关闭编辑页、不发服务器请求。

本需求只改变结果页面归属，不改变成功/失败判定、pending、timestamp、API 或 Time Zone/Gateway 同步逻辑。

## 6. 行为矩阵

| 来源 | 场景 | 关闭 Edit Site 后页面 | 结果展示 |
|---|---|---|---|
| Sites | 普通属性在线成功 | Sites | Sites 上成功 Toast |
| Sites | 普通属性在线失败或响应不匹配 | Sites | Sites 上失败 Toast |
| Sites | 普通属性离线 | Sites | Sites 上现有失败 Toast，保留 pending |
| Site | 普通属性在线成功 | Site | Site 上成功 Toast |
| Site | 普通属性在线失败或响应不匹配 | Site | Site 上失败 Toast |
| Site | 普通属性离线 | Site | Site 上现有失败 Toast，保留 pending |
| Sites | Time Zone 在线 | Sites | active window 上全屏状态卡，底层为 Sites |
| Site | Time Zone 在线 | Site | active window 上全屏状态卡，底层为 Site |
| Sites/Site | Time Zone 离线 | 对应来源页 | 沿用现有无结果卡行为，保留 pending |
| Sites/Site | 本地持久化失败 | Edit Site | 现有失败 HUD，可重试 |
| Sites/Site | 无变化、Cancel、Close | 对应来源页 | 无结果提示 |

## 7. 预计改动范围

### 7.1 生产代码

- `SunSmart/Main/Site/Controller/SiteEditViewController.swift`
  - 将 `returnToSites` 语义重命名为来源宿主/结果宿主语义；
  - 保持普通更新和 Time Zone 更新共用同一个编辑结束回调；
  - 普通 Toast 使用回调返回的来源页 view；Time Zone 状态卡使用 active window 全屏展示；
  - 不改提交和结果判定。
- `SunSmart/Main/Site/Controller/SitesViewController.swift`
  - 适配新命名；
  - 保持 modal dismiss、列表刷新和 Sites view 回传。
- `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - 移除编辑成功后的 Sites 查找、详情页 pop 和 transition 等待；
  - dismiss 完成后刷新当前 Site UI，并回传当前 Site view。

### 7.2 测试

- `Tests/Site/SiteUpdateToastUIContractTests.swift`
  - 将断言从“两个入口最终都提供 Sites host”改为“两个入口分别提供自身 host”；
  - 明确 Site 入口不得 pop，Sites 入口行为保持不变。
- `Tests/Site/SiteTimeZoneUIContractTests.swift`
  - 将 Site 入口必须 pop 的旧契约改为必须保留 Site；
  - 验证两个入口共用编辑器、Coordinator，且 Time Zone 状态卡使用 active window 全屏展示。

本次不新增测试文件，路由职责继续由上述两个既有聚焦契约覆盖。

不计划修改 Toast 外观、Time Zone 状态卡 UI、本地化、资源、target 配置、依赖或 `NordicSigMeshSDK`。

## 8. 开发步骤

1. 先更新路由契约测试，使当前 Site 入口的 pop 行为明确失败；
2. 重命名编辑器的返回接口，使名称不再承诺统一返回 Sites；
3. 保持 Sites 入口行为不变，仅适配接口；
4. 修改 Site 入口：modal dismiss 后刷新当前页并回传当前 view，不 pop；
5. 运行 Site Update Toast、Time Zone UI、Site props policy/API/persistence 等聚焦测试；
6. 执行 `git diff --check`；
7. 直接使用 generic iPhoneOS、关闭签名依次构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart；
8. 真机验证两个入口、普通/Time Zone、成功/失败/离线、本地失败、无变化与 iPad modal。

## 9. 验收标准

1. 从 Site 详情进入 Edit Site，任何本地持久化成功的提交都只关闭 Edit Site，不退出 Site；
2. 普通更新成功/失败 Toast 展示在对应来源页；
3. Time Zone 在线状态卡由 active window 全屏展示并覆盖 navigation bar，底层保留对应来源页；
4. 从 Sites 列表进入的既有结果展示位置不变；
5. 本地持久化失败仍停留 Edit Site，输入可继续修改并重试；
6. 无变化、Cancel、Close 不产生结果提示；
7. 成功/失败真值、pending、timestamp、API、文案和视觉不变；
8. 聚焦测试、diff check 和四个品牌 generic iPhoneOS build 通过；
9. 自动化与构建结果不代替真实服务器、导航动画和真机视觉验收。

## 10. 已确认决策

2026-08-14 已确认采用方案 A，并按第 1 节列出的五项默认口径实施；执行方式采用 Inline Execution。
