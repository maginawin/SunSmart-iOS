# Gateway 详情页 Time Zone 与 Clock Sync 实现总结

## 结果

已在 Wi-Fi 与 4G Gateway 共用详情页实现 Time Zone、Gateway/Local 时间、Off by 与手动同步流程。功能仅在当前目标 Gateway 已达到蓝牙 Mesh Proxy Ready 后展示，断开后隐藏。

本实现采用用户确认的四项验收规则：

1. Gateway Offset 与目标 Time Zone 不一致，或目标 Offset 无法 Mesh 编码时，展示 `Sync required`。
2. `Off by` 使用双方应用各自时区后的墙钟时间计算 `Gateway datetime − Local datetime`，包含 Site/Gateway 时区差。
3. 仅最终 `TimeGet` 回读 Offset 一致且偏差在正负 30 秒内时，同步成功。
4. 同步失败保留此前有效 Gateway 样本；原本未知时继续展示 `--`。

## 页面行为

- Section 顺序：
  - 4G：Name → Time Zone → Clock → Associated Spaces → APN → Server Information。
  - Wi-Fi：Name → Time Zone → Clock → Network Connectivity → Associated Spaces → Server Information。
- Time Zone 行复用 Site 固定时区展示语义，无点击和右侧箭头。
- Site 时区缺失或不可解析时，临时使用手机当前 IANA 标识和当前有效 Offset，不写回 Site。
- 页面首次 Proxy Ready 后只执行一次自动 `TimeGet`。
- `Gateway` 和 `Local` 使用 `yyyy-M-d hh:mm:ss a` 格式。
- 展示期间每 0.5 秒读取一次手机时间；`Gateway` 按 `Local + Off by` 通过已保存的差值推进，不重复请求设备。
- `Off by` 正负 30 秒内使用绿色状态点，超出范围使用琥珀色，未知使用灰色；未知状态仍可点击 `Sync clock`。
- `Sync required` 弹窗区分已知 Gateway Offset 与 Gateway 时区未知两种文案。
- 同步期间按钮显示 `Syncing...` 并阻止重复操作。
- 成功与失败 Toast 复用 Edit Site 的 `siteUpdate` 外观。

## Mesh 同步链

1. 校验当前直连 Proxy Ready 必须属于目标 Gateway。
2. 校验目标 Offset 可按 15 分钟步长编码。
3. 校验 Composition 中同时存在 Time Server 与 Time Setup Server。
4. 校验当前 AppKey 为目标 Node 已知。
5. 对未绑定的 Time Server、Time Setup Server 依次发送 `ConfigModelAppBind`，并严格校验回包的状态、Element、Model 与 AppKey。
6. 使用目标固定时区和发送时的手机时间生成并发送 `TimeSet`。
7. 校验 `TimeSet` 返回已知时间且 Offset 一致。
8. 再发送最终 `TimeGet`，按墙钟规则计算偏差。
9. 仅 Offset 一致且偏差在正负 30 秒内时保存 Node 时间并排队更新 Gateway Cloud 快照。
10. 任一步失败均恢复操作前的 Node 时间字段；页面保留此前有效显示样本。

## 主要改动

- 新增 `GatewayDetailClockCoordinator.swift`：目标时区解析、偏差与格式化纯逻辑、展示状态、Mesh 读写协调器。
- 修改 `GatewayViewController.swift`：共用 Section、0.5 秒刷新、弹窗、Toast 和 Off by Cell。
- 修改 `WiFiGatewayViewController.swift`：复用共用 Proxy Ready 时钟逻辑，并调整 Network Connectivity 顺序。
- 新增中英文用户文案。
- 新文件加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target。
- 新增纯逻辑测试和源码契约测试，并纳入现有 Gateway 时间检查脚本。

## 验证结果

以下检查通过：

- Gateway Detail Clock 纯逻辑测试。
- Gateway Detail Clock Runtime/UI 契约测试。
- 既有 Gateway Information、Fast Add Time、Wi-Fi Proxy Ready 相关测试与契约。
- 两套 `Localizable.strings` 和 `project.pbxproj` 的 `plutil` 校验。
- `git diff --check`。
- iPhoneOS generic device、Debug、关闭签名构建：
  - SunSmart：通过。
  - Archipelago：通过。
  - SLG Sync Plus：通过。
  - SylSmart：通过。

## 尚未覆盖

- 未进行真实 Wi-Fi/4G Gateway 的 BLE/Mesh 联调。
- 未覆盖 Composition 缺少 Time Model、Model 未绑定、Config Bind 拒绝、TimeSet/TimeGet 超时等固件级实机矩阵。
- 未验证 Gateway Cloud 同步的服务端最终结果；当前证据仅确认本地排队路径。
- 未进行四品牌真机视觉、动态字体、横竖屏与本地化截断验收。
- Figma 中未知时间的按钮原型为不可用，但本实现按需求文本优先，保持 `Sync clock` 可点击。
