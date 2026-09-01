# Lumineux 同名资源回归

Lumineux 在构建期把公共 catalog 与 Lumineux catalog 合并为一份无重名的派生 catalog；共享 SunSmart Swift 只保留四个主题色的 Lumineux 分支，不使用运行时图片染色 helper，也不改共享布局。

## 检查范围

### Catalog 物理分组

`Lumineux/Assets-Lumineux.xcassets` 使用与 SLGSync 相同的十二个一级业务目录：`Common`、`Device`、`Energy`、`FireAlarm1.5`、`Firmware`、`Group`、`Path`、`Profile`、`Scene`、`Site`、`Space`、`Timed`。`AppIcon` 与 `AccentColor` 保留在根目录；当前 Lumineux source catalog 为 119 imageset 加 AppIcon、AccentColor，共 121 组；imageset 全部位于业务目录中。较早批次的 92 组统计保留在下方带日期的历史验证记录中。

`Lumineux/DesignAssets/asset-groups.json` 是生成器的分组来源。`icon-manifest.json` 中的 `Tabs`、`Navigation`、`Buttons` 等字段只描述 Figma 来源，不决定 Xcode 目录。两个资源生成器会拒绝缺失分组、未知分组、错误位置和同名重复资源；重新运行后不得在 catalog 根目录生成 imageset。

- 临时 XCTest reference catalog 与 source catalog 同为 121 组。当前 SLGSync non-Fire 覆盖为 83 / 94，待提供为 11；额外已打包 33，因此已提供总数为 116。Task 6 的构建验收合同为合并 catalog 695 组，其中 121 组匹配 Lumineux、574 组保留 Common。
- 已提供素材均保持原始画布和 iOS 逻辑尺寸；其中 Figma 完整向量节点、`auto`、六组 Common Retina PNG 与本轮 grouped Retina PNG 按各自来源保存。系统启动页另使用独立的 88pt `lumineux_launch_logo`，AppIcon 为无 alpha 的 1024px 派生文件，AccentColor 为 `#4D738A`。
- PNG 文件字节与运行时布局属于不同层次：`switch_proxy_instructions_1` 的 310 × 328pt 原图在 iPhone 现有 324/310 约束下约有 1.2% 纵向压缩；用户确认影响可忽略，本轮不改生产 Swift。
- Lumineux 的 `Merge Lumineux Assets` phase 每次构建调用 `Lumineux/Scripts/merge_assets.rb`，把 `SunSmart/Assets.xcassets` 复制到 `DERIVED_FILE_DIR` 后以完整 Lumineux asset set 覆盖；Resources 只编译 `LumineuxAssets/Assets-Lumineux-Merged.xcassets`。签名 Team、Bundle ID、协议与独立启动页归属不变。
- 真实 UIKit 测试覆盖 Welcome、仅保留用户与关于入口的菜单、Europe-only 服务器地区契约、Sites 单元格和滑块回调、启动页及协议内容/路由、四类真实空状态容器、强制 AUTO 弹窗、全部已提供图片尺寸与来源、Tab/收藏状态，以及真实 menu/back 导航图片、target/action、渲染 bounds 与返回路径。
- 临时 XCTest bundle 会独立编译完整原始 Lumineux 121 组 catalog（119 个 imageset、AppIcon、AccentColor）。主 App 的 `UIImage(named:)` 与该 reference catalog 逐像素 RGBA 对比；common launch logo 仅以三个唯一前缀的 loose PNG 作为严格负对照，不参与正向 catalog 编译。reference bundle ID 必须不同于主 App；不以两次主 bundle 同名读取或平铺 PNG 自比代替来源验证。
- new3 focused UIKit 的真实调用点为 Buoy、Firmware、Profile、Scene 与 Space。Task 3 的 iPhone 16 focused 运行已产生并审阅 18 张附件；Task 5 的 iPhone SE 3、iPhone 16、iPad Pro 11 M4 与 en-US、zh-Hans-CN 六组合矩阵已全部通过并审阅 108 张附件。Task 6 又在全新的正常 `DerivedData3` 目录完成 Debug generic iOS 构建、签名与生成 catalog 验证，实际证据见本页末尾。
- 测试不修改生产工程/AppDelegate，不选择服务器、不登录、不添加站点、不连接或控制真实设备。截图必须人工查看；编译通过不等同于布局通过。

