# Lumineux 同名资源回归

Lumineux 在构建期把公共 catalog 与 Lumineux catalog 合并为一份无重名的派生 catalog；共享 SunSmart Swift 只保留四个主题色的 Lumineux 分支，不使用运行时图片染色 helper，也不改共享布局。

## 检查范围

- 57 组已提供图标与 88/120pt Logo 均保持原有 iOS 逻辑尺寸和 1x/2x/3x 图片；AppIcon 为无 alpha 的 1024px 派生文件，AccentColor 为 `#4D738A`。
- Lumineux 的 `Merge Lumineux Assets` phase 每次构建调用 `Lumineux/Scripts/merge_assets.rb`，把 `SunSmart/Assets.xcassets` 复制到 `DERIVED_FILE_DIR` 后以完整 Lumineux asset set 覆盖；Resources 只编译 `LumineuxAssets/Assets-Lumineux-Merged.xcassets`。签名 Team、Bundle ID、协议与独立启动页归属不变。
- 真实 UIKit 测试覆盖 Welcome、菜单/服务器入口、Sites 单元格和滑块回调、启动页及协议内容/路由、Sites 空页、全部已提供图片尺寸与来源、Tab/收藏状态，以及真实 menu/back 导航图片、target/action、渲染 bounds 与返回路径。
- 临时 XCTest bundle 会独立编译完整原始 Lumineux 61 组 catalog（59 个 image set、AppIcon、AccentColor）。主 App 的 `UIImage(named:)` 与该 reference catalog 逐像素 RGBA 对比；common launch logo 仅以三个唯一前缀的 loose PNG 作为严格负对照，不参与正向 catalog 编译。reference bundle ID 必须不同于主 App；不以两次主 bundle 同名读取或平铺 PNG 自比代替来源验证。
- 测试不修改生产工程/AppDelegate，不选择服务器、不登录、不添加站点、不连接或控制真实设备。截图必须人工查看；编译通过不等同于布局通过。

## 静态配置与素材

在仓库根目录执行：

```sh
export LUMINEUX_SOURCE_PACKAGES_DIR=/Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages
ruby Tests/Branding/LumineuxConfigurationTests.rb
ruby Tests/Branding/LumineuxMergeTests.rb
swift Tests/Branding/LumineuxAssetTests.swift
bash scripts/check_nordic_sdk_dependency.sh
git diff --check
```

打包脚本只在更新派生资源时执行，测试不会自动重写图片：

```sh
swift scripts/prepare_lumineux_assets.swift
swift scripts/prepare_lumineux_icons.swift
```

原始 Logo 与 Figma PDF 均不改写；AppIcon 去除 alpha，其他透明图保留透明度。两组显示 Logo 均从 `app_logo_1024.png` 缩小生成，不再放大带灰角的 `launch_logo_88.png` 预览图，打包器禁止源图放大。Logo 测试直接与已确认的高清源图比较，并检查四角在白底合成后没有灰色装饰。图标打包器显式按完整 PDF 画布缩放，保留图形及留白；素材测试同时检查像素尺寸和可见内容范围。

## 实际布局测试

使用 `SunSmart.xcworkspace`，不要切换到现有锁定 revision 不同的 `SunSmart.xcodeproj`。不更新依赖。首次安装需要 `pod install --no-repo-update` 生成被现有规则忽略的 Lumineux Pods 支持文件。

当前 Bugly 的 arm64 slice 仅供真机，因此使用现有 x86_64 iOS 18 模拟器，不替换依赖。测试设备为 iPhone SE 3、iPhone 16、iPad Pro 11 M4，中英文分别运行。

