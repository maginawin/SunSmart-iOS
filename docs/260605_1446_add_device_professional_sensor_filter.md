# Add Device Professional Motion/Light 展示过滤

## 背景

Professional Add Mode 包含 manual、motion sensing、light sensing、RSSI range 四个入口。本次只调整 motion sensing 和 light sensing 两个入口的设备展示范围。

## 更新范围

- `add based on motion sensing`：仅展示 `light` 和 `sensor` 类型设备。
- `add based on light sensing`：仅展示 `light` 和 `sensor` 类型设备。
- `manual` 和 `RSSI range` 保持原有展示逻辑。

## 实现要点

- 在 `DeviceAddProfessionalModeController` 中新增当前 AddMode 的设备展示判断。
- 扫描分区列表使用过滤后的 `scanDevices` 生成，不修改底层扫描缓存。
- candidate 面板传入当前模式可展示的候选设备，保持计数和实际展示一致。
- candidate 撤销回流时同样按当前模式判断是否回到扫描分区。

## 验证重点

- motion sensing 模式下，扫描列表和候选面板只显示 light、sensor。
- light sensing 模式下，扫描列表和候选面板只显示 light、sensor。
- manual 和 RSSI range 模式仍按原有设备类型展示。
