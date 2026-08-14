# Edit Site 结果宿主页实施总结

## 1. 实施结果

已按确认的方案 A 完成来源页结果宿主调整：

- 从 Sites 列表进入 Edit Site：关闭编辑页后仍停留 Sites，普通结果 Toast 在 Sites 展示，Time Zone 状态卡由 active window 全屏展示；
- 从 Site 详情进入 Edit Site：关闭编辑页后保留 Site，不再 pop 到 Sites，普通结果 Toast 在 Site 展示，Time Zone 状态卡由 active window 全屏展示。

本次只改变编辑结束后的页面归属与结果宿主，不改变提交真值、pending、timestamp、API、文案或视觉。

## 2. 生产代码改动

### 2.1 SiteEditViewController

- 将带有“统一返回 Sites”含义的接口重命名为结束编辑与结果宿主语义；
- 普通更新继续在宿主 view 上展示现有 Site Update Toast；
- Time Zone 状态卡在编辑页关闭后使用 active window，遮罩覆盖包括 navigation bar 在内的整个界面；
- 本地持久化失败、离线规则、服务器提交和成功判定保持不变。

### 2.2 SitesViewController

- 适配新的结束编辑接口名称；
- 保持原有 modal dismiss、列表刷新和回传 `SitesViewController.view` 的时序。

### 2.3 SiteViewController

- 移除 Edit Site 完成后的 `SitesViewController` 查找、详情页 pop 和 pop transition 等待；
- modal dismiss 完成后刷新当前 Site 标题，并回传 `SiteViewController.view`；
- 保留既有 `siteDidChange` 和 iPad modal 配置。

## 3. TDD 证据

### 3.1 RED

先修改两个既有源码契约：

- `SiteUpdateToastUIContractTests` 因缺少来源结果宿主接口而失败；
- `SiteTimeZoneUIContractTests` 因仍使用旧初始化/路由语义而失败。

两次失败均来自目标行为未实现，不是测试路径、参数或编译错误。

### 3.2 GREEN

完成最小生产修改后：

- `SiteUpdateToastUIContractTests` routing 通过；
- `SiteTimeZoneUIContractTests` 完整路由模式通过，并锁定 active window 全屏承载规则。

## 4. 聚焦回归

以下 9 个检查点均通过：

| 契约 | 模式/结果 |
|---|---|
| SiteEditAlertTransitionContractTests | component passed |
| SiteEditAlertTransitionContractTests | edit-site passed |
| SiteTimeZoneUIContractTests | routing passed |
| SiteTimeZoneUIContractTests | localization/target passed |
| SiteUpdateToastUIContractTests | component passed |
| SiteUpdateToastUIContractTests | routing passed |
| SitePropsEditPolicyTests | passed |
| SitePropsAPIContractTests | passed |
| SiteTimeZonePersistenceContractTests | passed |

`git diff --check` 无输出。

## 5. 四品牌构建

构建配置统一为 Debug、generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO`。

| Scheme | 结果 |
|---|---|
| SunSmart | BUILD SUCCEEDED，退出码 0 |
| Archipelago | BUILD SUCCEEDED，退出码 0 |
| SLG Sync Plus | BUILD SUCCEEDED，退出码 0 |
| SylSmart | BUILD SUCCEEDED，退出码 0 |

构建过程中使用工程当前的本地 `NordicSigMeshSDK` Package 引用；SDK 仓库没有修改。

## 6. 明确保留的行为

- 本地持久化失败：停留 Edit Site，显示现有失败 HUD，可继续重试；
- 普通更新在线失败、响应不匹配或离线：保留 pending，并在来源页显示现有失败 Toast；
- Time Zone 在线：继续展示 saving/success/failure 状态卡，并由 active window 全屏承载；
- Time Zone 离线：保存本地 pending 后回到来源页，不新增结果卡；
- 无变化、Cancel、Close：只关闭 Edit Site，不展示结果；
- 在线确认弹窗和离线提示弹窗仍先完整 dismiss，再执行保存。

## 7. 未修改范围

- Toast 外观、动画、时长和本地化文案；
- Time Zone 状态卡视觉和状态机；
- Site props policy、API、响应校验、pending、timestamp 和数据库结构；
- 资源、`project.pbxproj`、依赖和 `NordicSigMeshSDK`；
- Site 以外的页面或业务模块。

## 8. 仍需真机与真实环境验收

自动化契约和 generic build 不能证明以下运行时结果：

1. Sites 与 Site 两个入口的 modal 动画和结果显示位置；
2. 普通更新在线成功、服务器失败、响应不匹配和离线；
3. Time Zone 在线 success/failure 与离线 pending；
4. 本地持久化失败、无变化、Cancel 和 Close；
5. iPhone 与 iPad 的页面层级和结果视图布局；
6. 真实服务器请求、网络切换和用户可感知时序。

本次未进行真机、真实服务器或实际网络验收。
