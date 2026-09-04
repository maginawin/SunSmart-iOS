#!/usr/bin/env ruby
# frozen_string_literal: true


require 'fileutils'
require 'find'
require 'json'
require 'pathname'

module LumineuxAssetMerger
  OUTPUT_BASENAME = 'Assets-Lumineux-Merged.xcassets'.freeze
  ASSET_TYPES = %w[imageset colorset appiconset].freeze

  class Error < StandardError; end

  module_function

  def merge(common:, brand:, output:)
    common_path = validate_catalog(common, 'common')
    brand_path = validate_catalog(brand, 'brand')
    output_path = validate_output(output, common_path, brand_path)
    common_sets = index_asset_sets(common_path, 'common')
    brand_sets = index_asset_sets(brand_path, 'brand')
    validate_compatible_sets(common_sets, brand_sets)

    staging = create_staging_path(output_path)

    begin
      copy_directory(common_path, staging)
      apply_brand_sets(staging, common_sets, brand_sets)
      replace_output(staging, output_path)
    ensure
      FileUtils.rm_rf(staging) if File.exist?(staging) || File.symlink?(staging)
    end

    { common_sets: common_sets.length, brand_sets: brand_sets.length, output: output_path }
  end

  def validate_catalog(path, label)
    raise Error, "#{label} catalog path is required" if path.nil? || path.to_s.empty?

    expanded = File.expand_path(path)
    raise Error, "#{label} catalog does not exist: #{expanded}" unless File.directory?(expanded)
    reject_symlinks(expanded, "#{label} catalog")
    contents = File.join(expanded, 'Contents.json')
    raise Error, "#{label} catalog is missing Contents.json" unless File.file?(contents)

    validate_json_files(expanded, label)
    expanded
  end

  def validate_output(output, common, brand)
    raise Error, 'output path is required' if output.nil? || output.to_s.empty?
    raise Error, "output basename must be #{OUTPUT_BASENAME}" unless File.basename(output) == OUTPUT_BASENAME
    raise Error, 'output path must be absolute' unless Pathname.new(output).absolute?

    expanded = File.expand_path(output)
    raise Error, 'output path is too broad' if expanded == File::SEPARATOR || File.dirname(expanded) == File::SEPARATOR
    derived_file_dir = ENV['DERIVED_FILE_DIR']
    if derived_file_dir.nil? || derived_file_dir.empty?
      raise Error, 'DERIVED_FILE_DIR is required to establish the output scope'
    end
    expected_parent = File.expand_path(File.join(derived_file_dir, 'LumineuxAssets'))
    unless File.dirname(expanded) == expected_parent
      raise Error, 'output must be exactly inside DERIVED_FILE_DIR/LumineuxAssets'
    end
    [common, brand].each do |source|
      if within?(expanded, source) || within?(source, expanded)
        raise Error, 'output must not be a source catalog, ancestor, or descendant'
      end
    end
    reject_symlink_ancestors(expanded)
    raise Error, "refusing to replace symlink output: #{expanded}" if File.symlink?(expanded)
    raise Error, "output must be a directory when it exists: #{expanded}" if File.exist?(expanded) && !File.directory?(expanded)
    expanded
  end

  def reject_symlinks(root, label)
    Find.find(root) do |entry|
      stat = File.lstat(entry)
      if stat.symlink?
        raise Error, "#{label} contains a symlink: #{entry}"
      end
    end
  end

  def reject_symlink_ancestors(path)
    current = File.dirname(path)
    loop do
      if File.symlink?(current) && !trusted_system_symlink?(current)
        raise Error, "output path is redirected through a symlink: #{current}"
      end
      parent = File.dirname(current)
      break if parent == current
      current = parent
    end
  end

  def trusted_system_symlink?(path)
    return false unless ['/var', '/tmp'].include?(path)

    File.realpath(path).start_with?('/private/')
  rescue Errno::ENOENT
    false
  end

  def validate_json_files(root, label)
    Find.find(root) do |entry|
      next unless File.file?(entry) && File.basename(entry) == 'Contents.json'

      begin
        metadata = JSON.parse(File.binread(entry))
      rescue JSON::ParserError => error
        raise Error, "#{label} catalog has malformed JSON at #{entry}: #{error.message}"
      end
      raise Error, "#{label} catalog Contents.json must contain an object: #{entry}" unless metadata.is_a?(Hash)
      if metadata['provides-namespace'] == true || metadata.fetch('properties', {}).fetch('provides-namespace', false) == true
        raise Error, "#{label} catalog uses unsupported provides-namespace metadata: #{entry}"
      end
    end
  end

  def index_asset_sets(root, label)
    sets = {}
    Find.find(root) do |entry|
      next unless File.directory?(entry)

      type = ASSET_TYPES.find { |candidate| entry.end_with?(".#{candidate}") }
      if type.nil?
        if entry != root && File.file?(File.join(entry, 'Contents.json')) && File.basename(entry).end_with?('set')
          raise Error, "#{label} catalog contains unsupported asset set type #{File.extname(entry)}: #{entry}"
        end
        next
      end

      contents = File.join(entry, 'Contents.json')
      raise Error, "#{label} asset set is missing Contents.json: #{entry}" unless File.file?(contents)
      name = File.basename(entry, ".#{type}")
      raise Error, "#{label} catalog contains duplicate asset name #{name}" if sets.key?(name)

      sets[name] = { path: entry, relative: relative_path(root, entry), type: type }
    end
    sets
  end

  def validate_compatible_sets(common_sets, brand_sets)
    brand_sets.each do |name, brand_set|
      common_set = common_sets[name]
      next unless common_set
      next if common_set[:type] == brand_set[:type]

      raise Error, "asset #{name} has incompatible types: common #{common_set[:type]}, brand #{brand_set[:type]}"
    end
  end

  def apply_brand_sets(staging, common_sets, brand_sets)
    brand_sets.each do |name, brand_set|
      destination_relative = common_sets.key?(name) ? common_sets[name][:relative] : brand_set[:relative]
      destination = File.join(staging, destination_relative)
      FileUtils.rm_rf(destination) if File.exist?(destination)
      copy_directory(brand_set[:path], destination)
    end
  end

  def copy_directory(source, destination)
    FileUtils.mkdir_p(destination)
    Dir.children(source).each do |name|
      source_entry = File.join(source, name)
      destination_entry = File.join(destination, name)
      if File.directory?(source_entry)
        copy_directory(source_entry, destination_entry)
      else
        FileUtils.cp(source_entry, destination_entry, preserve: true)
      end
    end
  end

  def create_staging_path(output)
    parent = File.dirname(output)
    FileUtils.mkdir_p(parent)
    path = File.join(parent, ".#{File.basename(output)}.staging-#{Process.pid}-#{rand(1_000_000)}")
    raise Error, "staging path already exists: #{path}" if File.exist?(path) || File.symlink?(path)
    path
  end

  def replace_output(staging, output)
    FileUtils.rm_rf(output) if File.exist?(output)
    FileUtils.mv(staging, output)
  end

  def relative_path(root, path)
    path.sub(/\A#{Regexp.escape(root)}\/?/, '')
  end

  def within?(child, parent)
    child == parent || child.start_with?(parent.end_with?(File::SEPARATOR) ? parent : "#{parent}#{File::SEPARATOR}")
  end
end

if $PROGRAM_NAME == __FILE__
  unless ARGV.length == 3
    warn "usage: #{$PROGRAM_NAME} COMMON.xcassets BRAND.xcassets #{LumineuxAssetMerger::OUTPUT_BASENAME}"
    exit 1
  end

  begin
    result = LumineuxAssetMerger.merge(common: ARGV[0], brand: ARGV[1], output: ARGV[2])
    puts "Merged #{result[:brand_sets]} brand asset set(s) over #{result[:common_sets]} common set(s): #{result[:output]}"
  rescue LumineuxAssetMerger::Error => error
    warn "Lumineux asset merge failed: #{error.message}"
    exit 1
  end
end
