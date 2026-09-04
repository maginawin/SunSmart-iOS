#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates a temporary XCTest host using the real app target. Never saves the
# production project, adds test hooks to AppDelegate, or changes package pins.
require 'xcodeproj'
require 'fileutils'
require 'tmpdir'

root = File.expand_path('..', __dir__)
output = ARGV.fetch(0) { Dir.mktmpdir('lumineux-ui-') }
# Resolve existing symlinks as well as '..', including a source-root argument.
# The parent must exist (normally supplied by mktemp -d).
output = File.expand_path(output)
output = if File.exist?(output)
           File.realpath(output)
         else
           File.join(File.realpath(File.dirname(output)), File.basename(output))
         end
abort('Output directory must be outside the source tree') if output == root || output.start_with?(root + '/')
FileUtils.mkdir_p(output)
project = Xcodeproj::Project.open(File.join(root, 'SunSmart.xcodeproj'))
project.root_object.project_dir_path = root
# Absolute source paths make the generated project portable across temp folders.
project.files.each do |reference|
  next unless ['<group>', 'SOURCE_ROOT'].include?(reference.source_tree)
  resolved = reference.real_path.to_s
  reference.path = resolved
  reference.source_tree = '<absolute>'
end
app = project.targets.find { |target| target.name == 'Lumineux' }
abort('Lumineux target not found') unless app
tests = project.new_target(:unit_test_bundle, 'LumineuxBrandingTests', :ios, '15.0')
tests.add_dependency(app)
test_files = Dir[File.join(root, 'Tests/Branding/*RuntimeTests.swift')]
abort('Runtime tests missing') if test_files.empty?
test_files.each { |path| tests.add_file_references([project.main_group.new_file(path)]) }
# Compile the complete original Lumineux catalog into the XCTest bundle. Keeping
# this catalog byte-for-byte separate from common assets preserves the actool
# decoding behavior used by the strict RGBA source oracle.
reference_catalog = File.join(output, 'LumineuxReference.xcassets')
brand_catalog = File.join(root, 'Lumineux/Assets-Lumineux.xcassets')
asset_set_extensions = %w[.imageset .appiconset .colorset]
brand_sets = Dir.glob(File.join(brand_catalog, '**', '*')).select do |path|
  File.directory?(path) && asset_set_extensions.include?(File.extname(path))
end
abort("Expected 132 complete Lumineux catalog sets for reference catalog; found #{brand_sets.length}") unless brand_sets.length == 132
FileUtils.mkdir_p(reference_catalog)
FileUtils.cp_r(File.join(brand_catalog, '.'), reference_catalog)
# The common launch logo stays loose and uniquely named, outside the positive
# catalog, so the negative control cannot change catalog compilation output.
shared_launch = File.join(root, 'SunSmart/Assets.xcassets/Common/launch_logo.imageset')
abort('Shared launch-logo fixture is missing') unless File.directory?(shared_launch)
negative_sources = Dir[File.join(shared_launch, 'launch_logo@*x.png')].sort
abort('Expected three shared launch-logo scale fixtures') unless negative_sources.length == 3
negative_sources.each do |source|
  destination = File.join(output, File.basename(source).sub('launch_logo', 'shared_only_launch_logo'))
  FileUtils.cp(source, destination)
  tests.resources_build_phase.add_file_reference(project.main_group.new_file(destination))
end
tests.resources_build_phase.add_file_reference(project.main_group.new_file(reference_catalog))
tests.resources_build_phase.add_file_reference(project.main_group.new_file(File.join(root, 'Lumineux/DesignAssets/icon-manifest.json')))
tests.build_configurations.each do |configuration|
  # @testable import also loads the app's imported Pods modules.
  pod_config = "Pods-Common-Lumineux.#{configuration.name.downcase}.xcconfig"
  configuration.base_configuration_reference = project.files.find { |ref| ref.path.end_with?(pod_config) }
  abort("Missing #{pod_config}; run pod install first") unless configuration.base_configuration_reference
  configuration.build_settings.merge!(
    'SWIFT_VERSION' => '5.0',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'DEBUG Lumineux',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.azoula.sunsmart.Lumineux.BrandingTests',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/Lumineux.app/Lumineux',
    'BUNDLE_LOADER' => '$(TEST_HOST)',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'CODE_SIGNING_ALLOWED' => 'NO',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks'],
    'FRAMEWORK_SEARCH_PATHS' => ['$(inherited)', '$(PLATFORM_DIR)/Developer/Library/Frameworks'],
    'SWIFT_INCLUDE_PATHS' => ['$(inherited)', '$(BUILT_PRODUCTS_DIR)']
  )
end
app.build_configurations.each { |config| config.build_settings['ENABLE_TESTABILITY'] = 'YES' }
project_path = File.join(output, 'LumineuxBranding.xcodeproj')
project.save(project_path)
# Reload so scheme buildable references point at the generated project, not the
# original project's basename retained by xcodeproj's in-memory object.
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |target| target.name == 'Lumineux' }
tests = project.targets.find { |target| target.name == 'LumineuxBrandingTests' }
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(tests)
scheme.test_action.build_configuration = 'Debug'
scheme.test_action.code_coverage_enabled = false
scheme.set_launch_target(app)
scheme.save_as(project_path, 'LumineuxBranding')
workspace = Xcodeproj::Workspace.new(nil)
workspace << project_path
workspace << File.join(root, 'Pods/Pods.xcodeproj')
workspace_path = File.join(output, 'LumineuxBranding.xcworkspace')
workspace.save_as(workspace_path)
# Use the existing lock unchanged; Xcode is invoked with automatic updates disabled.
resolved = File.join(root, 'SunSmart.xcworkspace/xcshareddata/swiftpm/Package.resolved')
FileUtils.mkdir_p(File.join(workspace_path, 'xcshareddata/swiftpm'))
FileUtils.cp(resolved, File.join(workspace_path, 'xcshareddata/swiftpm/Package.resolved'))
puts workspace_path
