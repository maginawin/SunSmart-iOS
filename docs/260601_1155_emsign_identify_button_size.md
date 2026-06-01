# EMSign Identify 按钮尺寸调整

## 背景

EMSign 设备页的 Identify 按钮原来复用 `Identify` 图片资源，该资源视觉尺寸为 24pt，和普通灯设备控制页面的 OnOff 按钮不一致。

## 调整方案

- EMSign 设备页 Identify 按钮改用新增资源 `EMSign_identify`。
- `EMSign_identify` 的 1x/2x/3x 资源尺寸为 40/80/120 px，手机端视觉尺寸与普通灯 OnOff 按钮一致。
- 按钮约束同步为手机 40pt、iPad 56pt，匹配普通灯设备控制页 OnOff 按钮的布局尺寸。
- Identify 按钮增加按压 UI 效果：按下时轻微缩小并降低透明度，松开、取消或拖出时恢复原尺寸与透明度。

## 影响范围

仅影响 EMSign 设备页 `DeviceLightViewController` 中 Identify 按钮的图片、尺寸约束与点击视觉反馈，不改变 Identify 指令发送逻辑。
