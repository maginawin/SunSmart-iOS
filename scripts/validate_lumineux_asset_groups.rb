#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

module LumineuxAssetGroups
  APPROVED_GROUPS = %w[
    Common Device Energy FireAlarm1.5 Firmware Group Path Profile Scene Site Space Timed
  ].freeze
  SET_EXTENSIONS = %w[.imageset .appiconset .colorset].freeze
  ROOT_GROUP = 'root'
  ROOT_ASSETS = %w[AppIcon AccentColor].freeze
  class Error < StandardError; end

  module_function

  def validate(catalog:, manifest:)
    parsed_manifest = JSON.parse(File.read(manifest))
    groups = parsed_manifest.fetch('groups')
    assets = parsed_manifest.fetch('assets')

    raise Error, 'Asset groups must equal approved groups' unless groups == APPROVED_GROUPS
    raise Error, 'Asset mappings must be an object' unless assets.is_a?(Hash)

    assets.each do |name, group|
      if group == ROOT_GROUP && !ROOT_ASSETS.include?(name)
        raise Error, "Only AppIcon and AccentColor may use root for #{name}"
      end
      next if group == ROOT_GROUP || APPROVED_GROUPS.include?(group)

      raise Error, "Unknown asset group #{group} for #{name}"
    end

    sets_by_name = index_sets(catalog)
    sets_by_name.each do |name, paths|
      raise Error, "Duplicate asset set #{name}" if paths.length > 1

      group = assets[name]
      raise Error, "Missing asset group for #{name}" unless group

      expected_parent = group == ROOT_GROUP ? catalog : File.join(catalog, group)
      expected_path = File.join(expected_parent, File.basename(paths.first))
      unless File.expand_path(paths.first) == File.expand_path(expected_path)
        raise Error, "Asset set #{name} exists outside mapped group"
      end
    end

    parsed_manifest
  end

  def index_sets(catalog)
    raise Error, "Missing asset catalog #{catalog}" unless File.directory?(catalog)

    Dir.glob(File.join(catalog, '**', '*')).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |path, sets|
      next unless File.directory?(path)
      next unless SET_EXTENSIONS.include?(File.extname(path))

      sets[File.basename(path, File.extname(path))] << path
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort('usage: validate_lumineux_asset_groups.rb CATALOG MANIFEST') unless ARGV.length == 2
  begin
    puts JSON.generate(LumineuxAssetGroups.validate(catalog: ARGV[0], manifest: ARGV[1]))
  rescue LumineuxAssetGroups::Error, JSON::ParserError, KeyError => error
    warn error.message
    exit 1
  end
end
