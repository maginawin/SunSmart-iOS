# Device Parameter Filter Capability Design

## 背景

在 `Site - Space - More - Device Parameter Settings` 中选择某个具体设备类型后，页面会进入该类型下的设备列表。设备列表右上角有 `Filter` 按钮，用于按设备参数值筛选设备。

预期是 `Filter` 弹窗中的参数选项必须与当前设备实际支持的参数能力一致。例如设备不支持 `PWM` 时，不应展示 `PWM` 筛选项；其他参数同理。

## 问题结论

问题真实存在。

当前设备列表 cell 已经按设备能力隐藏不支持的参数行：

- `PWM` 使用 `supportPwmFrequency`
- `Rated Power` 当前作为通用参数展示
- `Absolute Sensitivity` 使用 `supportMotionSensitivity`
- `Transition Time` 使用 `supportDefaultTransitionTime`
- `Change Control Page` 和 `Absolute CCT Range` 使用 `rawSupportCct`

但 `Filter` 弹窗的数据源没有完整复用这套能力判断。尤其是 `--` 选项的生成使用整个 `devices` 集合判断临时值是否为空，未先限定到支持该参数的设备。因此“不支持某参数的设备”会被误认为“该参数值为空”，导致弹窗展示不该出现的参数筛选项。

典型例子：某设备不支持 `PWM`，初始化时不会设置 `tempPwm`，但弹窗生成 `PWM` 内容时看到 `tempPwm == nil`，就可能插入 `--` 并展示 `PWM` section。

## 目标

- `Filter` 弹窗只展示当前设备集合中至少一个设备实际支持的参数类型。
- 每个参数 section 的内容只由支持该参数的设备贡献。
- `--` 只表示“支持该参数，但当前值为空或读取失败”，不表示“不支持该参数”。
- 筛选结果与设备列表中可见参数行保持一致。

## 非目标

- 不修改设备参数设置页的参数编辑逻辑。
- 不修改设备读写协议、Mesh message、SDK 或云同步逻辑。
- 不调整 UI 布局、图片资源、本地化 key 或 target 配置。
- 不扩大到 `All Devices` 的行为重设计；本次只修正当前 Filter 能力匹配问题。

## 方案

采用方案 A：在 `DeviceParameterDevicesViewController` 内做小范围修复，让 Filter 数据生成和筛选应用都基于设备能力判断。

新增一个局部 helper，用于判断某个 `Node` 是否支持某个 Filter 参数类型。该 helper 只服务当前页面，避免引入跨模块抽象。

能力映射如下：

- `pwm` -> `node.supportPwmFrequency`
- `ratedPower` -> 保持当前行为，视为支持
- `absoluteSensitivity` -> `node.supportMotionSensitivity`
- `transitionTime` -> `node.supportDefaultTransitionTime`
- `changeControlPage` -> `node.rawSupportCct`
- `absoluteCctRange` -> `node.rawSupportCct`

## 数据流

1. 页面初始化或参数读取/设置完成后，继续调用 `setupFilterData()` 刷新候选值。
2. `setupFilterData()` 收集每类参数值前，先筛出支持该参数的设备。
3. 构建弹窗内容时，每个参数的 `--` 选项只检查支持该参数的设备是否存在空值。
4. 如果某参数没有任何支持设备，也没有任何有效候选内容，则不创建该参数 section。
5. 用户选择筛选条件后，筛选设备时同步加入能力条件，避免不支持该参数但值为空的设备进入结果。

## 边界处理

- 如果支持某参数的设备全部读取失败，则该参数仍可展示，并只展示 `--`，因为这代表“支持但当前无值”。
- 如果没有任何设备支持某参数，则该参数不展示，即使部分设备的临时值为空。
- 现有已选筛选条件在刷新后如果不再存在于候选内容中，选择态回退为未选中，不保留无效筛选项。
- `Rated Power` 本次保持当前通用展示语义，不新增额外能力判断，避免改变已有业务假设。

## 验证计划

代码级验证：

- 检查 `Filter` 每个 section 都由支持对应参数的设备生成。
- 检查 `--` 生成逻辑只使用支持对应参数的设备。
- 检查筛选闭包中每个参数分支也限制在支持对应参数的设备。

构建验证：

运行 iPhoneOS 构建：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

人工验证建议：

- 选择一个不支持 `PWM` 的具体设备分类，确认 `Filter` 弹窗不出现 `PWM`。
- 选择一个支持 `PWM` 的分类，确认 `PWM` 仍出现，且 `--` 只在支持设备读取失败或值为空时出现。
- 对 `Absolute Sensitivity`、`Transition Time`、`Change Control Page`、`Absolute CCT Range` 做同样检查。