```sh
branding_tmp="$(mktemp -d /private/tmp/lumineux-branding.XXXXXX)"
ruby scripts/make_lumineux_test_workspace.rb "$branding_tmp/runtime"
xcodebuild \
  -workspace "$branding_tmp/runtime/LumineuxBranding.xcworkspace" \
  -scheme LumineuxBranding -configuration Debug \
  -destination 'platform=iOS Simulator,id=9FCF83EB-38F9-4B61-A35E-D88F8665A1B5,arch=x86_64' \
  -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' \
  -destination 'platform=iOS Simulator,id=1B4321CD-F455-4252-8504-105435A02C9A,arch=x86_64' \
  -maximum-concurrent-test-simulator-destinations 1 \
  -derivedDataPath "$branding_tmp/DerivedData" \
  -clonedSourcePackagesDirPath "$LUMINEUX_SOURCE_PACKAGES_DIR" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -resultBundlePath "$branding_tmp/matrix-en.xcresult" \
  -testLanguage en -testRegion US -parallel-testing-enabled NO -jobs 4 \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

其他机器用 `xcrun simctl list devices available` 替换设备 ID。中文沿用命令，把动作改为 `test-without-building`，语言/地区改为 `zh-Hans`/`CN`，结果路径改为新的 `matrix-zh.xcresult`。

```sh
xcrun xcresulttool get test-results summary --path "$branding_tmp/matrix-en.xcresult"
xcrun xcresulttool export attachments --path "$branding_tmp/matrix-en.xcresult" --output-path "$branding_tmp/screenshots-en"
```

## 构建与签名

正式 workspace 构建 Lumineux Release，使用 `-destination 'generic/platform=iOS'`，沿用用户签名设置，不传 `-allowProvisioningUpdates`；用 `codesign -dvv` 验证生成的 App。SunSmart Debug 模拟器回归使用 `ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO`。

构建期合并已替代旧的双 catalog 顺序方案：历史 `resource-only` 探针证明仅调 catalog 顺序仍会加载共享同名图，因此不再作为当前方案。增量 native probe 已验证三轮：新增 Lumineux-only asset 自动进入 Assets.car，移走覆盖 asset 自动恢复 common，移走 Lumineux-only asset 后无残留；证据见 `/private/tmp/lumineux-merge-verification.tOdkwK/incremental-results.json`。

最终验证已完成：英文和简体中文各在 iPhone SE 3、iPhone 16、iPad Pro 11 M4 上通过（每语言 24 个通过、3 个严格预期失败负控、无失败或跳过；合计 48 通过、6 个预期失败）。已逐图审阅 21 张英文和 18 张中文页面截图；最终英文截图与已审版本逐字节相同，中文 Launch 与英文相同，布局、菜单、导航、Tab、按钮、滑块与协议流程均无新增裁切或重叠。

Lumineux Release 已成功构建并通过 `codesign --verify --deep --strict`；签名为 Wen Xu（Y4NBSLQQ63），Team 为 JTD3WYUC58，Info、独立 Launch、iPhone/iPad AppIcon 均正确。Release actool 仅编译生成 merged catalog，且无重复资源警告。SunSmart Debug 亦成功构建且只编译 common catalog；4233 个受保护文件、4 个非 Lumineux target 及全局设置与基线字节一致。这些初轮构建使用 `/tmp` 内的 DerivedData，不能据此确认正常 Library 缓存路径下的脚本沙箱兼容性，后续修正如下。

## 2026-08-28 真机构建沙箱修正

正常 `Library/Developer/Xcode/DerivedData3` 下可复现 `ruby deny file-write-create ...staging-*`。Xcode 生成的规则对 Run Script 输出仅授予 literal 路径权限，不授权其子目录；输出目录加尾斜线无效。独立工程验证移动到 target 临时目录可让合并步骤通过，但完整 App 随后仍在 `[CP] Embed Pods Frameworks` 的 `rsync` 创建框架子目录时被拒绝，因此不采用单纯迁移目录的方案。

最终只将 Lumineux Debug/Release 的 `ENABLE_USER_SCRIPT_SANDBOXING` 设为 `NO`，保持原来的 `DERIVED_FILE_DIR` 输出、完整 asset-set 合并逻辑及路径安全检查。没有修改 Pods 脚本、其他 target 或共享代码；这项设置只影响构建脚本，不改变 iOS App 的运行时沙箱。配置回归明确断言这一兼容设置。

沙箱相关构建验证必须使用正常 Library 路径，例如通过 `mktemp -d /Users/sr/Library/Developer/Xcode/DerivedData3/LumineuxVerification.XXXXXX` 创建独立缓存，再将其传给 `xcodebuild -derivedDataPath`。不要以 `/tmp` 中构建成功替代这项验证，也不要为测试清理日常使用的 DerivedData。

本次已在独立的 `/Users/sr/Library/Developer/Xcode/DerivedData3/LumineuxSandboxProbe.MeQZFc/AppBuild` 完成两次 Lumineux 真机 Debug 构建（第二次不清理缓存），均成功；`codesign --verify --deep --strict` 通过，仍为 Wen Xu / JTD3WYUC58。694 组生成资源逐文件校验通过，其中 58 组完整匹配 Lumineux，其余匹配公共图库。合并器 16 项 / 70 个断言及 Debug/Release 有效配置回归通过；4233 个受保护文件、其他 4 个 target 和项目级设置保持不变。未安装或启动真机 App，也未改动 UI。

构建日志为 `/private/tmp/lumineux-sandbox-fix.yJQ1as/lumineux-debug-fixed.log` 与 `lumineux-debug-incremental.log`；反例日志为同目录的 `lumineux-debug-library.log`（移动目录后仍在 CocoaPods 处被拒绝），原始 Ruby 拒绝见 `/private/tmp/lumineux-merge-verification.tOdkwK/sandbox-library-red.log`。这些路径为本机临时验证产物。

## 2026-08-28 页面素材补充验证

从用户提供的页面原节点补入 `add`（48pt）、`select`（30pt）、`space_add`（30pt），共 3 份 PDF 源文件、9 张 PNG 和 3 份 Contents.json；原 54 组图标与 Logo 逐文件保持一致。未修改打包器、合并脚本、生产工程配置、共享 Swift 或其他品牌资源，仅扩展 manifest、测试和清单。

- 素材测试先确认缺少 `add` 时失败，再补齐素材后通过；57 组图标的节点、尺寸、三套倍率及可见图形检查通过。合并器 16 项 / 70 个断言、Debug/Release 配置回归及 `git diff --check` 均通过。
- 中英文分别在 iPhone SE 3、iPhone 16、iPad Pro 11 M4 上通过：每设备 9 个通过 + 1 个严格预期失败负控，合计 54 个通过、6 个预期失败，无实际失败或跳过。独立 reference catalog 比较覆盖全部 57 组图标，Welcome 的勾选态、Sites 的实际添加按钮和真实 `SpaceFunctionFooterView` 都明确断言图片来自 Lumineux；后者同时检查控件边界、间距、添加/排序回调及编辑/取消状态，不创建真实 Space 或操作 Mesh。
- 已人工审阅 9 张英文、6 张中文的 Welcome/Sites/Space 底部截图，无本轮新增裁切或重叠；3 张中文 Space 底部截图与已审英文截图逐字节相同。Sites 空状态插图仍是待补原图，Space 仅验证真实底部组件，不宣称完整设备页已按稿重做。
- 正式 workspace 的 Lumineux 真机 Debug 构建成功，沿用正常 Library 缓存路径；`codesign --verify --deep --strict` 通过，Wen Xu / JTD3WYUC58 未变。生成 catalog 的 694 组逐文件检查通过：61 组匹配 Lumineux，633 组匹配公共资源。本轮未安装或启动真机 App。

本轮结果与截图保存在 `/private/tmp/lumineux-page-assets.LjWuDY`：`matrix-en.xcresult`、`matrix-zh.xcresult`、`screenshots-en`、`screenshots-zh`、`device-debug.log`。这些路径为本机临时验证产物。

## 2026-08-28 Logo 清晰度与系统启动页复核

Welcome 模糊和灰角来自旧打包器：它把自带灰色圆角的 88×88 预览图放大生成 120pt 的 1x/2x/3x 图片。重新核对 Figma `0:39925` 的 1024px 导出，SHA-256 与仓库的 `Lumineux/DesignAssets/app_logo_1024.png` 一致；现在两组显示 Logo 均从这张高清原图缩小生成，打包器禁止放大源图。仅替换 `launch_logo`、`launch_logo_120` 的六张 PNG，名称、倍率和逻辑尺寸不变；AppIcon、源图、其他图标及主题色不变。

- 质量回归先在旧图片上检出六张图的高清源图不匹配及灰角，再在重新打包后通过；合并器 16 项 / 70 个断言通过。
- UIKit 中英文各在 iPhone SE 3、iPhone 16、iPad Pro 11 M4 上执行：合计 54 个通过、6 个严格预期失败负控，无实际失败或跳过。已人工审阅 9 张英文和 6 张中文的 Launch / Welcome / Menu 截图，无新增灰角、裁切或重叠；三张中文 Launch 截图与已审英文逐字节相同。
- 启动页测试改为读取 App 实际 `UILaunchStoryboardName`，同时另外验证系统冷启动：iPhone 16 模拟器使用 `simctl launch --wait-for-debugger` 将进程停在进入 App 代码前，等待系统启动动画结束后截图。旧版本显示带灰角的 Lumineux 图；不卸载、不清数据，直接覆盖安装新版本后，系统启动画面显示高清 Lumineux 图。该验证与手动实例化 storyboard 的布局测试分开记录。
- 正式 workspace 的 Lumineux 真机 Debug 构建、签名校验通过，仍为 Wen Xu / JTD3WYUC58；694 组生成资源中 61 组逐文件匹配 Lumineux、633 组匹配公共图库。4249 个受保护文件中仅上述六张 PNG 变化，其他四个 target、全局设置、生产工程和合并器保持不变。未安装或启动用户真机 App。

用户真机“仍显示 SunSmart”的现象尚未直接复现，不能据模拟器结果宣称已确认其根因。当前构建包配置为 `Lumineux-LaunchScreen` 且合并 Logo 正确；旧启动快照只是待验证方向，参见 [Apple TN3118](https://developer.apple.com/documentation/technotes/tn3118-debugging-your-apps-launch-screen)。如真机覆盖构建后仍出现旧图，需先核对截图与安装包，不自行卸载 App 或清除站点 / Mesh 数据，也不为未证实的缓存问题修改共享 UI 或资源命名。

本轮本机临时证据位于 `/private/tmp/lumineux-logo-fix.Qad0mL`：`matrix-en.xcresult`、`matrix-zh.xcresult`、`screenshots-en`、`screenshots-zh`、`cold-launch-before.png`、`cold-launch-after-stable.png`。

## 待办边界

剩余 66 组 SLGSync 范围资源见 `docs/lumineux-missing-assets.md`；没有新版的继续保留共享原图。硬编码在共享控件中的剩余紫色按 SLGSync 现状保留，不为其新增 UI 分支。协议正文、服务器、云端身份和空间默认值仍待产品确认。
