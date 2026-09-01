# Lumineux 同名资源回归

Lumineux 在构建期把 Common catalog 与 Lumineux catalog 合并为一份无重名的派生 catalog；资源只编译 `$(DERIVED_FILE_DIR)/LumineuxAssets/Assets-Lumineux-Merged.xcassets`。new3 未修改生产 Swift、Xcode 工程或依赖锁定，也不使用运行时图片染色。

## new3 静态资源合同

- `Tests/Branding/LumineuxAssetTests.swift` 固定 28 对原始 Retina PNG 到 29 个资源的分组、2x/3x 像素、SHA-256 和 catalog/source 逐字节一致性；`button/Group 160` 是唯一的一对双目标映射。
- 每个 new3 imageset 有且只有 universal 的 1x 空槽、2x 和 3x 槽位；没有 `@1x.png`，不可重新编码或从 iPhone PNG 生成 iPad 资源。
- Lumineux source catalog 合同为 121 组（119 imageset、`AppIcon`、`AccentColor`）。构建后的验收合同为 695 组：121 Lumineux + 574 Common。
- `scripts/validate_lumineux_asset_groups.rb` 具有两个参数的 CLI 入口；它和 `LumineuxConfigurationTests.rb` 一起检查分组 manifest、工程资源阶段及既有 NordicSigMeshSDK 锁定配置。

本轮 focused UIKit 测试名为：

```text
LumineuxBrandingTests/LumineuxRuntimeTests/testProvidedNew3RetinaAssetsFitProductionControls
```

它通过独立编译的 Lumineux reference catalog 验证全部 29 个资源的来源，并覆盖真实的 Buoy、Firmware、Profile、Scene、Space 容器。`value_buoy` 在 slider 实际触发 `valueChanged` 后仍要求无布局歧义。`DaylightSensorInstructionsViewCell` 的 `daylight_scheme4...7` 四个生产 cell 有已确认的 2.934pt 竖向 hugging 歧义；这四个 cell 不改变生产 Swift，也不作泛化歧义断言，改为严格检查独立来源、可见、具体 containment 与截图。其余容器继续严格检查 `hasAmbiguousLayout == false`。

每次 focused 测试运行会生成 18 张附件，名称为 `New3-common-buoy`、`New3-firmware-header-and-flow`、`New3-firmware-guides`、`New3-profile-instructions`、`New3-profile-charts`、`New3-scene-and-space`（同名表示同类页面的多张快照）。Task 3 已在 iPhone 16 focused 运行中产生并审阅 18 张附件；该单机结果不替代下面六组合矩阵。

## 静态/脚本回归

在仓库根目录执行；不更新或安装依赖：

```sh
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

最后两条预期无输出，确认没有 Package.resolved 或 project.pbxproj diff。若分组 validator 缺少 CLI 才应以 configuration test 中的调用为准；当前脚本有 CLI，不能为方便运行而修改生产脚本。

## Task 5：待执行的六组合 focused UIKit 矩阵

先用 `xcrun simctl list devices available` 找到现有 iPhone SE 3、iPhone 16、iPad Pro 11 M4 的实际 ID；不创建、删除或抹除模拟器。用 Homebrew Ruby 生成临时 workspace：

```sh
export PATH=/opt/homebrew/opt/ruby/bin:$PATH
branding_tmp="$(mktemp -d /private/tmp/lumineux-new3-matrix.XXXXXX)"
ruby scripts/make_lumineux_test_workspace.rb "$branding_tmp/runtime"
```

英文用 `test`，三台设备串行执行；中文用同一构建产物 `test-without-building`，只替换语言、地区和 result bundle：

```sh
xcodebuild \
  -workspace "$branding_tmp/runtime/LumineuxBranding.xcworkspace" \
  -scheme LumineuxBranding -configuration Debug \
  -destination 'platform=iOS Simulator,id=<IPHONE_SE_3_ID>,arch=x86_64' \
  -destination 'platform=iOS Simulator,id=<IPHONE_16_ID>,arch=x86_64' \
  -destination 'platform=iOS Simulator,id=<IPAD_PRO_11_M4_ID>,arch=x86_64' \
  -maximum-concurrent-test-simulator-destinations 1 \
  -derivedDataPath "$branding_tmp/DerivedData" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -resultBundlePath "$branding_tmp/matrix-en.xcresult" \
  -testLanguage en -testRegion US \
  -only-testing:LumineuxBrandingTests/LumineuxRuntimeTests/testProvidedNew3RetinaAssetsFitProductionControls \
  -parallel-testing-enabled NO -jobs 4 \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

中文命令使用相同参数并改为：`-resultBundlePath "$branding_tmp/matrix-zh.xcresult" -testLanguage zh-Hans -testRegion CN test-without-building`。导出两份结果摘要和附件：

```sh
xcrun xcresulttool get test-results summary --path "$branding_tmp/matrix-en.xcresult"
xcrun xcresulttool get test-results summary --path "$branding_tmp/matrix-zh.xcresult"
xcrun xcresulttool export attachments --path "$branding_tmp/matrix-en.xcresult" --output-path "$branding_tmp/screenshots-en"
xcrun xcresulttool export attachments --path "$branding_tmp/matrix-zh.xcresult" --output-path "$branding_tmp/screenshots-zh"
```

验收为 6 个设备/语言组合均通过、每组合 18 张附件（共 108 张）逐张人工检查。重点检查 buoy cap-inset 拉伸、Firmware 大图比例、iPhone/iPad Profile 图表分支、Scene 加号、Space 锁图标、裁切、重叠、越界与除已知四个 Daylight cell 外的布局歧义。Task 5 尚未执行；不要将这项验收写成已通过。

## Task 6：待执行的正常 DerivedData 构建与签名

在正常 Library DerivedData 路径创建独立目录，不清理日常缓存；不允许自动更新依赖：

```sh
derived_dir="$(mktemp -d /Users/sr/Library/Developer/Xcode/DerivedData3/LumineuxNew3.XXXXXX)"
xcodebuild \
  -workspace SunSmart.xcworkspace \
  -scheme Lumineux -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived_dir" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  build
codesign --verify --deep --strict "$derived_dir/Build/Products/Debug-iphoneos/Lumineux.app"
codesign -dvv "$derived_dir/Build/Products/Debug-iphoneos/Lumineux.app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$derived_dir/Build/Products/Debug-iphoneos/Lumineux.app/Info.plist"
```

验收项：实际 Bundle ID、Team 和签名结果如实记录；在构建中间目录核对生成 catalog 为 695（121 Lumineux + 574 Common），无 duplicate asset/actool 错误，且 `Package.resolved` 与 `project.pbxproj` 无 diff。Task 6 尚未执行；不能把旧批次构建或签名结果作为本轮通过证据。
