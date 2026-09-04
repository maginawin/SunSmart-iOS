#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'

class LumineuxGeneratorTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  ICON_SCRIPT = File.join(ROOT, 'scripts/prepare_lumineux_icons.swift')
  ASSET_SCRIPT = File.join(ROOT, 'scripts/prepare_lumineux_assets.swift')

  def with_fixture
    Dir.mktmpdir('lumineux-generators-') do |directory|
      FileUtils.mkdir_p(File.join(directory, 'Lumineux'))
      FileUtils.cp_r(File.join(ROOT, 'Lumineux/DesignAssets'), File.join(directory, 'Lumineux/DesignAssets'))
      FileUtils.cp_r(File.join(ROOT, 'Lumineux/Assets-Lumineux.xcassets'),
                     File.join(directory, 'Lumineux/Assets-Lumineux.xcassets'))
      yield directory
    end
  end

  def run_script(script, directory)
    Open3.capture3('/usr/bin/xcrun', 'swift', script, chdir: directory)
  end

  def rewrite_manifest(directory)
    path = File.join(directory, 'Lumineux/DesignAssets/asset-groups.json')
    manifest = JSON.parse(File.read(path))
    yield manifest
    File.write(path, JSON.pretty_generate(manifest) + "\n")
  end

  def test_generators_keep_every_imageset_out_of_the_catalog_root
    with_fixture do |directory|
      [ASSET_SCRIPT, ICON_SCRIPT].each do |script|
        _stdout, stderr, status = run_script(script, directory)
        assert status.success?, stderr
      end
      catalog = File.join(directory, 'Lumineux/Assets-Lumineux.xcassets')
      assert_empty Dir.glob(File.join(catalog, '*.imageset'))
      assert File.directory?(File.join(catalog, 'Common/launch_logo.imageset'))
      assert File.directory?(File.join(catalog, 'Device/device_select.imageset'))
      assert File.directory?(File.join(catalog, 'Profile/profile_chart_occupancy_daylight.imageset'))
      assert File.directory?(File.join(catalog, 'Timed/schedule_target_select.imageset'))
    end
  end

  def test_asset_generator_keeps_88pt_launch_logos_retina_only
    with_fixture do |directory|
      catalog = File.join(directory, 'Lumineux/Assets-Lumineux.xcassets/Common')
      %w[launch_logo lumineux_launch_logo].each do |name|
        File.write(File.join(catalog, "#{name}.imageset/#{name}@1x.png"), 'stale-1x')
      end

      _stdout, stderr, status = run_script(ASSET_SCRIPT, directory)
      assert status.success?, stderr

      %w[launch_logo lumineux_launch_logo].each do |name|
        directory_path = File.join(catalog, "#{name}.imageset")
        contents = JSON.parse(File.read(File.join(directory_path, 'Contents.json')))
        one_x = contents.fetch('images').find { |entry| entry.fetch('scale') == '1x' }
        assert_nil one_x['filename'], "#{name} must keep an empty universal 1x slot"
        refute File.exist?(File.join(directory_path, "#{name}@1x.png")),
               "#{name} must remove a stale 1x file"
        [2, 3].each do |scale|
          entry = contents.fetch('images').find { |candidate| candidate.fetch('scale') == "#{scale}x" }
          assert_equal "#{name}@#{scale}x.png", entry.fetch('filename')
          assert File.file?(File.join(directory_path, entry.fetch('filename')))
        end
      end

      full_scale_directory = File.join(catalog, 'launch_logo_120.imageset')
      full_scale_contents = JSON.parse(File.read(File.join(full_scale_directory, 'Contents.json')))
      one_x = full_scale_contents.fetch('images').find { |entry| entry.fetch('scale') == '1x' }
      assert_equal 'launch_logo_120@1x.png', one_x.fetch('filename')
      assert File.file?(File.join(full_scale_directory, one_x.fetch('filename')))
    end
  end

  def test_icon_generator_rejects_a_missing_mapping
    with_fixture do |directory|
      rewrite_manifest(directory) { |manifest| manifest.fetch('assets').delete('add') }
      _stdout, stderr, status = run_script(ICON_SCRIPT, directory)
      refute status.success?
      assert_match(/Missing asset group for add/, stderr)
    end
  end

  def test_icon_generator_rejects_an_unknown_group
    with_fixture do |directory|
      rewrite_manifest(directory) { |manifest| manifest.fetch('assets')['add'] = 'Unknown' }
      _stdout, stderr, status = run_script(ICON_SCRIPT, directory)
      refute status.success?
      assert_match(/Unknown asset group Unknown for add/, stderr)
    end
  end

  def test_icon_generator_rejects_a_non_root_asset_mapped_to_root
    with_fixture do |directory|
      rewrite_manifest(directory) { |manifest| manifest.fetch('assets')['add'] = 'root' }
      _stdout, stderr, status = run_script(ICON_SCRIPT, directory)
      refute status.success?
      assert_match(/Only AppIcon and AccentColor may use root for add/, stderr)
    end
  end

  def test_icon_generator_rejects_duplicate_asset_locations
    with_fixture do |directory|
      catalog = File.join(directory, 'Lumineux/Assets-Lumineux.xcassets')
      FileUtils.cp_r(File.join(catalog, 'Common/add.imageset'), File.join(catalog, 'add.imageset'))
      _stdout, stderr, status = run_script(ICON_SCRIPT, directory)
      refute status.success?
      assert_match(/Duplicate asset set add/, stderr)
    end
  end

  def test_icon_generator_rejects_an_asset_outside_its_mapped_group
    with_fixture do |directory|
      catalog = File.join(directory, 'Lumineux/Assets-Lumineux.xcassets')
      FileUtils.mv(File.join(catalog, 'Common/add.imageset'),
                   File.join(catalog, 'Device/add.imageset'))
      _stdout, stderr, status = run_script(ICON_SCRIPT, directory)
      refute status.success?
      assert_match(/Asset set add exists outside mapped group/, stderr)
    end
  end
end