## 静态配置与素材

在仓库根目录执行；不更新或安装依赖。受限环境中将 Swift module cache 指向可写的 `/private/tmp`，需要 `xcodeproj` 时使用 Homebrew Ruby：

```sh
export PATH=/opt/homebrew/opt/ruby/bin:$PATH
export CLANG_MODULE_CACHE_PATH=/private/tmp/lumineux-new3-module-cache
swift Tests/Branding/LumineuxAssetTests.swift
ruby Tests/Branding/LumineuxMergeTests.rb
ruby Tests/Branding/LumineuxGeneratorTests.rb
ruby Tests/Branding/LumineuxConfigurationTests.rb
ruby scripts/validate_lumineux_asset_groups.rb \
  Lumineux/Assets-Lumineux.xcassets \
  Lumineux/DesignAssets/asset-groups.json
git diff --check
git diff -- SunSmart.xcworkspace/xcshareddata/swiftpm/Package.resolved
git diff -- SunSmart.xcodeproj/project.pbxproj
```

最后两条预期无输出；validator 当前有 CLI 入口，不能为方便运行而修改生产脚本。

打包脚本只在更新派生资源时执行，测试不会自动重写图片：

```sh
swift scripts/prepare_lumineux_assets.swift
swift scripts/prepare_lumineux_icons.swift
```

原始 Logo 与 Figma PDF 均不改写；AppIcon 去除 alpha，其他透明图保留透明度。`launch_logo`、`launch_logo_120` 与系统启动页专用的 `lumineux_launch_logo` 均从 `app_logo_1024.png` 缩小生成，不再放大带灰角的 `launch_logo_88.png` 预览图，打包器禁止源图放大。Logo 测试直接与已确认的高清源图比较，并检查四角在白底合成后没有灰色装饰。图标打包器显式按完整 PDF 画布缩放，保留图形及留白；素材测试同时检查像素尺寸和可见内容范围。

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
  -testLanguage en -testRegion US \
  -only-testing:LumineuxBrandingTests/LumineuxRuntimeTests/testProvidedNew3RetinaAssetsFitProductionControls \
  -parallel-testing-enabled NO -jobs 4 \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES

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
  -resultBundlePath "$branding_tmp/matrix-zh.xcresult" \
  -testLanguage zh-Hans -testRegion CN \
  -only-testing:LumineuxBrandingTests/LumineuxRuntimeTests/testProvidedNew3RetinaAssetsFitProductionControls \
  -parallel-testing-enabled NO -jobs 4 \
  test-without-building CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

其他机器用 `xcrun simctl list devices available` 替换设备 ID。两条命令均只执行 new3 focused 方法：英文以 `test` 构建并运行三台设备，中文以相同产物 `test-without-building` 运行三台设备。

