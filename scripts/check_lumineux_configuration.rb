#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'pathname'
require 'xcodeproj'
require 'json'

ROOT = Pathname.new(__dir__).join('..').realpath
PROJECT_PATH = ROOT.join('SunSmart.xcodeproj')
WORKSPACE_PATH = ROOT.join('SunSmart.xcworkspace')
TARGET_NAME = 'Lumineux'

def fail!(message)
  warn "FAIL: #{message}"
  exit 1
end

def assert(condition, message)
  fail!(message) unless condition
end

def settings_for(target, configuration)
  package_arguments = ['-disableAutomaticPackageResolution', '-skipPackageUpdates']
  if ENV['LUMINEUX_SOURCE_PACKAGES_DIR']
    package_arguments += ['-clonedSourcePackagesDirPath', ENV.fetch('LUMINEUX_SOURCE_PACKAGES_DIR')]
  end
  stdout, stderr, status = Open3.capture3(
    'xcodebuild', '-workspace', WORKSPACE_PATH.to_s,
    '-scheme', target.name, '-configuration', configuration,
    *package_arguments, '-showBuildSettings', '-json'
  )
  assert(status.success?, "xcodebuild could not resolve #{target.name} #{configuration}: #{stderr.strip}")
  entry = JSON.parse(stdout).find { |candidate| candidate['target'] == target.name }
  assert(entry, "No effective build settings returned for #{target.name}")
  entry.fetch('buildSettings')
end

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |candidate| candidate.name == TARGET_NAME }
assert(target, 'Lumineux target is missing')

launch_storyboard_path = ROOT.join('Lumineux/Lumineux-LaunchScreen.storyboard')
assert(launch_storyboard_path.file?, 'Lumineux launch storyboard is missing')
launch_storyboard = launch_storyboard_path.read
assert(launch_storyboard.include?('image="lumineux_launch_logo"'),
       'Lumineux launch storyboard must use its dedicated launch image name')
assert(!launch_storyboard.include?('image="launch_logo"'),
       'Lumineux launch storyboard must not resolve the shared SunSmart launch image name')
assert(ROOT.join('Lumineux/Assets-Lumineux.xcassets/Common/lumineux_launch_logo.imageset').directory?,
       'Lumineux dedicated launch image set is missing')

expected_config_paths = {
  'Debug' => 'Config/Lumineux/Debug.xcconfig',
  'Release' => 'Config/Lumineux/Release.xcconfig'
}
target.build_configurations.each do |configuration|
  expected_path = expected_config_paths.fetch(configuration.name)
  actual_path = configuration.base_configuration_reference&.real_path&.relative_path_from(ROOT)&.to_s
  assert(actual_path == expected_path,
         "#{configuration.name} must resolve through #{expected_path}; got #{actual_path || 'no xcconfig'}")
end

resource_paths = target.resources_build_phase.files_references.map do |reference|
  reference.real_path.relative_path_from(ROOT).to_s
rescue ArgumentError
  reference.path
end
%w[
  Lumineux/Lumineux-LaunchScreen.storyboard
  Lumineux/Privacy\ Policy.html
  Lumineux/User\ Agreement.html
  SunSmart/devices_config.json
  SunSmart/Main/Device/Device1.5/devices1.5.md
].each do |path|
  assert(resource_paths.include?(path), "Lumineux resources must include #{path}")
end
generated_catalog = target.resources_build_phase.files_references.find do |reference|
  reference.source_tree == 'DERIVED_FILE_DIR' &&
    reference.path == 'LumineuxAssets/Assets-Lumineux-Merged.xcassets'
end
assert(generated_catalog, 'Lumineux resources must contain the generated merged asset catalog')
assert(resource_paths.none? { |path| path == 'SunSmart/Assets.xcassets' },
       'Lumineux must not compile the common asset catalog directly')
assert(resource_paths.none? { |path| path == 'Lumineux/Assets-Lumineux.xcassets' },
       'Lumineux must not compile the brand asset catalog directly')
merge_phase = target.build_phases.find { |phase| phase.display_name == 'Merge Lumineux Assets' }
assert(merge_phase, 'Lumineux merge build phase is missing')
expected_inputs = %w[
  $(SRCROOT)/Lumineux/Scripts/merge_assets.rb
  $(SRCROOT)/SunSmart/Assets.xcassets
  $(SRCROOT)/Lumineux/Assets-Lumineux.xcassets
]
assert((expected_inputs - merge_phase.input_paths).empty?,
       'Lumineux merge phase must declare merger and both catalog inputs')
assert(merge_phase.output_paths.include?('$(DERIVED_FILE_DIR)/LumineuxAssets'),
       'Lumineux merge phase must declare its generated catalog directory output')
assert(merge_phase.shell_script.include?('set -eu') &&
       merge_phase.shell_script.include?('"${DERIVED_FILE_DIR}/LumineuxAssets/Assets-Lumineux-Merged.xcassets"'),
       'Lumineux merge phase must invoke the merger with the generated catalog output')
assert(target.build_phases.index(merge_phase) < target.build_phases.index(target.source_build_phase),
       'Lumineux merge phase must run before Sources so asset-symbol generation sees the catalog')
assert(target.build_phases.index(merge_phase) < target.build_phases.index(target.resources_build_phase),
       'Lumineux merge phase must run before resource compilation')
assert(merge_phase.respond_to?(:always_out_of_date) && merge_phase.always_out_of_date == '1',
       'Lumineux merge phase must run every build')
assert(resource_paths.none? { |path| path == 'SunSmart/Base.lproj/LaunchScreen.storyboard' },
       'Lumineux must not package the SunSmart launch storyboard')
assert(resource_paths.none? { |path| path == 'SunSmart/InfoPlist.strings' },
       'Lumineux must not package shared InfoPlist.strings')

expected_settings = {
  'DEVELOPMENT_TEAM' => 'JTD3WYUC58',
  'CODE_SIGN_IDENTITY' => 'Apple Development',
  'CURRENT_PROJECT_VERSION' => '1',
  'MARKETING_VERSION' => '1.0.0',
  'PRODUCT_BUNDLE_IDENTIFIER' => 'com.azoula.sunsmart.Lumineux',
  'INFOPLIST_FILE' => 'Lumineux/Lumineux-Info.plist',
  'INFOPLIST_KEY_CFBundleDisplayName' => 'LumiSmart',
  'INFOPLIST_KEY_UILaunchStoryboardName' => 'Lumineux-LaunchScreen',
  'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
  'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
  # Dynamic catalog output and CocoaPods rsync cannot use literal-only output grants.
  'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO',
  'CODE_SIGN_ENTITLEMENTS' => 'Lumineux/Lumineux.entitlements'
}

%w[Debug Release].each do |configuration|
  settings = settings_for(target, configuration)
  expected_settings.each do |key, value|
    assert(settings[key] == value,
           "#{configuration} resolved #{key} must be #{value.inspect}; got #{settings[key].inspect}")
  end
  assert(settings.fetch('SWIFT_ACTIVE_COMPILATION_CONDITIONS').split.include?('Lumineux'),
         "#{configuration} must enable the Lumineux Swift compilation condition")
end

puts 'PASS: Lumineux target resolves its independent configuration and resources.'
