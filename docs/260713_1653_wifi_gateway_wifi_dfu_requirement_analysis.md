# WiFi Gateway WiFi DFU 需求完整性与方案预分析

## 已确认需求

- 设备边界：CID `0x0A78`、PID `0x2721`。
- `WiFiGatewayViewController` 右上角菜单点击 `WiFi DFU` 后进入标题为 `WiFi Firmware Update` 的页面。
- 页面进入后才请求最新 WiFi 固件。
- 最新版本 API：`/sitespace/ota/latest`，参数为 `manufacturerId=0A78`、`deviceType=2721`、`customerId=wifi`。
- 连续点击云图标后显示 `Beta Testing Environment`；密码 `1314` 通过后，使用相同参数并追加 `profile=dev` 查询测试版本。
- 历史版本 API：`/sitespace/ota/history`，同样使用 `customerId=wifi`；测试态追加 `profile=dev`。
- 底部按钮文案为 `UPGRADE`，实际升级流程留到后续规划。
- `Current target version` 当前固定显示 `1.0.0`；本阶段不读取设备、服务器或 Mesh 固件缓存。
- WiFi 页面不展示原 Firmware Version 页面用于删除本地固件缓存的删除按钮。
- WiFi 页面的 `Beta Testing Environment` 弹窗隐藏 `Import from local`；普通 Firmware Version 页面继续保留该入口。
- 本阶段点击 `UPGRADE` 后复用现有 `under_development` 提示，不触发下载、解析、缓存或升级流程。
- `UPGRADE` 沿用版本比较规则：只有服务器版本高于固定版本 `1.0.0` 时启用；版本不高于、服务器无固件或请求失败时禁用，Beta 查询同样适用。
- 后续提供 WiFi 固件版本获取方式后，只替换版本数据源，不改变页面结构。

需求边界已全部确认，可以进入正式设计确认。

## API 结论

历史版本已有明确 API，并且已有字符串 `customerId` 参数，因此不需要向服务器开发者确认另一套历史 API。

需要注意：请求层支持字符串 `customerId`，但现有 `FirmwareServerData.customId` 与本地 `FirmwareData.customId` 是 `UInt16`。服务器返回 `wifi` 时，旧解析会回落为 `0`。本阶段应让 WiFi 流程只把 `wifi` 用作请求身份，不进入 Mesh 固件缓存链；后续 WiFi 升级流程再根据固件格式决定是否建立独立模型。

## 方案比较

### 方案 A：继承并增加窄扩展点（推荐）

保留 `FirmwareVersionViewController` 的共享布局、请求状态和错误态，仅为页面标题、请求 `customerId`、固定版本来源、删除按钮显隐、底部按钮文案与动作、历史页面请求参数、本地导入能力增加可覆写 hook。新增 `WiFiFirmwareUpdateViewController` 承担 WiFi 差异。

该方案符合后续 WiFi `UPGRADE` 流程会独立发展的方向，并避免复制整套 UI。

### 方案 B：单一页面注入配置

由同一个控制器接收标题、请求身份和动作闭包。当前改动较少，但后续会让 Mesh Download 与 WiFi Upgrade 状态机集中在同一类中，职责容易膨胀。

### 方案 C：复制页面

短期隔离明显，但会复制大量布局、Beta、历史导航和错误态逻辑，长期维护与 UI 漂移风险最高。

## 推荐设计草案

- 父类默认行为保持不变：`Firmware Version`、`customerId=00`、本地缓存版本、删除按钮、`DOWNLOAD`、Mesh ZIP 下载和导入。
- WiFi 子类固定：`WiFi Firmware Update`、`customerId=wifi`、`Current target version=1.0.0`、隐藏删除按钮、隐藏本地导入入口、`UPGRADE`；按钮按版本比较结果启用，点击只显示 `under_development`。
- `FirmwareVersionHistoryController` 增加字符串 `customerId` 初始化参数，默认仍为 `00`；WiFi 页面传 `wifi`。
- 新增或调整英文和简体中文本地化，英文 UI 精确显示 `WiFi Firmware Update` 与 `UPGRADE`。
- 回归验证应覆盖普通/测试最新版本、普通/测试历史版本、固定版本展示、普通 Firmware Version 默认行为，以及四个品牌 target 的 iPhoneOS Debug 构建。
