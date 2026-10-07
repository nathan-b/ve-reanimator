require_relative 'test_helper'
require 'fake_game'
require 'logger'
require 'stringio'
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
    @log = StringIO.new
    @app = Reanimator::App.new(@saves, archive_dir: @archive, clock: clock,
                               logger: Logger.new(@log), retry_delay: 0.01)
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

  def death_names
    dir = File.join(@archive, 'death')
    Dir.exist?(dir) ? Dir.children(dir).sort : []
  end

  # Primary archives only: the death directory lives inside the archive root.
  def primary_names
    archive_names - ['death']
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

  def test_death_saves_go_to_the_death_directory_and_not_the_primary_one
    @game.trigger
    wait_until('normal save archived') { primary_names == [archive_name(1)] }
    @game.trigger(death: true)

    wait_until('death save archived') { death_names == [archive_name(2)] }
    assert_equal [archive_name(1)], primary_names
  end

  def test_saves_go_back_to_the_primary_directory_once_the_player_has_items_again
    @game.trigger
    wait_until('save 1') { primary_names == [archive_name(1)] }
    @game.trigger(death: true)
    wait_until('save 2') { death_names == [archive_name(2)] }
    @game.trigger

    wait_until('save 3') { primary_names == [archive_name(1), archive_name(3)] }
    assert_equal [archive_name(2)], death_names
  end

  def test_only_the_newest_death_save_is_kept
    @game.trigger(death: true)
    wait_until('death save 1') { death_names == [archive_name(1)] }
    @game.trigger(death: true)

    wait_until('death save 2 to replace death save 1') { death_names == [archive_name(2)] }
    assert_empty primary_names
  end

  def test_unreadable_world_data_is_skipped_with_a_warning_and_later_saves_still_work
    File.write(File.join(@saves, 'slot_0', 'world.data'), 'half a sav')

    wait_until('a warning to be logged') { @log.string.include?('world.data') }
    assert_empty archive_names

    @game.trigger
    wait_until('the next good save') { primary_names == [archive_name(1)] }
  end
end
