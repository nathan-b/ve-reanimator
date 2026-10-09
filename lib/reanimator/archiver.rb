require 'fileutils'
require 'reanimator/slot'
require 'time'

module Reanimator
  # Copies a save slot directory into a timestamped directory under the archive
  # and keeps only the newest +max_saves+ archives of each slot.
  class Archiver
    TIMESTAMP_FORMAT = '%Y%m%d_%H%M%S'
    ARCHIVE_NAME = /\A(?<slot>#{Slot::PATTERN})_(?<stamp>\d{8}_\d{6})\z/

    # Split an archive directory name like slot_0_20261006_180629 into its slot
    # ("slot_0") and time. Returns nil for names that are not archives.
    def self.parse_name(name)
      m = ARCHIVE_NAME.match(name)
      m && [m[:slot], Time.strptime(m[:stamp], TIMESTAMP_FORMAT)]
    end

    def initialize(archive_dir:, max_saves: 3, clock: -> { Time.now })
      @archive_dir = archive_dir
      @max_saves = max_saves
      @clock = clock
    end

    # Archive the slot directory containing +world_data_path+.
    # Returns the path of the new archive directory.
    def archive(world_data_path)
      slot_dir = File.dirname(world_data_path)
      slot = File.basename(slot_dir)
      dest = File.join(@archive_dir, "#{slot}_#{@clock.call.strftime(TIMESTAMP_FORMAT)}")
      publish(slot_dir, dest)
      prune(slot)
      dest
    end

    # True if some archive of the same slot already holds a world.data identical
    # to the one at +world_data_path+.
    def holds?(world_data_path)
      slot = File.basename(File.dirname(world_data_path))
      return false unless File.directory?(@archive_dir)

      Dir.children(@archive_dir).any? { |name|
        next false unless self.class.parse_name(name)&.first == slot

        archived = File.join(@archive_dir, name, 'world.data')
        File.file?(archived) && FileUtils.compare_file(archived, world_data_path)
      }
    end

    private

    # Copy +slot_dir+ to +dest+ so that +dest+ only ever appears complete: copy
    # into a hidden temporary directory, then rename it into place. A save made
    # in the same second as an earlier one replaces it.
    def publish(slot_dir, dest)
      tmp = File.join(@archive_dir, ".#{File.basename(dest)}.tmp")
      FileUtils.rm_rf(tmp)
      FileUtils.mkdir_p(tmp)
      FileUtils.cp_r(File.join(slot_dir, '.'), tmp)
      FileUtils.rm_rf(dest)
      File.rename(tmp, dest)
    ensure
      FileUtils.rm_rf(tmp) if tmp
    end

    # Remove all but the newest archives of +slot+. Timestamps sort lexically.
    def prune(slot)
      pattern = /\A#{Regexp.escape(slot)}_\d{8}_\d{6}\z/
      archives = Dir.children(@archive_dir).grep(pattern).sort
      archives.first([archives.size - @max_saves, 0].max).each { |name|
        FileUtils.remove_entry(File.join(@archive_dir, name))
      }
    end
  end
end
