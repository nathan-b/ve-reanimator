require 'fileutils'
require 'save_builder'

# Stands in for VoidExpanse in tests. A background thread waits for messages
# and, on request, writes a save file into a slot directory the way the game
# would. world.data is a realistic save (see SaveBuilder); +death+ makes it one
# with an empty inventory and cargo hold, as after the player dies.
class FakeGame
  def initialize(saves_dir)
    @saves_dir = saves_dir
    @queue = Queue.new
    @counter = 0
    @thread = Thread.new { run }
  end

  # Ask the game thread to save the given file in the given slot.
  def trigger(slot: 'slot_0', file: 'world.data', death: false)
    @queue << [:save, slot, file, death]
    self
  end

  # Stop the game thread, waiting for any queued saves to finish.
  def stop
    @queue << :stop
    @thread.join
  end

  private

  def run
    while (msg = @queue.pop) != :stop
      _, slot, file, death = msg
      write_save(slot, file, death)
    end
  end

  def write_save(slot, file, death)
    dir = File.join(@saves_dir, slot)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, file)
    @counter += 1
    if file == 'world.data'
      items = death ? 0 : 3
      SaveBuilder.write_world_data(path, items: items, cargo: 0, save_number: @counter)
    else
      File.write(path, "save #{@counter}")
    end
  end
end
