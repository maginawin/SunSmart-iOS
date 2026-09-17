# 从当前 worktree 命令行安装 SunSmart 到 MiPAD

不需要在 Xcode 中打开该 workspace。MiPAD 保持连接、解锁并开启开发者模式，签名沿用当前 SunSmart target 配置和本机已有开发者账号。

## 快捷脚本

已提供可执行脚本 `scripts/install_on_MiPad.sh`，自动定位脚本所属 worktree，依次构建、安装并启动；任一步失败立即停止。

优先使用当前 worktree 的 `SunSmartLocal.xcworkspace`，不存在时回退到 `SunSmart.xcworkspace`；两者都不存在则报错退出。运行时会打印实际使用的 workspace。

```bash
# 默认 Debug
./scripts/install_on_MiPad.sh

# Release
./scripts/install_on_MiPad.sh Release
```

脚本使用固定的 MiPAD 设备 UDID，构建目录按 worktree 目录名隔离在 `/tmp/SunSmart-<worktree目录名>-MiPAD`。启动时从构建产物读取 Bundle ID。创建脚本时仅检查语法和帮助输出，没有执行真机安装。

## 1. 构建已签名的 Debug 包

以下是手动使用主 workspace 的命令；如当前目录存在 `SunSmartLocal.xcworkspace`，将 `-workspace` 参数替换为该名称。上面的脚本会自动选择。

```bash
cd /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/debug-features

xcodebuild \
  -workspace SunSmart.xcworkspace \
  -scheme SunSmart \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'platform=iOS,id=00008103-001E29400CE9401E' \
  -derivedDataPath /tmp/SunSmart-debug-features-MiPAD \
  -allowProvisioningUpdates \
  build
```

只有看到 `BUILD SUCCEEDED` 后才继续安装。此命令保留签名，不能添加仅用于编译校验的 `CODE_SIGNING_ALLOWED=NO`。

## 2. 安装

```bash
xcrun devicectl device install app \
  --device MiPAD \
  /tmp/SunSmart-debug-features-MiPAD/Build/Products/Debug-iphoneos/SunSmart.app
```

## 3. 启动

```bash
xcrun devicectl device process launch \
  --device MiPAD \
  --terminate-existing \
  com.azoula.sunsmart
```

## 4. 不同 worktree 与 Release

- 换 worktree 时，修改第一步的目录和 `derivedDataPath`，第二步使用对应产物路径。独立构建目录可避免不同 worktree 共用产物。
- 两个 worktree 的 SunSmart 默认使用相同 Bundle ID，因此安装会更新 MiPAD 上同一个 App，不会生成两个独立 App。
- 如需测试 Release，把第一步的 `-configuration Debug` 改成 `Release`，并把安装路径中的 `Debug-iphoneos` 改成 `Release-iphoneos`。
- 当前 `debug_features.json` 将 Site 右上角 Trigger Zone 配置为仅 Debug 且 Site 角色为 Owner／Editor 时展示。

以上为用户手动执行命令；本轮未使用这些命令安装正式 SunSmart App。
