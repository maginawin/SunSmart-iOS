# WiFi Gateway SIG Mesh Status UI 更新方案

## 需求结论

- 需求真实存在：当前 `WiFiGatewayViewController` 继承 `GatewayViewController`，顶部 table header 仍复用 4G Gateway 的 `GatewayInformationHeaderView`。
- 当前左侧状态是单个 `gateway_online/gateway_offline` 图标加 `Online/Offline` 文案。
- Figma 目标要求 WiFi Gateway 左侧改成 `bluetooth_online/bluetooth_offline` 图标加两段文案：`SIG Mesh` 和 `Online/Offline`。
- 本次范围仅更新左侧 Online/Offline 相关 UI；右侧 WiFi Status 暂不实现，但左侧封装应能复用同一布局样式，方便后续替换右侧 4G Status View。

## Figma 对照

- Online 节点：`211:5832`，名称 `wifi gateway sig online`。
- Offline 节点：`211:5846`，名称 `wifi gateway sig offline`。
- 整体 header 尺寸：343 x 72。
- 左侧 `sig mesh status view`：x=8, y=4, width=130, height=56。
- 图标尺寸：30 x 30。
- 标题文案：`SIG Mesh`，12pt Light，颜色 `#64748B`。
- 状态文案：`Online` / `Offline`，12pt Light，颜色 `#272536`。
- 本地资源已有 `bluetooth_online` / `bluetooth_offline`，3x 资源为 90 x 90，符合 30pt 显示尺寸。

## 推荐方案

推荐在 `GatewayInformationHeaderView` 中封装一个可配置的状态项视图，例如 `GatewayHeaderStatusItemView`，而不是只在现有 `gatewayStateImageView` 和 `gatewayStateLabel` 上硬塞额外 label。

理由：

- 能把 “图标 + 顶部标题 + 底部状态” 封装成独立布局单元，后续右侧 WiFi Status 可以复用同样样式。
- 可以保持 4G Gateway 默认行为不变，只让 WiFi Gateway 配置左侧为 SIG Mesh 样式。
- 改动集中在顶部 header 结构，不触碰 WiFi 网络连接、菜单、Activate、同步等无关逻辑。

## 备选方案

方案 A：只改现有 `gatewayStateImageView` / `gatewayStateLabel`，新增一个 `sigMeshLabel`。

- 优点：代码量最少。
- 缺点：左侧布局继续和 4G 状态强绑定，后续右侧 WiFi Status 复用困难。

方案 B：新增可复用状态项视图，并让 header 左侧使用该 view。

- 优点：符合后续右侧 WiFi Status 复用诉求，边界清晰。
- 缺点：比方案 A 多一个小 view。

方案 C：新建 `WiFiGatewayInformationHeaderView`，WiFi 页面完全专用。

- 优点：完全隔离 4G 和 WiFi。
- 缺点：会复制当前 header 的 Node、右侧区域和连接中状态，后续维护成本更高。

推荐方案 B。

## 实施计划

1. 在 `GatewayInformationHeaderView.swift` 内新增一个小型状态项 view，负责展示图标、标题、状态文案。
2. 将现有左侧 4G Gateway 在线状态迁移到该状态项 view 的默认配置，保持 4G 显示仍为原图标加 `Online/Offline`。
3. 给 `GatewayInformationHeaderView` 增加配置入口，用于切换左侧状态样式。
4. 在 `WiFiGatewayViewController` 初始化或配置 header 时，将左侧样式设置为 SIG Mesh：
   - 在线：`bluetooth_online` + `SIG Mesh` + `online`。
   - 离线：`bluetooth_offline` + `SIG Mesh` + `Offline`。
5. 检查本地化：
   - 优先复用现有 `online` / `Offline`。
   - 若没有合适 key，新增 `sig_mesh` 并同步英文、简体中文。
6. 不改右侧 4G/WiFi Status 行为；仅确保新封装后右侧后续可复用同一状态项 view。

## 验证计划

- 静态检查：
  - 确认 `WiFiGatewayViewController` 仅配置左侧 SIG Mesh 样式。
  - 确认 legacy 4G Gateway 仍使用原左侧 Online/Offline 样式。
  - 确认新增或修改文案已覆盖 `en.lproj` 和 `zh-Hans.lproj`。
- 构建验证：
  - 运行 iPhoneOS 构建：
    `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- 可选轻量脚本：
  - 增加或更新 WiFi Gateway header 检查脚本，校验 `bluetooth_online` / `bluetooth_offline`、`SIG Mesh` 配置入口存在，且未改右侧 signal 逻辑。

## 待确认点

- 是否按推荐方案 B 执行：在共享 header 内封装可复用状态项 view，并仅让 WiFi Gateway 左侧切换为 SIG Mesh 样式。
- `SIG Mesh` 是否需要在中文环境仍显示为 `SIG Mesh`。我建议保持该技术名英文不翻译，但通过本地化 key 管理。

## 实施结果

- 已按推荐方案 B 实现。
- `GatewayInformationHeaderView` 新增可复用状态项 view，并通过 `GatewayHeaderStateStyle` 配置左侧状态样式。
- 4G Gateway 默认左侧状态保持 `gateway_online` / `gateway_offline`，且保持单图标加在线状态文案。
- WiFi Gateway 通过 `makeGatewayInformationHeaderView(frame:)` 配置左侧 SIG Mesh 状态：
  - 在线：`bluetooth_online` + `SIG Mesh` + `online`。
  - 离线：`bluetooth_offline` + `SIG Mesh` + `Offline`。
- 新增 `sig_mesh` 本地化 key，英文和简体中文均显示为 `SIG Mesh`。
- 右侧 4G Status View 未替换，仍保留现有 4G 信号布局，后续可复用状态项 view 单独替换。

## 验证结果

- `bash scripts/check_wifi_gateway_sig_mesh_status_header.sh`：通过。
- `bash scripts/check_wifi_gateway_menu_icons.sh`：通过。
- `bash scripts/check_wifi_gateway_info_rows_hidden.sh`：通过。
- `git diff --check`：通过。
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`：通过。

## 布局细化

- 以 `Online` / `Offline` 状态文案位置为基准调整 SIG Mesh 状态项。
- SIG Mesh 图片底部与 `Online` / `Offline` 顶部间距为 6pt。
- SIG Mesh 图片左边位于 `Online` / `Offline` 左边左侧 8pt，匹配 Figma 中图片相对状态文案的水平位置。
- `SIG Mesh` label 左边与图片右边间距为 2pt。
- `SIG Mesh` label 底部比图片底部高 2pt。
- SIG Mesh 状态项整体相对默认左侧状态项左移 12pt；默认 4G Gateway 状态项不移动。
- `scripts/check_wifi_gateway_sig_mesh_status_header.sh` 已补充上述约束检查。
