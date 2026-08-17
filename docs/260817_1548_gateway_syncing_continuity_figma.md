# Gateway Syncing 连续状态与 Figma 样式实现总结

## 目标

- 点击 `Sync clock` 后立即进入 `Syncing...`，过程中不得短暂恢复正常按钮。
- 同步态左侧展示并旋转 loading Icon，样式参考 Figma `399:13367`。

## 问题原因

进入网关页面后，初始 `TimeGet` 可能仍在执行。用户在此期间点击同步时，按钮先进入同步态，但旧读取结果通过共享的状态更新方法清除了 `isSyncing`，造成同步文案回弹；同时协调器仍被读取操作占用，真正同步无法立即启动。

## 实现

- 按钮在点击处理的第一步直接切换同步态，不等待控制器或网关回调。
- 分离普通读取结果与同步完成：普通 `TimeGet` 只更新样本，不再结束同步态。
- 用户点击时若初始读取仍在进行，则保持同步态并排队同步；读取完成后立即启动真正的同步操作。
- Proxy 断开时清理排队同步，避免失效操作继续执行。
- 使用 Figma 导出的原始 SVG：24 pt Icon 容器、16 pt 可见图形、6 pt 图文间距、8/12 pt 左右内边距。
- Icon 使用线性循环旋转；开启 Reduce Motion 时保留静态 Icon。
- 复用项目 `Bar_Color`，保持四个品牌 target 的主题适配。

## 验证

- `bash scripts/check_gateway_information_time.sh`：通过。
- `git diff --check`：通过。
- generic iPhoneOS、Debug、关闭签名构建：
  - `SunSmart`：通过。
  - `Archipelago`：通过。
  - `SLG Sync Plus`：通过。
  - `SylSmart`：通过。

## 未覆盖

- 未进行真机快速点击、BLE/Mesh 回包竞态验证。
- 未进行四品牌真机动画与布局视觉验收。
