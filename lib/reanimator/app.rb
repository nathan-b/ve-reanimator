require 'reanimator/archiver'
require 'reanimator/watcher'

module Reanimator
  # Wires the save watcher to the archiver: every time the game writes a
  # world.data, the slot it belongs to is archived.
  class App
    DEFAULT_ARCHIVE_DIR = '/tmp/ve-reanimator'

    def initialize(saves_dir, archive_dir: DEFAULT_ARCHIVE_DIR, max_saves: 3, clock: -> { Time.now })
      archiver = Archiver.new(archive_dir: archive_dir, max_saves: max_saves, clock: clock)
      @watcher = Watcher.new(saves_dir) { |world_data| archiver.archive(world_data) }
    end

    def start
      @watcher.start
    end

    def stop
      @watcher.stop
    end
  end
end
