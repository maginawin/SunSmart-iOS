# Daylight Sensor Lux Display 实现记录

## 实现结论

已在 `Select daylight sensor` 设备行增加双行照度读数，并按确认规则完成轮询、freshness 和校准生命周期控制：

- Switch On 后每 1 s 向当前选中传感器发送一次 Ambient Light Level Get。
- 有 `steadyDaylightLux` 缓存时先显示灰色读数；无缓存时隐藏整个读数组件。
- 收到来源属于当前传感器、且包含 Present Ambient Light Level 的有效 Sensor Status 后立即显示绿色；不比较 Lux 数字是否变化。
- 每次有效回包都会重新开始 3 s freshness 计时；3 s 内无新有效回包则恢复灰色。
- Switch Off、切换设备、离开页面或未选中设备时停止轮询。
- 校准和 Configuring 全程暂停页面轮询，避免与校准管理器的临时 publication 和 Sensor Status 监听互相干扰。
- Manual Correction 期间保持轮询，并继续更新手动修正界面的 Lux。
- Mesh 暂时断开时保留轮询计时器但跳过发送，连接恢复后可在下一次 tick 自动继续。

## UI 与国际化

实现采用 Figma `ID002` 行的双行文字结构，不复用 Group 页面底部的胶囊背景：

- 第一行：`{value} lx`，12 pt。
- 第二行：`Sensor reading`，12 pt、light。
- steady 状态颜色：`#94A3B8`。
- fresh 状态第一行颜色：`#00D492`，第二行保持 `#94A3B8`。
- 读数位于设备名与 Switch 之间，设备名空间不足时尾部截断。
- 新增 English 与简体中文本地化：`Sensor reading` / `传感器读数`。

freshness 计时器由 Select View 统一管理，而不是由可复用 Cell 自行管理，以避免 Cell 复用、滚动离屏和重复定时器造成状态错位。

## 主要修改范围

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
  - 管理 1 s Lux 轮询。
  - 管理 calibration、configuration、sensor switching 三类暂停原因。
  - 过滤当前传感器的有效 Sensor Status，并刷新 Manual Correction 与设备行 freshness。
- `SunSmart/Main/Group/View/LightSensorCalibrationSelectView.swift`
  - 增加双行 Lux UI。
  - 管理 3 s freshness 计时与 Cell 刷新。
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`

本功能未修改 NordicSigMeshSDK、依赖、资源或 target 配置。

## 验证结果

- `git diff --check`：通过。
- English、简体中文 `Localizable.strings`：`plutil -lint` 通过。
- `SunSmart`：Debug / iphoneos / generic device / no signing 构建通过。
- `Archipelago`：Debug / iphoneos / generic device / no signing 构建通过。
- `SLG Sync Plus`：Debug / iphoneos / generic device / no signing 构建通过。
- `SylSmart`：Debug / iphoneos / generic device / no signing 构建通过。

## 仍需真机验收

- Switch On 后是否按 1 s 节奏发出 Sensor Get，并只接受当前传感器回包。
- Lux 数字未变化但收到有效回包时，绿色 freshness 是否重新计时。
- 断开回包超过 3 s 后是否转灰；无缓存时是否完全隐藏。
- 校准及 Configuring 期间页面是否不再发 Lux Get，结束或取消后是否按预期恢复。
- Manual Correction 期间 Lux 是否持续更新。
- Mesh 断开和恢复后的自动续轮询行为。
- 四品牌、English/简体中文及不同屏幕宽度下的双行布局与截断效果。
