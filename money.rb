#!/usr/bin/ruby

require 'zip'
require 'fileutils'

# Read the filename
fn = ARGV.shift

# Read new desired money
money = ARGV.shift

if fn.nil?
  puts "Usage: #{$0} <save slot dir | world.data> [new money]"
  exit(1)
end

if money && money !~ /^\d+$/
  puts "Money must be a non-negative integer, got: #{money}"
  exit(1)
end

if fn.end_with?('world.data')
  fn = File.dirname(fn)
end

world_file = File.join(fn, 'world.data')

if !File.exist?(world_file)
  puts "Couldn't find world.data in #{fn}"
  exit(1)
end

entry_name = nil
world_data = nil

# Step 1: read the data
Zip::File.open(world_file) { |zfile|
  # Since there is only one file, grab the first entry
  entry = zfile.first
  entry_name = entry.name

  # Read the uncompressed data directly into memory
  world_data = entry.get_input_stream.read
}

# Get the current money value and print it
m = world_data.match(/"money":\s*(\d+)/)
if m.nil?
  puts "Couldn't find money in #{world_file}"
  exit(1)
end

puts "Save file has money: #{m[1]}"

# Step 2 (only if user specified new money value): Modify
if money
  world_data.gsub!(/"money":\s*\d+/) { "\"money\":#{money}" }

  # Back up the old file (clobbering an existing backup if preset)
  bak = "#{world_file}.bak"
  FileUtils.cp(world_file, bak)

  # Write a new zip and then replace the original with it
  tmp = "#{world_file}.tmp"
  File.delete(tmp) if File.exist?(tmp)
  Zip::OutputStream.open(tmp) { |zout|
    zout.put_next_entry(entry_name)
    zout.write(world_data)
  }
  File.rename(tmp, world_file)

  puts "Edited money to #{money}"
end
