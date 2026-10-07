require_relative 'test_helper'
require 'fake_game'
require 'reanimator/app'

# End-to-end: the fake game saves, the watcher notices, the archiver copies.
class AppTest < Minitest::Test
  TIMEOUT = 5
  START = Time.local(2026, 10, 6, 18, 0, 0)

  def setup
    @root = Dir.mktmpdir('ve-app')
    @saves = File.join(@root, 'saves')
    @archive = File.join(@root, 'archive')
    FileUtils.mkdir_p(File.join(@saves, 'slot_0')) # slots exist before the first save we watch
    # Each archive gets a timestamp one minute after the previous one.
    @ticks = 0
    clock = -> { START + 60 * (@ticks += 1) }
    @app = Reanimator::App.new(@saves, archive_dir: @archive, clock: clock)
    @app.start
    @game = FakeGame.new(@saves)
  end

  def teardown
    @game.stop
    @app.stop
    FileUtils.remove_entry(@root)
  end

  def archive_names
    Dir.exist?(@archive) ? Dir.children(@archive).sort : []
  end

  # Name of the archive made by the +n+th save (the clock ticks once a minute from START).
  def archive_name(n)
    "slot_0_#{(START + 60 * n).strftime('%Y%m%d_%H%M%S')}"
  end

  # Poll until the block is truthy; fail the test if it never is.
  def wait_until(what)
    deadline = Time.now + TIMEOUT
    sleep 0.02 until yield || Time.now > deadline
    assert yield, "timed out waiting for #{what}; archive has #{archive_names.inspect}"
  end

  def test_each_save_copies_the_whole_slot_into_the_archive
    @game.trigger(file: 'save.data').trigger(file: 'world.data')

    wait_until('first archive') { archive_names == [archive_name(1)] }
    assert_equal %w[save.data world.data], Dir.children(File.join(@archive, archive_name(1))).sort
  end

  def test_oldest_archive_is_removed_after_more_than_three_saves
    (1..4).each { |n|
      @game.trigger
      wait_until("archive ##{n}") { archive_names.include?(archive_name(n)) }
    }
    @game.trigger

    # Rotation happens right after the fifth archive appears.
    wait_until('oldest archives to be removed') {
      archive_names == [archive_name(3), archive_name(4), archive_name(5)]
    }
  end
end