```sh
xcrun xcresulttool get test-results summary --path "$branding_tmp/matrix-en.xcresult"
xcrun xcresulttool get test-results summary --path "$branding_tmp/matrix-zh.xcresult"
xcrun xcresulttool export attachments --path "$branding_tmp/matrix-en.xcresult" --output-path "$branding_tmp/screenshots-en"
xcrun xcresulttool export attachments --path "$branding_tmp/matrix-zh.xcresult" --output-path "$branding_tmp/screenshots-zh"
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

用户随后在 iPhone 16 真机上复现了白色启动页。11:05 的真机构建产物已确认 `UILaunchStoryboardName`、编译后的 storyboard 和 `Assets.car` 都包含正确的 Lumineux 专用资源，因此这次现象不是 catalog 漏打包。11:17 的真机 SpringBoard/SplashBoard 日志直接记录了 `found matching snapshot; will not generate` 与 `not purging the cached image; force: 0`，证明系统仍在复用旧的白色启动快照；参见 [Apple TN3118](https://developer.apple.com/documentation/technotes/tn3118-debugging-your-apps-launch-screen)。

后续真机对照进一步确认，临时把 storyboard 改名为 `Lumineux-LaunchScreen-V2`、把 Bundle Version 覆盖为 2，以及整机重启后首次解锁，SplashBoard 都继续返回同一个旧 snapshot `…50CFFB617A46`，没有进入重新生成分支。因此已撤销无效的改名和版本实验，不把缓存规避写入正式配置。用户选择严格保持 SLGSync 的实现边界：最终仍为独立 `Lumineux-LaunchScreen` storyboard 加独立 `lumineux_launch_logo` 资源，不增加 Lumineux 应用内启动层，不修改共享 AppDelegate。当前这台曾安装旧启动页的 iPhone 16 仍显示系统缓存白屏，不能宣称真机问题已由工程代码修复。

本轮本机临时证据位于 `/private/tmp/lumineux-logo-fix.Qad0mL`：`matrix-en.xcresult`、`matrix-zh.xcresult`、`screenshots-en`、`screenshots-zh`、`cold-launch-before.png`、`cold-launch-after-stable.png`。

## 2026-08-29 启动页专用资源

用户真机截图中的紫色光束图标与 `SunSmart/Assets.xcassets/Common/launch_logo.imageset` 完全一致。当时的 Lumineux 构建包虽已把同名 `launch_logo` 合并为 Lumineux 图片，但编译后的启动 storyboard 仍请求这个共享名称。仅替换 asset catalog 内部的同名图片，没有让真机的旧启动画面更新。

SLGSync 的启动 storyboard 并不使用共享 `launch_logo`，而是引用品牌专用的 `slg_launch_logo`。Lumineux 现以同样方式改为 `lumineux_launch_logo`，并在 Lumineux catalog 中新增独立 88pt 1x/2x/3x 资源。该资源与已确认的高清 Lumineux Logo 逐文件一致，启动 storyboard 不再依赖 SunSmart 共享图名。本轮只修改 Lumineux 启动 storyboard、新增的专用 asset、素材生成器及回归测试，没有修改 SunSmart 共享代码、共享图片或其他 target。

回归测试已先在缺少专用资源时失败，补入后通过。UIKit 启动页在 iPhone SE 3、iPhone 16 和 iPad Pro 11 M4 上各通过 1 个实例化与资源来源测试；3 张截图已人工核对，Logo 清晰、无灰角、无裁切或重叠。iPhone 16 模拟器还在不卸载 App、不清除数据的情况下覆盖安装，用 `simctl launch --wait-for-debugger` 在进入 App 代码前捕获系统冷启动画面，已显示新的 Lumineux Logo。真机已完成正式 Build 1 覆盖安装，但 SpringBoard 仍复用旧白色快照；按用户选择的方案 1 保留该系统缓存现状，不以应用内启动层规避。

正式 `SunSmart.xcworkspace` 的 Lumineux 真机 Debug 构建已在用户当前 `DerivedData3` 路径中成功，`codesign --verify --deep --strict` 通过，Team 仍为 JTD3WYUC58。最终配置的 `UILaunchStoryboardName` 为 `Lumineux-LaunchScreen`，二进制 storyboard 只引用 `lumineux_launch_logo`，`Assets.car` 包含 88/176/264px 三套专用 rendition。生成 catalog 共 695 组，62 组匹配 Lumineux，其余 633 组保持公共资源。真机系统缓存白屏作为设备状态问题保留记录，不再用额外业务代码规避。

## 2026-08-29 空状态插图

按 Figma 页面语义补入 `site_empty`（`0:11425`）、`group_empty`（`0:2719`）、`scene_empty`（`0:4474`）；`space_empty` 使用实际 “No spaces!” 页面中的插图实例 `2090:132420`。四组均保留完整节点画布，直接使用 Figma 2x/3x PNG，不重绘、改色或修改共享图片调用。

素材测试固定节点、逻辑尺寸、像素尺寸和原始导出 SHA-256。UIKit 测试通过真实 `UIView.showEmptyDataView` 装载四个同名资源，并与独立编译的 Lumineux reference catalog 逐像素比较；iPhone SE 3、iPhone 16、iPad Pro 11 M4 各执行 1 个测试，全部通过。12 张快照均已人工检查，无错图、裁切、重叠或约束歧义。

正式 `SunSmart.xcworkspace` 的 Lumineux 真机 Debug 构建成功，Wen Xu 签名完整性校验通过。合并后的 catalog 仍为 695 组：66 组来自 Lumineux，629 组保留公共资源；真机裁剪后的 `Assets.car` 可查到四组 Lumineux 3x rendition 及对应逻辑尺寸。本轮只构建，未安装或启动真机 App。

## 2026-08-29 24pt 状态与扫描图标

从 Figma 组件 `9339:293204` 补入 `sync_success_small`、`sync_failed_small`、`sync_waiting_small` 和 `device_scan`，并把已有 `sync_loading_small` 的源节点从内层圆环纠正为完整 24pt 组件。共保存 5 份完整节点 PDF，生成对应 1x/2x/3x PNG；没有改共享图片调用或生产 Swift。组件 `9338:150316` 中的 30pt 设备状态图与公共 catalog 当前设计一致，因此不重复放进 Lumineux；无法确认资源名的 `power24`、`repair` 等仍保留原实现。

- 素材测试先在缺少 `sync_success_small` 时失败，补齐后 61 组 manifest 的节点、尺寸、倍率和可见范围全部通过；合并器 16 项 / 70 个断言、Lumineux 配置、Nordic SDK 配置与 `git diff --check` 均通过。
- 真实 `SyncDeviceViewCell` 与 `DeviceAddCandidateDeviceListView` 在 iPhone SE 3、iPhone 16、iPad Pro 11 M4 上分别以英文和简体中文执行，合计 6 个通过、无失败或跳过。12 张最终截图已人工核对，4 个同步状态图标与扫描图标均无错图、裁切、重叠或约束歧义。
- 正式 `SunSmart.xcworkspace` 的 Lumineux 真机 Debug 构建在正常 `DerivedData3` 路径成功，`codesign --verify --deep --strict` 通过，签名仍为 Wen Xu / JTD3WYUC58。生成 catalog 共 695 组；70 组 Lumineux asset set 已逐组与源 catalog 一致，其余 625 组保留公共资源。本轮只构建，未安装或启动真机 App。

本轮测试结果与截图保存在 `/private/tmp/lumineux-status.F3a1xm`，正式构建产物位于 `/Users/sr/Library/Developer/Xcode/DerivedData3/LumineuxFigmaAssets.UzlG2a/AppBuild`；这些路径均为本机临时验证产物。

## 2026-08-29 外部 PNG 素材补充

从用户提供的 `/Users/sr/Documents/SunSmart/assets` 中仅接入可唯一映射的 40pt `auto`。原始 2x/3x PNG 存档在 `Lumineux/DesignAssets/Provided` 并逐字节保持不变，catalog 的 1x 由 2x 机械缩小生成。文件夹中的扫描、加减号和电源图标要么已经接入，要么无法唯一映射到待补资源，因此没有覆盖现有版本。

- 素材测试先因缺少 `auto@2x.png` 失败，补入后通过固定 SHA-256、40pt 画布和 1x/2x/3x 完整性检查。
- 真实 `PJEightKeySwitchForcedAutoPopupController` 在 iPhone SE 3、iPhone 16 上分别以英文和简体中文执行，合计 4 个通过。4 张最终截图已人工核对，标题和 AUTO 图标均无错图、裁切、重叠或约束歧义。iPad 仍使用独立的 56pt `auto_big`，没有放大这张 40pt 图片。
- 正式 Lumineux 真机 Debug 增量构建成功，签名仍为 Wen Xu / JTD3WYUC58；生成 catalog 共 695 组，71 组 Lumineux asset set 逐组匹配源 catalog，`auto` 覆盖已明确验证，其余 624 组保留公共资源。本轮只构建，未安装或启动真机 App。

本轮测试结果与截图保存在 `/private/tmp/lumineux-auto.3yb4Fl`，正式构建沿用上述独立 `LumineuxFigmaAssets.UzlG2a/AppBuild`；这些路径均为本机临时验证产物。

## 2026-08-29 Profile 与 Safe Mode 素材补充

从四个已确认节点补入 `profile_chart_occupancy_daylight`、`schedule_target_select`、`sensor_move` 和 `device_select`。前三组保持完整节点画布；`device_select` 保持项目既有 30pt 画布，把 Figma 的 18pt 图形原尺寸居中，不放大内部图形。四组均使用 PDF 原稿机械生成 1x／2x／3x，没有修改共享 UIKit 代码或图片调用。

- 素材测试先因缺少 `profile_chart_occupancy_daylight` 按预期失败；补入后 65 组 Figma 图标、1 组外部 PNG、4 组空状态、Logo、AppIcon 和 AccentColor 全部通过。
- 主 App 的四个 `UIImage(named:)` 均与独立 reference catalog 逐像素一致；真实 `ProfileTriggerConditionPhasesView`、`ProfilePowerUpBehaviorView`、`GroupSensorView` 及项目 UIButton 图片加载路径在 iPhone 16 的英文、简体中文环境中各执行 3 个测试，合计 6 个通过。
- 8 张最终截图已人工核对：图表和三个小图标均为 Lumineux `#4D738A`，无错图、拉伸、裁切、偏移或文字挤压。测试结果与截图保存在 `/private/tmp/lumineux-profile-safe-mode.gkELNL`。
- 正式 `SunSmart.xcworkspace` 的 Lumineux 真机 Debug 构建成功，`codesign --verify --deep --strict` 通过，Bundle ID 为 `com.azoula.sunsmart.Lumineux`，签名仍为 Wen Xu / JTD3WYUC58。生成 catalog 共 695 组；75 组 Lumineux asset set 逐组与源 catalog 一致，其余 620 组保留公共资源。SunSmart 的 iPhone 16 模拟器 Debug 构建回归同时通过。

