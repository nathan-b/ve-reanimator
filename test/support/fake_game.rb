require 'zip'
require 'fileutils'

# Stands in for VoidExpanse in tests. A background thread waits for messages
# and, on request, writes a save file into a slot directory the way the game
# would: a zip archive containing a single `data` entry.
class FakeGame
  def initialize(saves_dir)
    @saves_dir = saves_dir
    @queue = Queue.new
    @counter = 0
    @thread = Thread.new { run }
  end

  # Ask the game thread to save the given file in the given slot.
  def trigger(slot: 'slot_0', file: 'world.data')
    @queue << [:save, slot, file]
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
      _, slot, file = msg
      write_save(slot, file)
    end
  end

  def write_save(slot, file)
    dir = File.join(@saves_dir, slot)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, file)
    @counter += 1
    if file == 'world.data'
      Zip::OutputStream.open(path) { |z|
        z.put_next_entry('data')
        z.write(%({"save_number":#{@counter}}))
      }
    else
      File.write(path, "save #{@counter}")
    end
  end
end
