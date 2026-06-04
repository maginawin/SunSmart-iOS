# Battery Power Switch Information Name

## Root Cause

- Battery power switch monitor page title uses `PJEightKeySwitchMonitorViewModel.title`, which returns `PJEightKeySwitchData.name`.
- The Information page was created with only `node`, so `DeviceInformationViewController` displayed `node.name`.
- `DeviceInformationViewController` also prepended `node.group.name` when the current space enabled `displayDeviceNamePrefix`, which made the Information name a computed display value rather than the battery power switch record name.

## Fix

- Added an optional `nameOverride` to `DeviceInformationViewController`.
- Kept the existing `node.name` and group-prefix behavior for all existing call sites that do not pass `nameOverride`.
- Passed `viewModel.title` from `PJEightKeySwitchMonitorVC` when opening Information, so battery power switch Information displays the same real device name shown in the navigation bar.

## Verification

- Static regression check confirmed `PJEightKeySwitchMonitorVC` passes `nameOverride: viewModel.title`.
- iOS build verification should use:

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
