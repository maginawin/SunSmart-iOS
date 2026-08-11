# Site 普通属性更新 Toast 实现总结

## 结论

已按确认的方案 A 完成 Site 普通属性更新 Toast：最终待发送字段不包含 `timezone`、仅更新 name 或 imageId 时，关闭 Edit Site 并返回 Sites 页面后展示 Site Update 专用成功或失败 Toast。失败文案保持 `Failed to update site.`；历史 pending 字段包含 `timezone` 时仍沿用 Time Zone 状态卡。

## 实现范围

- 为共享 `ToastStatusView` 增加可选的 Site Update 外观；默认 Standard 外观及 Group、Device 现有调用保持不变。
- 根据 Figma 节点 `425:12304`、`425:12317` 增加成功和失败 SVG，共享给四个品牌 target。
- Site 普通更新的在线成功、在线失败、离线 pending 三种结果改用新 Toast。
- 返回路由显式提供最终可见的 host view：Sites 入口等待 modal 关闭；Site 详情入口等待 modal 关闭及 pop 转场结束。
- 本地持久化失败仍停留 Edit Site 并使用原错误 HUD；Time Zone 更新仍使用原状态卡。
- 新增独立 component/routing contract，并保留既有 Site props、persistence、Time Zone UI contract。

## Figma 资源核对

- 成功 SVG SHA-256：`e307c8e69c1268351064baaa7b0365df7e59c9c4ed86140e7c2f7b2635f964fd`
- 失败 SVG SHA-256：`334dfad5851da48cb9788caa95035e3e3537c8a032c75052141cf2fddb3a67b8`
- 两个 SVG 均通过 XML 结构校验，Asset Catalog 保留矢量表示。

## 自动验证

以下 focused contracts 均通过：

- `SitePropsEditPolicyTests`
- `SitePropsAPIContractTests`
- `SiteTimeZonePersistenceContractTests`
- `SiteUpdateToastUIContractTests` component
- `SiteUpdateToastUIContractTests` routing
- `SiteTimeZoneUIContractTests` full routing
- `SiteTimeZoneUIContractTests` localization/resource membership

以下 generic iPhoneOS Debug 构建均显示 `BUILD SUCCEEDED`：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

`git diff --check` 无输出。构建仍包含工程原有警告，例如 `device_dongle` 资源符号重名、历史 API deprecated/未使用变量；本次未扩展范围处理。

## 尚需人工验收

自动 contract 与构建不能替代真机视觉、真实网络和导航动画验收，建议覆盖：

1. Sites 入口仅改 name，验证在线成功 Toast。
2. Site 详情入口仅改 icon，验证返回动画结束后才展示 Toast。
3. 在线请求失败以及响应 timestamp/已发送字段不匹配，验证失败 Toast 文案。
4. 离线修改 name/icon，验证失败 Toast 且 pending 保留。
5. 历史 pending timezone 加本次 name/icon，验证仍展示 Time Zone 状态卡。
6. 无变化且无 pending，验证不展示 Toast。

## 版本控制

未执行 Git commit、push 或 merge；保留工作树内所有既有修改与未跟踪文档。
