# Gateway Sync clock 按钮优化总结

## 目标

- `Sync clock` 按钮高度固定为 28 pt，圆角固定为 10 pt。
- 点击后 `Syncing...` 至少展示 1 秒，避免网关快速响应导致状态闪回。

## 实现

- 将按钮高度和圆角改为不随屏幕比例缩放的固定值。
- 使用系统单调运行时间计算同步结果返回后仍需等待的展示时长。
- 同步成功、失败以及操作未能启动时统一通过最短展示时长处理，再更新按钮、时钟数据和 Toast。
- 为每次同步分配独立标识；Proxy 断开后作废待展示结果，避免延迟回调更新已失效页面状态。
- 补充核心时长测试与控制器 UI 契约检查。

## 验证

- `bash scripts/check_gateway_information_time.sh`：通过。
- `git diff --check`：通过。
- generic iPhoneOS、Debug、关闭签名构建：
  - `SunSmart`：通过。
  - `Archipelago`：通过。
  - `SLG Sync Plus`：通过。
  - `SylSmart`：通过。

## 未覆盖

- 未进行真机 BLE/Mesh 快速响应与超时响应验证。
- 未进行四品牌真机视觉验收。
