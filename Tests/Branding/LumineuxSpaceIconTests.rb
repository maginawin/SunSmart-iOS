#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'digest'

root = File.expand_path('../..', __dir__)
catalog = File.join(root, 'Lumineux/Assets-Lumineux.xcassets/Space')
sets = Dir[File.join(catalog, 'space_picture_*.imageset')]
abort("Expected 60 Lumineux Space icons, found #{sets.length}") unless sets.length == 60
manifest = JSON.parse(File.read(File.join(root, 'Lumineux/DesignAssets/space-icons.json')))
abort('Space icon IDs must follow Figma order 1...60') unless manifest.fetch('assets').map { |a| a.fetch('id') } == (1..60).to_a

manifest.fetch('assets').each do |asset|
  name = "space_picture_#{asset.fetch('id')}"
  source = File.join(root, 'Lumineux/DesignAssets', asset.fetch('source'))
  abort("Source changed: #{name}") unless Digest::SHA256.file(source).hexdigest == asset.fetch('sha256')
  contents = JSON.parse(File.read(File.join(catalog, "#{name}.imageset/Contents.json")))
  entries = contents.fetch('images')
  abort("Unexpected scale slots: #{name}") unless entries.map { |e| e.fetch('scale') }.sort == %w[1x 2x 3x]
  abort("1x should remain empty: #{name}") if entries.find { |e| e['scale'] == '1x' }.key?('filename')
  [2, 3].each do |scale|
    entry = entries.find { |e| e['scale'] == "#{scale}x" }
    png = File.binread(File.join(catalog, "#{name}.imageset", entry.fetch('filename')))
    abort("Invalid PNG dimensions: #{name} @#{scale}x") unless png.byteslice(16, 8).unpack('NN') == [120 * scale, 96 * scale]
  end
end
puts 'PASS: 60 ordered Figma Space icons, original source hashes, and Retina canvases'
