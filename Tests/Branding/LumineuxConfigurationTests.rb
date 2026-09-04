#!/usr/bin/env ruby
# frozen_string_literal: true

root = File.expand_path('../..', __dir__)
checker = File.join(root, 'scripts/check_lumineux_configuration.rb')

abort('Lumineux configuration checker failed') unless system('ruby', checker)

puts 'LumineuxConfigurationTests passed'
