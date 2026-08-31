#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'

require_relative '../../Lumineux/Scripts/merge_assets'

class LumineuxMergeTests < Minitest::Test
  def test_replaces_common_set_at_its_original_path_without_stale_files
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_set(common, 'Common/logo.imageset', {
        'Contents.json' => '{"images":["common"]}',
        'logo@2x.png' => 'common pixels',
        'old@3x.png' => 'obsolete common pixels'
      })
      write_set(common, 'Other/untouched.imageset', {
        'Contents.json' => '{"images":["untouched"]}',
        'untouched.png' => 'common bytes stay exact'
      })
      write_catalog(brand)
      write_set(brand, 'Common/logo.imageset', {
        'Contents.json' => '{"images":["brand"]}',
        'logo@2x.png' => 'brand pixels'
      })

      LumineuxAssetMerger.merge(common: common, brand: brand, output: output)

      matches = Dir.glob(File.join(output, '**', 'logo.imageset'))
      assert_equal 1, matches.size
      assert_equal File.join(output, 'Common', 'logo.imageset'), matches.first
      assert_equal 'brand pixels', File.binread(File.join(matches.first, 'logo@2x.png'))
      assert_equal '{"images":["brand"]}', File.binread(File.join(matches.first, 'Contents.json'))
      refute File.exist?(File.join(matches.first, 'old@3x.png'))
      assert_equal %w[Contents.json logo@2x.png], Dir.children(matches.first).sort
      assert_equal 'common bytes stay exact', File.binread(File.join(output, 'Other', 'untouched.imageset', 'untouched.png'))
      refute File.exist?(File.join(output, '.lumineux-assets-merger'))
    end
  end

  def test_preserves_group_path_for_a_brand_only_set
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_catalog(brand)
      write_set(brand, 'Profile/chart.imageset', {
        'Contents.json' => '{"images":["brand-only"]}',
        'chart@2x.png' => 'brand-only pixels'
      })

      LumineuxAssetMerger.merge(common: common, brand: brand, output: output)

      set = File.join(output, 'Profile', 'chart.imageset')
      assert_equal 'brand-only pixels', File.binread(File.join(set, 'chart@2x.png'))
      assert_equal 1, Dir.glob(File.join(output, '**', 'chart.imageset')).length
    end
  end

  def test_adds_brand_only_app_icon_and_accent_color
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_catalog(brand)
      write_set(brand, 'AppIcon.appiconset', 'Contents.json' => '{"images":["icon"]}', 'AppIcon.png' => 'icon bytes')
      write_set(brand, 'AccentColor.colorset', 'Contents.json' => '{"colors":["accent"]}')

      LumineuxAssetMerger.merge(common: common, brand: brand, output: output)

      assert_equal 'icon bytes', File.binread(File.join(output, 'AppIcon.appiconset', 'AppIcon.png'))
      assert_equal '{"colors":["accent"]}', File.binread(File.join(output, 'AccentColor.colorset', 'Contents.json'))
    end
  end

  def test_second_run_reverts_removed_override_and_removes_brand_only_set
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_set(common, 'Common/logo.imageset', 'Contents.json' => '{}', 'old@3x.png' => 'common old pixels')
      write_catalog(brand)
      write_set(brand, 'logo.imageset', 'Contents.json' => '{}', 'logo.png' => 'brand pixels')
      write_set(brand, 'OnlyBrand.imageset', 'Contents.json' => '{}', 'only.png' => 'brand-only pixels')
      LumineuxAssetMerger.merge(common: common, brand: brand, output: output)

      File.binwrite(File.join(brand, 'logo.imageset', 'logo.png'), 'brand updated pixels')
      LumineuxAssetMerger.merge(common: common, brand: brand, output: output)
      assert_equal 'brand updated pixels', File.binread(File.join(output, 'Common', 'logo.imageset', 'logo.png'))

      FileUtils.rm_rf(File.join(brand, 'logo.imageset'))
      FileUtils.rm_rf(File.join(brand, 'OnlyBrand.imageset'))
      LumineuxAssetMerger.merge(common: common, brand: brand, output: output)

      assert_equal 'common old pixels', File.binread(File.join(output, 'Common', 'logo.imageset', 'old@3x.png'))
      refute File.exist?(File.join(output, 'Common', 'logo.imageset', 'logo.png'))
      refute File.exist?(File.join(output, 'OnlyBrand.imageset'))
    end
  end

  def test_never_mutates_source_catalogs
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_set(common, 'Common/logo.imageset', 'Contents.json' => '{}', 'common.png' => 'common pixels')
      write_catalog(brand)
      write_set(brand, 'logo.imageset', 'Contents.json' => '{}', 'brand.png' => 'brand pixels')
      before = snapshot(common, brand)

      LumineuxAssetMerger.merge(common: common, brand: brand, output: output)

      assert_equal before, snapshot(common, brand)
    end
  end

  def test_rejects_duplicate_asset_names_in_one_catalog
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_set(common, 'One/logo.imageset', 'Contents.json' => '{}')
      write_set(common, 'Two/logo.imageset', 'Contents.json' => '{}')
      write_catalog(brand)

      error = assert_raises(LumineuxAssetMerger::Error) { LumineuxAssetMerger.merge(common: common, brand: brand, output: output) }

      assert_match(/duplicate asset name logo/, error.message)
      refute File.exist?(output)
    end
  end

  def test_rejects_malformed_json_without_replacing_previous_output
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_set(common, 'logo.imageset', 'Contents.json' => '{}', 'logo.png' => 'common')
      write_catalog(brand)
      write_set(brand, 'logo.imageset', 'Contents.json' => '{}', 'logo.png' => 'brand')
      LumineuxAssetMerger.merge(common: common, brand: brand, output: output)
      File.binwrite(File.join(brand, 'Contents.json'), '{not json')

      error = assert_raises(LumineuxAssetMerger::Error) { LumineuxAssetMerger.merge(common: common, brand: brand, output: output) }

      assert_match(/malformed JSON/, error.message)
      assert_equal 'brand', File.binread(File.join(output, 'logo.imageset', 'logo.png'))
    end
  end

  def test_rejects_missing_asset_metadata_and_incompatible_types
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_set(common, 'logo.imageset', 'Contents.json' => '{}')
      write_catalog(brand)
      write_set(brand, 'logo.colorset', 'Contents.json' => '{}')

      incompatible = assert_raises(LumineuxAssetMerger::Error) { LumineuxAssetMerger.merge(common: common, brand: brand, output: output) }
      assert_match(/incompatible types/, incompatible.message)

      FileUtils.rm_f(File.join(brand, 'logo.colorset', 'Contents.json'))
      missing = assert_raises(LumineuxAssetMerger::Error) { LumineuxAssetMerger.merge(common: common, brand: brand, output: output) }
      assert_match(/missing Contents.json/, missing.message)
    end
  end

  def test_rejects_namespace_metadata
    with_catalogs do |common, brand, output|
      write_catalog(common)
      File.binwrite(File.join(common, 'Contents.json'), '{"properties":{"provides-namespace":true}}')
      write_catalog(brand)

      error = assert_raises(LumineuxAssetMerger::Error) { LumineuxAssetMerger.merge(common: common, brand: brand, output: output) }

      assert_match(/provides-namespace/, error.message)
    end
  end

  def test_preserves_existing_output_outside_the_dedicated_scope
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_catalog(brand)
      unscoped_output = File.join(File.dirname(File.dirname(output)), 'Assets-Lumineux-Merged.xcassets')
      FileUtils.mkdir_p(unscoped_output)
      File.binwrite(File.join(unscoped_output, 'keep.txt'), 'do not delete')

      error = assert_raises(LumineuxAssetMerger::Error) { LumineuxAssetMerger.merge(common: common, brand: brand, output: unscoped_output) }

      assert_match(/DERIVED_FILE_DIR\/LumineuxAssets/, error.message)
      assert_equal 'do not delete', File.binread(File.join(unscoped_output, 'keep.txt'))
    end
  end

  def test_does_not_allow_a_forged_marker_to_escape_the_dedicated_scope
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_catalog(brand)
      unscoped_output = File.join(File.dirname(File.dirname(output)), 'Assets-Lumineux-Merged.xcassets')
      FileUtils.mkdir_p(unscoped_output)
      File.binwrite(File.join(unscoped_output, 'keep.txt'), 'do not delete')
      marker = File.join(File.dirname(unscoped_output), '.Assets-Lumineux-Merged.xcassets.lumineux-assets-merger')
      File.binwrite(marker, "LumineuxAssetMerger v1\n")

      error = assert_raises(LumineuxAssetMerger::Error) { LumineuxAssetMerger.merge(common: common, brand: brand, output: unscoped_output) }

      assert_match(/DERIVED_FILE_DIR\/LumineuxAssets/, error.message)
      assert_equal 'do not delete', File.binread(File.join(unscoped_output, 'keep.txt'))
    end
  end

  def test_rejects_a_same_named_scope_outside_derived_file_dir
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_catalog(brand)
      other_output = File.join(File.dirname(File.dirname(output)), 'other', 'LumineuxAssets', 'Assets-Lumineux-Merged.xcassets')
      FileUtils.mkdir_p(other_output)
      File.binwrite(File.join(other_output, 'keep.txt'), 'do not delete')

      error = assert_raises(LumineuxAssetMerger::Error) { LumineuxAssetMerger.merge(common: common, brand: brand, output: other_output) }

      assert_match(/DERIVED_FILE_DIR\/LumineuxAssets/, error.message)
      assert_equal 'do not delete', File.binread(File.join(other_output, 'keep.txt'))
    end
  end

  def test_rejects_unsupported_brand_asset_set_instead_of_dropping_it
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_catalog(brand)
      write_set(brand, 'Payload.dataset', 'Contents.json' => '{}', 'payload.bin' => 'must not disappear')

      error = assert_raises(LumineuxAssetMerger::Error) { LumineuxAssetMerger.merge(common: common, brand: brand, output: output) }

      assert_match(/unsupported asset set type/, error.message)
      refute File.exist?(output)
    end
  end

  def test_preserves_metadata_groups_with_dotted_names
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_catalog(brand)
      group = File.join(common, 'EightKeySwitches1.5')
      FileUtils.mkdir_p(group)
      File.binwrite(File.join(group, 'Contents.json'), '{"info":{"version":1}}')

      LumineuxAssetMerger.merge(common: common, brand: brand, output: output)

      assert_equal '{"info":{"version":1}}', File.binread(File.join(output, 'EightKeySwitches1.5', 'Contents.json'))
    end
  end

  def test_rejects_unsafe_output_paths_and_symlinked_sources
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_catalog(brand)
      bad_name = File.join(File.dirname(output), 'Assets-Other.xcassets')
      error = assert_raises(LumineuxAssetMerger::Error) { LumineuxAssetMerger.merge(common: common, brand: brand, output: bad_name) }
      assert_match(/basename/, error.message)

      redirected = File.join(File.dirname(output), 'redirected-output')
      FileUtils.mkdir_p(redirected)
      File.symlink(redirected, output)
      error = assert_raises(LumineuxAssetMerger::Error) { LumineuxAssetMerger.merge(common: common, brand: brand, output: output) }
      assert_match(/symlink output/, error.message)
      FileUtils.rm_f(output)

      external = File.join(File.dirname(output), 'external.imageset')
      write_set(File.dirname(external), File.basename(external), 'Contents.json' => '{}')
      File.symlink(external, File.join(brand, 'linked.imageset'))
      error = assert_raises(LumineuxAssetMerger::Error) { LumineuxAssetMerger.merge(common: common, brand: brand, output: output) }
      assert_match(/contains a symlink/, error.message)
    end
  end

  def test_rejects_output_that_contains_a_source_catalog
    with_catalogs do |_common, brand, output|
      source_inside_output = File.join(output, 'common.xcassets')
      write_catalog(source_inside_output)
      write_catalog(brand)

      error = assert_raises(LumineuxAssetMerger::Error) do
        LumineuxAssetMerger.merge(common: source_inside_output, brand: brand, output: output)
      end

      assert_match(/source catalog/, error.message)
    end
  end

  def test_cli_reports_success_and_invalid_argument_error
    with_catalogs do |common, brand, output|
      write_catalog(common)
      write_catalog(brand)
      script = File.expand_path('../../Lumineux/Scripts/merge_assets.rb', __dir__)

      stdout, stderr, status = Open3.capture3('/usr/bin/ruby', script, common, brand, output)
      assert status.success?, stderr
      assert_match(/Merged 0 brand asset set/, stdout)

      _stdout, stderr, status = Open3.capture3('/usr/bin/ruby', script, common, brand)
      refute status.success?
      assert_match(/usage:/, stderr)

      _stdout, stderr, status = Open3.capture3('/usr/bin/ruby', script, common, brand, File.join(File.dirname(output), 'wrong.xcassets'))
      refute status.success?
      assert_match(/Lumineux asset merge failed:.*basename/, stderr)
    end
  end

  private

  def with_catalogs
    Dir.mktmpdir('lumineux-merge-test') do |root|
      previous_derived_file_dir = ENV['DERIVED_FILE_DIR']
      ENV['DERIVED_FILE_DIR'] = root
      begin
        yield File.join(root, 'common.xcassets'),
              File.join(root, 'brand.xcassets'),
              File.join(root, 'LumineuxAssets', 'Assets-Lumineux-Merged.xcassets')
      ensure
        if previous_derived_file_dir
          ENV['DERIVED_FILE_DIR'] = previous_derived_file_dir
        else
          ENV.delete('DERIVED_FILE_DIR')
        end
      end
    end
  end

  def write_catalog(path)
    FileUtils.mkdir_p(path)
    File.binwrite(File.join(path, 'Contents.json'), '{"info":{"author":"xcode","version":1}}')
  end

  def write_set(catalog, relative_path, files)
    directory = File.join(catalog, relative_path)
    FileUtils.mkdir_p(directory)
    files.each { |name, contents| File.binwrite(File.join(directory, name), contents) }
  end

  def snapshot(*catalogs)
    catalogs.each_with_object({}) do |catalog, files|
      Dir.glob(File.join(catalog, '**', '*'), File::FNM_DOTMATCH).sort.each do |path|
        next if File.directory?(path)

        files[path] = File.binread(path)
      end
    end
  end
end
