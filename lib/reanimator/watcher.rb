require 'listen'

module Reanimator
  # Watches a VoidExpanse saves directory and calls the block with the path of
  # a slot's world.data whenever the game writes it.
  class Watcher
    def initialize(saves_dir, &on_save)
      @listener = Listen.to(saves_dir, only: /(\A|\/)world\.data\z/) { |modified, added, _removed|
        (modified + added).each(&on_save)
      }
    end

    def start
      @listener.start
    end

    def stop
      @listener.stop
    end
  end
end