## 2026-08-31 Common Retina PNG 素材补充

从用户提供的 `/Users/sr/Documents/SunSmart/assets/new` 中接入 `filter_selected`、`menu_select`、`order_down`、`order_up`、`server_select`、`user_big`。六组源文件存档在 `Lumineux/DesignAssets/Provided/Common`，catalog 逐字节使用原始 2x/3x PNG；Contents.json 保留空的 universal 1x 槽位，不生成 1x 文件。`images/select_3` 与 `value_buoy` 均未接入。

- 静态素材测试固定十二个源文件的 SHA-256、逻辑尺寸、倍率、目录和源文件字节一致性；同时断言每组恰有 1x/2x/3x 三个槽位且 1x 没有文件名。
- UIKit 回归使用真实 `UserSettingsViewController`、`ServerSelectionViewController`、`TitleSelectView` 与 `EnergyStaticDataViewController`，验证六组图片来自独立 reference catalog，并检查实际控件 bounds、包含关系与页面快照。
- 英文和简体中文分别在 iPhone SE 3、iPhone 16、iPad Pro 11 M4 上执行，合计 6 次测试运行，0 失败、0 跳过；24 张快照已逐张核对，六组图片无拉伸、裁切、重叠或越界。正式 `SunSmart.xcworkspace` 的 Lumineux 真机 Debug 构建成功，`codesign --verify --deep --strict` 通过，签名为 Wen Xu / JTD3WYUC58；生成 catalog 共 695 组，其中 81 组逐文件匹配 Lumineux，其余 614 组保留公共资源。本轮未安装或启动真机 App。

