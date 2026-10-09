require 'logger'
require 'reanimator/archiver'
require 'reanimator/config'
require 'reanimator/death_detector'
require 'reanimator/save_locator'
require 'reanimator/slot'
require 'reanimator/watcher'

module Reanimator
  # Wires the pieces together: every time the game writes a world.data, its slot
  # is archived, into the primary archive normally or into the death archive if
  # the save was made after the player died.
  class App
    # No usable game save directory could be determined.
    class NoSavesDirectory < StandardError; end

    attr_reader :saves_dir

    # Build an App from a Config. The saves directory is +saves_dir+ if given
    # (e.g. from the command line), else the configured one, else the one found
    # by SaveLocator. Other options (clock:, logger:, ...) go to App.new.
    def self.build(config, saves_dir: nil, env: ENV, **options)
      dir = saves_dir || config.saves_dir || SaveLocator.locate(env)
      raise NoSavesDirectory, 'could not find the VoidExpanse Saves directory; set saves_dir in ve-reanimator.yaml' unless dir
      raise NoSavesDirectory, "not a directory: #{dir}" unless File.directory?(dir)

      new(dir, archive_dir: config.archive_dir, death_dir: config.death_dir,
               max_saves: config.max_saves, max_death_saves: config.max_death_saves, **options)
    end

    # +attempts+ and +retry_delay+ control how a save that cannot be read yet is
    # retried: the game may still be writing it when we are notified.
    def initialize(saves_dir, archive_dir:, death_dir: File.join(archive_dir, 'death'),
                   max_saves: 3, max_death_saves: 1, clock: -> { Time.now },
                   logger: Logger.new($stderr), attempts: 3, retry_delay: 0.5)
      @saves_dir = saves_dir
      @primary = Archiver.new(archive_dir: archive_dir, max_saves: max_saves, clock: clock)
      @death = Archiver.new(archive_dir: death_dir, max_saves: max_death_saves, clock: clock)
      @logger = logger
      @attempts = attempts
      @retry_delay = retry_delay
      @watcher = Watcher.new(saves_dir) { |world_data| handle_save(world_data) }
    end

    def start
      @watcher.start
      @watching = true
    end

    def stop
      @watcher.stop
      @watching = false
    end

    def watching?
      @watching == true
    end

    # Archive every slot as it is now, as if the game had just saved it. Returns
    # the paths of the archives made; slots that are unreadable or already
    # archived are skipped.
    def backup_now
      slots = Dir.children(@saves_dir).select { |name| Slot.name?(name) }.sort
      slots.map { |slot| File.join(@saves_dir, slot, 'world.data') }
           .select { |world_data| File.file?(world_data) }
           .filter_map { |world_data| handle_save(world_data) }
    end

    private

    # Archive the slot of +world_data+ unless it is unreadable or already
    # archived (which also keeps a restored save from being archived again).
    # Returns the new archive's path, or nil if nothing was archived.
    def handle_save(world_data)
      return nil if @primary.holds?(world_data) || @death.holds?(world_data)

      death = death_save?(world_data)
      return nil if death.nil?

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
