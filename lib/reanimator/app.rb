require 'logger'
require 'reanimator/archiver'
require 'reanimator/death_detector'
require 'reanimator/watcher'

module Reanimator
  # Wires the pieces together: every time the game writes a world.data, its slot
  # is archived, into the primary archive normally or into the death archive if
  # the save was made after the player died.
  class App
    DEFAULT_ARCHIVE_DIR = '/tmp/ve-reanimator'

    # +attempts+ and +retry_delay+ control how a save that cannot be read yet is
    # retried: the game may still be writing it when we are notified.
    def initialize(saves_dir, archive_dir: DEFAULT_ARCHIVE_DIR, death_dir: File.join(archive_dir, 'death'),
                   max_saves: 3, max_death_saves: 1, clock: -> { Time.now },
                   logger: Logger.new($stderr), attempts: 3, retry_delay: 0.5)
      @primary = Archiver.new(archive_dir: archive_dir, max_saves: max_saves, clock: clock)
      @death = Archiver.new(archive_dir: death_dir, max_saves: max_death_saves, clock: clock)
      @logger = logger
      @attempts = attempts
      @retry_delay = retry_delay
      @watcher = Watcher.new(saves_dir) { |world_data| handle_save(world_data) }
    end

    def start
      @watcher.start
    end

    def stop
      @watcher.stop
    end

    private

    def handle_save(world_data)
      death = death_save?(world_data)
      return if death.nil?

      (death ? @death : @primary).archive(world_data)
    end

    # true/false, or nil if the save is still unreadable after all attempts.
    # Unreadable saves are not archived: they are no use as a restore point.
    def death_save?(world_data)
      tries = 0
      begin
        tries += 1
        DeathDetector.death_save?(world_data)
      rescue DeathDetector::UnreadableSave => e
        if tries < @attempts
          sleep @retry_delay
          retry
        end
        @logger.warn("Skipping #{world_data}: #{e.message}")
        nil
      end
    end
  end
end