## 待办边界

当前仅剩 11 组非 FireAlarm 待提供资源，完整清单见 `docs/lumineux-missing-assets.md`；确认前继续保留共享原图。硬编码在共享控件中的剩余紫色按 SLGSync 现状保留，不为其新增 UI 分支。服务器固定为 Europe；协议正文、云端身份和空间默认值仍待产品确认。

## 2026-09-01 new3 Retina 合同与待办

本轮将 28 对原始 2x/3x PNG 接入为 29 个 Lumineux 资源，`button/Group 160` 是唯一的一对双目标映射。静态合同固定每个目标的分组、像素尺寸、SHA-256、catalog/source 逐字节一致性以及 universal 1x 空槽；不生成 `@1x.png`，不重编码，也不修改生产 Swift。四对排除素材为根目录 `Group 160`、`icon/Nav`、`images/download`、`Proximity/images/数据表`；不接入 FireAlarm 内容。当前数值为 121 source catalog、83 / 94 non-Fire covered、11 non-Fire missing、33 additional packaged、116 provided total；Task 6 的 merged catalog 验收为 695 = 121 Lumineux + 574 Common。

focused XCTest 为：

```text
LumineuxBrandingTests/LumineuxRuntimeTests/testProvidedNew3RetinaAssetsFitProductionControls
```

