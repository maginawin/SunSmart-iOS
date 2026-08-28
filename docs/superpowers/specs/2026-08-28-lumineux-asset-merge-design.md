# Lumineux 构建前资源合并设计

用户已选择“构建前自动合并”，本文件记录已确认方案，不扩大品牌改造范围。

## 目标与边界

仅在构建 Lumineux 时，复制公共图库到构建目录，再用 Lumineux 同名资源完整替换，最终只编译这一份无重名图库。缺少新版的资源继续使用公共版本。资源名称、原始文件、共享业务代码及其他 target 均不变。当前已确定的名称、Bundle ID、Wen Xu 签名、四个主题色和独立协议保持不变。服务器、云端身份、空间默认值及协议文案不在本次范围。

## 数据流与构建依赖

输入是 `SunSmart/Assets.xcassets` 和 `Lumineux/Assets-Lumineux.xcassets`；输出是 `$(DERIVED_FILE_DIR)/LumineuxAssets/Assets-Lumineux-Merged.xcassets`。按资源名称而非相对目录匹配，整组替换 `.imageset`、`.colorset`、`.appiconset`，不混用旧倍率文件。公共目录层级保留；品牌新增项可置于派生目录根部。输入内部重名、类型不兼容、损坏 JSON、危险输出路径或无法正确处理的 namespace 必须明确失败，不猜测覆盖结果。

Lumineux 增加一个合并 Build Phase，显式声明脚本和两个源目录为输入、独立派生目录为输出；生成图库以 `DERIVED_FILE_DIR` 为源树加入 Lumineux 的 Resources。原两份 catalog 仅从 Lumineux 的 Resources 移除，仍保留工程引用，供其他 target 使用。Xcode 原生 actool 负责后续 AppIcon、Assets.car、Info.plist 元数据、模拟器／真机差异和签名，不增加自制 actool 替代流程。脚本每次构建执行，确保新图、修改和删除都生效；重建只处理自身生成目录。

2026-08-28 沙箱修正：Run Script 的输出声明只获得该路径的 literal 权限，不能递归写入 staging 子目录。完整 App 的 CocoaPods 框架嵌入步骤也存在同类限制；只对 Lumineux Debug/Release 设置 `ENABLE_USER_SCRIPT_SANDBOXING=NO`，保留原始生成路径和脚本的输出范围保护，不改 Pods 或其他 target。构建回归必须包含正常 `Library/Developer/Xcode` 路径，不能仅依据 `/tmp` 构建成功。

## 验证

合并器测试使用真实临时文件，覆盖跨层级完整替换、未覆盖项保留、品牌新增项、三种资源类型、重复输入与安全路径、源文件不变，以及连续生成时的增删。配置测试验证只有 Lumineux 使用派生图库。首次构建必须使用全新 DerivedData，检查 actool 只有一份图库且无重复资源警告，AppIcon 元数据及签名仍正确。已有 UIKit 测试覆盖 Welcome、菜单、Sites、Tab、按钮、导航及启动页，中英文和三种设备尺寸均需实际运行并查看截图。

如果源 PNG 与 UIKit 解码存在编译期色彩转换差异，使用独立测试 bundle 中只含 Lumineux 源资源的参考图库作对照，并保留源文件校验与错误公共图库的反例验证；不通过放宽差异阈值掩盖错误图片。
