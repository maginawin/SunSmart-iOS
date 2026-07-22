# Site - Space - Main 设备名称过滤验证记录

## 验证结论

设备名称过滤功能已按确认范围完成，自动化测试、静态检查与四个品牌 target 的 generic iPhoneOS 构建均通过。

本次验证不包含真机交互，因此菜单像素表现、键盘交互、页面栈往返和实际设备控制仍需手工验收。

## 已通过项目

- `DeviceNameFilterSessionTests`：通过。
  - 输入前后空白 Trim。
  - 空或全空白输入重置过滤。
  - 忽略大小写的子串匹配。
  - 保留中间空格。
  - 设备名与组名候选任一匹配。
  - ALL 展示名称参与过滤。
  - 完整集合与可见集合分离。
  - 观察者只接收已提交变化。
  - 输入草稿不修改已提交条件。
- English、简体中文 `Localizable.strings`：`plutil -lint` 通过。
- `SunSmart.xcodeproj/project.pbxproj`：`plutil -lint` 通过。
- selected 图片资源 `Contents.json`：JSON 格式检查通过。
- selected 图片尺寸：1x 为 30×30、2x 为 60×60、3x 为 90×90。
- 三个新增 Swift 业务文件均加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart 的 Sources。
- `git diff --check`：通过。
- 范围审计：只有 Main 下 Lights、Switches、Sensors、Others 启用过滤按钮；Group、Scene、Timed、More 未持有或消费过滤会话。
- 数据语义审计：Footer 数量、Lights ALL 控制、repair、sync 与状态计算继续使用完整集合；列表索引和编辑选择使用可见集合。

## 构建结果

以下命令均使用 Debug、generic iPhoneOS、关闭签名：

- SunSmart：BUILD SUCCEEDED。
- Archipelago：BUILD SUCCEEDED。
- SLG Sync Plus：BUILD SUCCEEDED。
- SylSmart：BUILD SUCCEEDED。

构建中仍可见工程已有的资源符号重复、FSCalendar 重复编译项、Info.plist Copy Bundle Resources 和 ScanQRCode 弃用警告；未发现由本功能引入的编译错误。

## 待手工验收

- 左下角菜单颜色、圆角、阴影、宽度、行高、分隔线及安全区位置与 Figma 一致。
- Search 输入框自动聚焦，系统 clear、键盘 Search、Cancel 和遮罩外点击行为正确。
- 已提交条件回填为 Trim 后文本；Cancel 与遮罩外点击不覆盖旧条件。
- 四分类共享条件与 selected 图片；Reset 同时清除四分类过滤。
- Lights 组名前缀开关、ALL 显示过滤和完整灯具控制行为正确。
- 编辑 Select All 与组选择只作用于可见结果，删除不影响隐藏设备。
- 搜索零结果显示 `No matching devices` / `没有匹配的设备`。
- Main 深层页面返回后保留条件；深层设备列表不受过滤影响。
- Group、Scene、Timed、More 及其深层设备列表始终展示完整数据。
- Pop 回 Site 再进入 Space 后恢复默认状态。
- iPhone 与 iPad 上菜单、搜索卡片和键盘布局不越界。
