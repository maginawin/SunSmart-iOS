# Device Parameter Details Text Check

## 范围

检查 `Site - Space - More - Device Parameter Settings` 中以下 Details 文案：

- `Change Control Page`
- `Absolute CCT Range`

## 发现

改动前：

- `Change Control Page` 只有一条通用 `change_control_page_message`，不能区分普通 CCT 设备和 `companyIdentifier == 0x0A78 && productIdentifier == 0x2013` 的特殊默认单白光设备。
- `change_control_page_message` 英文内容与要求不一致。
- `absolute_cct_range_message` 英文内容与要求不一致。

## 修复

- 将普通 CCT 设备的 `change_control_page_message` 更新为要求文案。
- 新增 `change_control_page_single_white_default_message`，用于 `companyIdentifier == 0x0A78 && productIdentifier == 0x2013`。
- `DeviceParameterChangeControlPageViewCell.configure` 增加 `noteText` 参数，由 `DeviceParameterSettingsController` 按选中设备类型传入对应 Details 文案。
- 将 `absolute_cct_range_message` 更新为要求文案。
- 同步更新 `zh-Hans` 本地化为对应中文含义。
