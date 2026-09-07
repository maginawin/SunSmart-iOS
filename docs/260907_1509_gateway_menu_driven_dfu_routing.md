# 根据 Gateway 菜单类型进入 DFU 页面

## 最终规则

- 菜单显示 `4G DFU`：进入 4G 固件升级页面。
- 菜单显示 `WiFi DFU`：进入 WiFi 固件升级页面。
- 点击时不再检查 PID，不再显示开发中提示。
- Gateway 页面本身如何区分 4G / WiFi，继续使用现有规则，未来新增 PID 时在分类处适配。

本文取代此前 `260907_1503_gateway_2703_dfu_and_classification.md` 中“仅 0x2703 开放 DFU”的阶段性结论；此前的设备分类分析仍适用。

## 实现

`GatewayViewController.makeGatewayMenuItem` 的 `.fourGDFU` 与 `.wifiDFU` 两个分支，分别显式传入 `.fourG` 和 `.wifi`。菜单标题和点击动作在同一个分支内确定，使用类型而非本地化后的字符串判断，因此中英文行为一致。

两种入口调用同一个私有 `performGatewayDFUAction(firmwareKind:)` 方法，传入当前 Node 和菜单指定的固件类型，保留菜单关闭后跳转和模态栈保护。删除 `supportsFourGDFU` 的 PID 白名单，以及 WiFi 子类重复的跳转覆写。

本次仅调整入口选择，沿用现有固件查询协议：4G 使用统一固件设备类型 `2703`、客户标识 `4g` 和服务器原始 URL；WiFi 使用 Node PID、客户标识 `wifi` 和区域下载地址。未来若出现不同固件系列，需要另行扩展固件 Profile 的查询参数；无需在菜单点击处增加 PID 门槛。

未修改 Gateway 的 WiFi PID 分类、内置设备表、本地化、视图约束、SDK、依赖或 target 配置。

## 验证

- 菜单回归检查覆盖两个菜单的标题与对应跳转类型、关闭后执行、统一跳转和模态保护，以及移除 PID 门槛与 WiFi 独立覆写。
- Profile 回归覆盖内置旧 4G PID、`0x2703`、示例未来 4G PID `0x3703` 和示例未来 WiFi PID `0x3721`；未来 PID 仅是测试输入，并未加入产品识别表。
- 继续执行共享 DFU 状态恢复、取消、事务、下载地址与 SDK 协议检查。
- 本轮菜单路由检查、GatewayMenuPolicyTests 与共享 DFU 的七组测试/协议契约全部通过。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个品牌的 Debug / generic iPhoneOS / 禁用签名构建全部通过；`git diff --check` 通过。
- 本次没有布局变更；上一轮要求的真实页面布局和实际网关 OTA 验收仍未完成，不能用构建或静态路由检查替代。