测试以独立编译的 Lumineux reference catalog 验证 29 个资源并覆盖真实生产容器；每次运行产出 18 张附件。Buoy 在 slider 实际 `valueChanged` 后严格检查布局。四个 `daylight_scheme4...7` 的 `DaylightSensorInstructionsViewCell` 有确认的 2.934pt 竖向 hugging 歧义：不改生产 Swift，仍检查独立来源、可见性、具体 containment 与截图，但只豁免这四个 cell 的通用歧义断言；其他组件保持严格 `hasAmbiguousLayout == false`。

Task 3 的 iPhone 16 focused 运行已审阅 18 张附件。Task 5 已在 iOS 18.0（22A3351）的 iPhone SE 3（`9FCF83EB-38F9-4B61-A35E-D88F8665A1B5`）、iPhone 16（`5E6F7D5C-CC01-4760-8D6E-2489835F1748`）和 iPad Pro 11 M4（`1B4321CD-F455-4252-8504-105435A02C9A`）上完成 en-US `test` 与 zh-Hans-CN `test-without-building`：6 次运行全部通过，0 失败、0 跳过。两份结果分别保存在 `/private/tmp/lumineux-new3-matrix.bEfAtG/matrix-en-accepted.xcresult` 与 `/private/tmp/lumineux-new3-matrix.bEfAtG/matrix-zh-accepted.xcresult`；导出的 `/private/tmp/lumineux-new3-matrix.bEfAtG/screenshots-en-accepted` 和 `/private/tmp/lumineux-new3-matrix.bEfAtG/screenshots-zh-accepted` 各有 54 张附件，共 108 张，已全部人工核对。

iPhone SE 3 的固定高度固件步骤行会让 `mesh_upgrade_guide_1` 和 `mesh_upgrade_guide_3` 越出各自行内容区并产生两处已接受的既有重叠；SunSmart 与 SLGSync 的对应 2x 画布也同为 344 × 202 和 288 × 80。测试仅在该紧凑几何上豁免这两张图的严格行内容 containment，仍验证 Lumineux 独立来源、可见性、有限正尺寸、172 × 101 / 144 × 40 pt 生产 frame、与行的有效交集及外层固件容器 containment；没有修改生产 Swift 或 PNG。其余设备和资源仍使用严格 containment。人工检查确认 buoy、固件、图表、Scene 与 Space lock 等所有其他截图无错图、不合理拉伸/裁切、重叠或越界，iPad 图表继续使用 `_ipad` 分支。

Task 6 使用 `/Users/sr/Library/Developer/Xcode/DerivedData3/LumineuxNew3.GfYbuK` 作为全新正常 Library DerivedData，以 `-disableAutomaticPackageResolution -skipPackageUpdates` 和已缓存的 NordicSigMeshSDK `9504e5ba7286205f8d4749d8127bf2178b19d9a2` 完成 `SunSmart.xcworkspace` / Lumineux / Debug / generic iOS 构建。生成的 `Debug-iphoneos/Lumineux.app` 通过 `codesign --verify --deep --strict`，Bundle ID 为 `com.azoula.sunsmart.Lumineux`，签名为 Apple Development: Wen Xu (Y4NBSLQQ63)，Team 为 `JTD3WYUC58`。

派生 catalog 位于 `Build/Intermediates.noindex/SunSmart.build/Debug-iphoneos/Lumineux.build/DerivedSources/LumineuxAssets/Assets-Lumineux-Merged.xcassets`。独立逐文件 SHA-256 核对得到 695 组：121 组完整匹配 Lumineux source catalog，574 组未覆盖 Common 保持一致；历史 `Initiator` / `initiator` 大小写差异按 actool 的大小写不敏感名称视为同一覆盖。构建日志无 duplicate asset 或 actool error，合并器 17 项 / 72 个断言与 Lumineux 配置检查均通过；`Package.resolved` 和 `project.pbxproj` 相对 Task 6 起点无差异。该步骤只构建，未安装或启动 App。构建、签名和 catalog 核对日志分别为 `/private/tmp/lumineux-new3-task6-build.log`、`/private/tmp/lumineux-new3-task6-signing.log` 与 `/private/tmp/lumineux-new3-task6-catalog-verify.log`。
