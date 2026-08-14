# 4G Gateway 页面优化实施总结

## 实施结论

已按确认的方案 A 完成实现：所有现有路由中的非 WiFi Gateway 继续使用 `GatewayViewController`，并与 WiFi Gateway 共享 Back、More、Delete、Information、Identify、菜单顺序和子页面模态关闭保护；两类 Gateway 仅保留 DFU 行为差异。

本次未新增 `CID 0x0A78 / PID 0x2703` 的设备配置或页面特判。当前仓库仍不能静态证明生产 `/devicesConfig` 已把该 PID 分类为 Gateway。

## 已完成内容

### 共同导航与菜单

- Gateway 基类导航栏改为左侧 Back、右侧 More。
- 新增 Foundation-only 的 `GatewayMenuPolicy`，统一决定 4G/WiFi DFU 类型、Delete 权限、菜单顺序及底部模式。
- 4G Gateway 菜单顺序为 4G DFU、Delete、Information、Identify；无配置权限时只隐藏 Delete。
- WiFi Gateway 菜单保持 WiFi DFU、Delete、Information、Identify。
- Delete 继续调用原删除链路，没有修改权限复核、服务器删除、Mesh Reset、force-delete 或错误处理语义。
- Information 统一打开现有 `DeviceInformationViewController`，参数与 WiFi Gateway 原入口一致，并复用模态导航栈保护。
- Identify 统一调用现有 `MeshAPI.identify`，目标仍是当前 Node 的 Primary Unicast Address。
- 4G DFU 只展示现有 Under Development 提示；WiFi DFU 仍进入现有升级页面。

### 主页面布局

- Gateway 基础 Section 不再包含 Info，因此不再展示 Mac、Address、Model、Device Type、Firmware。
- Activate 继续不加入 Section，只移除 UI 展示，不修改底层属性或同步字段。
- 配置正常时底部改为单独 SAVE；修复状态隐藏底部操作，Delete 统一从菜单进入。
- Associated Spaces、APN、Server Information、Copy Gateway Information、SAVE 和 Repair 的原业务链路保持不变。

### 国际化与多 target

- English 与简体中文均新增 `4g_dfu = 4G DFU`。
- Identify 改为复用现有 `identify` 国际化 Key，不再硬编码标题。
- `GatewayMenuPolicy.swift` 已加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target 的 Compile Sources。

## 测试与验证

### 自动化

- `GatewayMenuPolicyTests`：通过，覆盖 4G/WiFi 菜单顺序、Delete 有无及 SAVE/Hidden 底部模式。
- 17 个 Gateway/Site 聚焦 contract：全部通过。
- `git diff --check`：通过。
- English 与简体中文的 `4g_dfu` Key：各且仅有一条。

### Generic iPhoneOS Debug 构建

以下构建均使用 `CODE_SIGNING_ALLOWED=NO`，未使用 Simulator：

- SunSmart：BUILD SUCCEEDED。
- Archipelago：BUILD SUCCEEDED。
- SLG Sync Plus：BUILD SUCCEEDED。
- SylSmart：BUILD SUCCEEDED。

构建仅出现既有工程警告，包括部分 target 的 Info.plist 位于 Copy Bundle Resources、FSCalendar 源文件重复加入 Compile Sources，以及未依赖 AppIntents 时跳过元数据提取；均未阻断构建，也不是本次改动引入的编译错误。

## 未覆盖的验收边界

- 尚未用真实 4G Gateway 验证 Identify 的设备表现或 Mesh 协议日志。
- 尚未端到端验证服务器 Delete、关联 Space 权限、Mesh Reset 和 force-delete。
- 尚未真机验证 Back 未保存提示、Information/WiFi DFU 子页面返回及下滑关闭手势。
- 尚未获取生产 `/devicesConfig` 响应，因此不能确认 `CID 0x0A78 / PID 0x2703` 当前已被服务器分类为 Gateway。

## 工作树状态

所有改动保留在当前 `time-zone` linked worktree，未 commit、未 push、未合并。
