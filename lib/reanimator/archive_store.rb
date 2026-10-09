require 'fileutils'
require 'reanimator/archiver'

module Reanimator
  # Reads and manages what Archiver has written: lists the archived saves,
  # deletes them and restores them into the game's save directory.
  class ArchiveStore
    class Error < StandardError; end

    # kind is :good or :death; slot is "slot_0" etc.; path is the archive directory.
    Entry = Data.define(:kind, :slot, :time, :path)

    def initialize(archive_dir:, death_dir:)
      @dirs = { good: archive_dir, death: death_dir }
    end

    # The archived saves of +kind+ (:good or :death), newest first.
    def entries(kind)
      dir = @dirs.fetch(kind)
      return [] unless File.directory?(dir)

      Dir.children(dir).filter_map { |name|
        slot, time = Archiver.parse_name(name)
        Entry.new(kind: kind, slot: slot, time: time, path: File.join(dir, name)) if slot
      }.sort_by { |e| [e.time, e.path] }.reverse
    end

    def delete(entry)
      FileUtils.rm_rf(entry.path)
    end

    # Copy the archived files over the ones in the entry's slot in +saves_dir+.
    #
    # The slot directory is kept (the game overwrites files in it and the
    # watcher depends on it), each file is replaced atomically, and files in the
    # slot that are not in the archive are left alone.
    def restore(entry, saves_dir)
      raise Error, "archive no longer exists: #{entry.path}" unless File.directory?(entry.path)

      slot_dir = File.join(saves_dir, entry.slot)
      FileUtils.mkdir_p(slot_dir)
      Dir.children(entry.path).each { |name| restore_file(File.join(entry.path, name), File.join(slot_dir, name)) }
    end

    private

    def restore_file(source, dest)
      if File.directory?(source)
        FileUtils.rm_rf(dest)
        FileUtils.cp_r(source, dest)
      else
        tmp = File.join(File.dirname(dest), ".#{File.basename(dest)}.restore")
        FileUtils.cp(source, tmp)
        File.rename(tmp, dest)
      end
    end
  end
end
