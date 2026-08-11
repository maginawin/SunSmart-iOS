# Edit Site 弹窗退出时序实施总结

## 1. 结果

已按确认的方案 A 完成优化：Edit Site 的 Time Zone 在线确认和离线提示在用户确认后，会先完成 `SRAlertView` dismiss 并从视图层级移除弹窗，再执行 Site 属性保存与返回 Sites 的既有路由。

共享弹窗能力采用 opt-in 设计，默认行为保持不变。除两个已批准的 Edit Site action 外，其他 `SRAlertView` 调用点不会改变 handler 与 dismiss 的既有先后顺序。

## 2. 实际改动

### 2.1 SRAlertView

`SunSmart/Common/View/SRAlertView.swift`：

- `dismiss` 增加可选 completion；
- 有动画与无动画分支都先执行 `removeFromSuperview()`，再调用 completion；
- `SRAlertAction` 增加 `performsActionAfterDismiss`，默认值为 `false`；
- 新增统一的 action 路由：
  - opt-in 且 `closeAlert == true`：dismiss 完成后执行 handler；
  - 默认 action：保持 handler 后 dismiss；
  - `closeAlert == false`：保持只执行 handler；
- 左右两个按钮复用同一 action 路由；
- 关闭动画参数和输入框 `inputDoneBack` 位置保持不变。

### 2.2 Edit Site

`SunSmart/Main/Site/Controller/SiteEditViewController.swift`：

- 在线 `Update Time Zone` action 启用 `performsActionAfterDismiss`；
- 离线 `Got it` action 启用 `performsActionAfterDismiss`；
- Cancel、Close、普通 name/imageId 保存、Time Zone Selection 和 return-to-Sites 路由未改。

### 2.3 聚焦契约

新增 `Tests/Site/SiteEditAlertTransitionContractTests.swift`：

- `component` 模式验证 dismiss completion、remove-before-completion、默认兼容性和左右按钮统一路由；
- `edit-site` 模式验证在线/离线两个 opt-in，并约束 Edit Site 文件中恰好只有两个 opt-in。

该测试是源码契约，证明结构和调用顺序边界，不替代 UIKit 真机动画验收。

## 3. RED→GREEN 证据

### 3.1 RED

- `component`：旧实现按预期失败，错误为 `Dismiss must remove the alert before completing in animated and immediate paths`；
- `edit-site`：旧实现按预期失败，错误为 `Online timezone confirmation must dismiss fully before commit while Cancel remains non-committing`。

### 3.2 分阶段 GREEN

- 完成共享 `SRAlertView` 能力后，`component` 通过；此时 `edit-site` 仍保持 RED；
- 仅为两个 Edit Site action opt in 后，`component` 与 `edit-site` 均输出 `SiteEditAlertTransitionContractTests passed`。

实施期间发现测试取段标记绑定了旧的单行 dismiss 签名，而实现计划使用多行签名。根因确认后，将取段起点收窄为稳定的方法声明标记，行为断言未放宽。

## 4. Focused regression 结果

以下检查均通过：

| 检查 | 模式/范围 | 结果 |
|---|---|---|
| SiteEditAlertTransitionContractTests | component | Passed |
| SiteEditAlertTransitionContractTests | edit-site | Passed |
| SiteTimeZoneUIContractTests | 完整 UI 路由 | Passed |
| SiteTimeZoneUIContractTests | 本地化/资源/target | Passed |
| SiteUpdateToastUIContractTests | component | Passed |
| SiteUpdateToastUIContractTests | routing | Passed |
| SitePropsEditPolicyTests | policy | Passed |
| SitePropsAPIContractTests | API/coordinator | Passed |
| SiteTimeZonePersistenceContractTests | persistence/lifecycle | Passed |

基线阶段曾因旧计划中的 `SiteTimeZoneUIContractTests` 参数顺序与当前测试程序不一致产生一次误报。按当前测试入口要求修正为 `Edit → Selection → Cell → Status → Sites → Site` 后，基线与最终回归均通过；该误报不是源码缺陷。

## 5. 四品牌构建结果

均使用 Debug、generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO`，直接运行 `xcodebuild`：

| Scheme | 结果 |
|---|---|
| SunSmart | `** BUILD SUCCEEDED **` |
| Archipelago | `** BUILD SUCCEEDED **` |
| SLG Sync Plus | `** BUILD SUCCEEDED **` |
| SylSmart | `** BUILD SUCCEEDED **` |

构建日志包含既有的 App Intents metadata skipped warning，没有导致构建失败。

## 6. Diff 与范围

- `git diff --check`：通过，无空白错误；
- 业务代码仅修改 `SRAlertView.swift` 和 `SiteEditViewController.swift`；
- 新增一个独立 Site 契约测试；
- 新增本次设计、实施计划和实施总结文档；
- 未修改本地化、资源、project 配置、依赖或 SDK；
- 未执行 Git commit、push 或 merge。

## 7. 自动化证据边界

当前证据可以证明：

- 新 API 在四个品牌 target 中可编译；
- opt-in/legacy 分支的源码顺序满足设计；
- Site Time Zone、Toast、policy、API 和持久化契约未出现静态回归。

当前证据不能证明：

- 真机上弹窗关闭动画的主观流畅度；
- 不同 iOS 版本、设备尺寸和系统负载下的视觉连续性；
- 真实服务器请求和本地数据库故障注入场景。

## 8. 真机交互验收清单

以下项目状态均为待验收：

1. Sites 入口、在线、确认更新：弹窗移除后才关闭 Edit Site，随后显示 saving 状态卡。
2. Site 详情入口、在线、确认更新：alert dismiss → modal dismiss → detail pop 严格串行。
3. Sites 入口、离线、`Got it`：弹窗移除后退出，保留 pending，不显示 saving 状态卡。
4. Site 详情入口、离线、`Got it`：三段 UI 过渡严格串行。
5. Cancel：只关闭弹窗，不保存、不退出 Edit Site。
6. 快速重复点击：仅保存和退出一次。
7. 本地持久化失败：弹窗先关闭，停留 Edit Site 并显示失败 HUD。

