# Site 页 Space item 的 Debug Export Json 方案

日期：2026-09-16  
状态：已确认并实施；导出回归、Debug / Release 编译通过，真机交互待人工验收。  
调查基线：`fix`，HEAD `999be5fa`；调查开始时工作树无未提交改动。

## 结论

已在 Site 页 Space item 的更多菜单中，于 Share 之后、Unbind 之前增加 Export Json。直接复用 Space 页面现有的 `DebugCloudJSONExporter`，业务改动仅涉及 `SiteViewController.swift` 中的 `spaceMenu(space:point:)`。

Debug 指现有 `#if DEBUG` 编译条件，不另设运行时开关，也不使用 `space.canDebug`。权限沿用现有导出功能：按被点击 Space 的 `permission` 判断，仅 owner/editor 可见。

## 实施前核实的入口与复用点

| 位置 | 现状及用途 |
| --- | --- |
| `SpacesViewCell.moreBtnClick()` | 把对应卡片及菜单锚点交给 delegate。无需修改 cell。 |
| `SiteViewController.cell(_:moreAction:)` | 取 `cell.space`，检查 Space 状态，调用 `spaceMenu(space:point:)`；All Spaces 与 Favourites 共用该入口。 |
| `SiteViewController.spaceMenu(space:point:)` | 现有顺序为 Edit、Delete、Share、Unbind，各项按权限显示；其中旧 Export 注释不是当前调试导出入口。 |
| `SpaceViewController.moreClick()` | 已有可直接参照的 Export Json 菜单项，包含权限判断及菜单关闭后执行设置。 |
| `SiteViewController.debugJSONExporter` | Site 顶部菜单已使用的 DEBUG 实例，可复用于卡片入口，无需新增实例。 |
| `DebugCloudJSONExporter.share(site:space:from:)` | 显式传入 Space 时导出单个 Space，已有重复操作保护、快照检查、错误提示、文件生成、系统分享及临时文件清理。 |
| `DebugCloudJSONExporter.menuWidth(items:minimum:)` | 按实际文案测量宽度，避免英文标题截断。卡片菜单现有默认宽度为 `SCRXFrom(108)`。 |

## 实施步骤

1. 在 `spaceMenu(space:point:)` 的 Share 条件块之后插入独立的 `#if DEBUG` 菜单项。使用 `DebugCloudJSONExporter.canExport(space.permission)`，不嵌套在 Share 的权限条件中：Share 未显示时，导出项仍按自己的既有权限规则显示。
2. 复用 `menu_share` 图标与 `debug_export_json` 本地化 Key。英文为 `Export Json`，简体中文为 `导出 JSON`，无需新增资源或翻译。
3. 设置 `performsActionAfterDismiss: true`。回调弱引用控制器，调用已有实例的 `share(site: self.site, space: space, from: self)`；明确传入本次卡片的 Space，避免误导出整个 Site 或上一次进入的 Space。
4. DEBUG 分支使用现有宽度计算方法，最小宽度取 `MenuPopView.defalutMenuWidth`，沿用传入的菜单锚点。Release 保留原来的菜单显示调用，避免引用仅 DEBUG 存在的类型。
5. 同位置的旧 Export 注释块可一并移除，避免与新入口混淆；不启用旧 `exportSpace` 路径，不扩展其他导出逻辑。

不需要修改 SDK、工程文件、依赖、本地化、Space 页面或导出器。共享控制器会影响引用它的品牌，但不引入新的品牌条件或资源归属差异。

## 行为约定

- 点击后留在 Site 页面，生成所选 Space 的本地诊断 JSON，再打开系统分享面板，无需先进入 Space 页面。
- 内容和文件命名完全沿用现有 Space 导出：接口对比字段及 `_debugInspection`，包含该 Space 的状态、诊断与已覆盖配置表原始记录；不是服务器备份，也不是可以直接提交的上传请求。
- 不主动同步、下载远程数据或切换 Mesh Space；不把断网、蓝牙未连接、待上传或同步保护状态作为新增入口限制。缺失本地数据时遵循已有诊断或报错行为，不承诺补齐远端内容。
- 不改变现有访问与一致性校验。角色、账号、区域或快照变化导致导出不可用时，沿用现有提示；取消分享沿用既有清理。
- iPad 沿用导出器已有的导航栏按钮或页面锚点，不为卡片新增分享面板定位 API；卡片弹出菜单仍使用原卡片锚点。

## 实施后的最小验证

| 范围 | 验收重点 |
| --- | --- |
| 菜单与权限 | Debug owner/editor 显示，visitor 不显示；顺序紧跟 Share，位于 Unbind 前；仅依据 Space 权限，不误用 Site 权限。 |
| 选中对象 | All Spaces 与 Favourites 分别选两个不同 Space，校验文件名、`spaceId` 与诊断记录属于被点击项；包含一个本次尚未进入的 Space。 |
| 展示与分享 | 英文、中文标题完整；菜单先关闭再显示分享；取消后可重新导出；iPad 分享面板能正常弹出。 |
| 诊断兼容 | 断网但有本地数据、同步保护中的 Space 仍按既有规则导出，原同步错误不被清除；权限或数据变化时沿用既有失败处理。 |
| Release 边界 | Release 中不显示卡片导出项，不引用 DEBUG 专用类型。 |

自动化优先运行 `scripts/check_debug_json_export.py`，复核已有 SQL/Blob、快照和文件行为；该脚本不覆盖本次真实卡片入口。已有 `DebugCloudJSONUITests` 为独立导出测试入口，也不能替代 Site 卡片交互验收，不为本次小改动新建 UI 测试工程。

实现完成后核对本地 workspace、scheme 与 SDK realpath，使用稳定 DerivedData 目录完成 SunSmart Debug generic iOS 构建。本次新增条件编译分支，补一次 SunSmart Release 构建验证隔离；无品牌分歧时不机械重复五品牌构建。使用本地映射时应指向约定的 `one-dev` SDK，本方案不需要新 SDK API 或发布 SDK revision。

真实菜单、文件选中对象及分享体验由用户人工验收；不自动安装真机。

## 实施与验证记录

- 实施了以上五步：DEBUG 权限控制、卡片 Space 传参、关闭菜单后导出、动态菜单宽度，以及移除旧注释入口。未改动 SDK、导出器、资源或工程配置。
- `scripts/check_debug_json_export.py` 通过：原始 SQL/Blob、隔离范围、受保护或异常 Space、角色/账号/区域/快照变化、JSON 文件读写和清理。该结果不代表卡片 UI 已验收。
- `git diff --check` 通过。
- `SunSmartLocal.xcworkspace` / SunSmart / Debug、Release / generic iOS / `CODE_SIGNING_ALLOWED=NO` 构建均通过。编译有既存弃用 API 等警告；未执行运行验收。
- 原 `SunSmart-fix-gateway` 构建目录出现数据库锁，确认持锁进程退出后重试仍失败；未清理缓存或终止其他任务。改用固定 CLI 目录 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-cli` 后 Debug 编译成功。
- SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `a6246b1`。构建使用该工作树当时已有的 Mesh 时间相关未提交差异（MeshLibManager、ExplicitTimeSetInput、Node+Messages、TimeSet、TimeMessage、MeshTimeConversion 及相关测试/脚本）；本任务未修改 SDK，也未引入新 SDK API。
- 未自动安装或运行真机。最短人工步骤：Debug owner/editor 账号在 Site 的 All Spaces 与 Favourites 各选一个不同 Space，打开卡片菜单确认 Share 下方有导出项，保存 JSON 后核对 `spaceId`；再取消一次分享并重试，确认菜单与分享面板正常衔接。
