require_relative 'test_helper'
require 'fake_game'
require 'reanimator/watcher'

class WatcherTest < Minitest::Test
  TIMEOUT = 5

  def setup
    @saves = Dir.mktmpdir('ve-saves')
    @events = Queue.new
    @watcher = Reanimator::Watcher.new(@saves) { |path| @events << path }
    @watcher.start
    @game = FakeGame.new(@saves)
  end

  def teardown
    @game.stop
    @watcher.stop
    FileUtils.remove_entry(@saves)
  end

  # Pop the next event, or nil if none arrives within +timeout+ seconds.
  def next_event(timeout = TIMEOUT)
    Timeout.timeout(timeout) { @events.pop }
  rescue Timeout::Error
    nil
  end

  def test_notifies_when_world_data_is_written
    @game.trigger(slot: 'slot_0')

    assert_equal File.join(@saves, 'slot_0', 'world.data'), next_event
  end

  def test_ignores_other_files_in_the_slot
    %w[save.data save_info.data screenshot.jpg].each { |f| @game.trigger(file: f) }
    @game.trigger(file: 'world.data')

    assert_equal File.join(@saves, 'slot_0', 'world.data'), next_event
    assert_nil next_event(0.5), 'only world.data should have produced an event'
  end

  def test_notifies_for_every_save_of_the_same_file
    3.times {
      @game.trigger
      assert_equal File.join(@saves, 'slot_0', 'world.data'), next_event
    }
  end

  def test_notifies_for_each_slot
    @game.trigger(slot: 'slot_0')
    @game.trigger(slot: 'slot_1')

    paths = [next_event, next_event]
    assert_equal %w[slot_0 slot_1], paths.map { |p| File.basename(File.dirname(p.to_s)) }.sort
  end

  def test_stops_notifying_after_stop
    @watcher.stop
    @game.trigger

    assert_nil next_event(0.5)
  end

  def test_ignores_world_data_in_directories_that_are_not_game_slots
    %w[backup_slot_0 slot_0_old slot notes].each { |dir| @game.trigger(slot: dir) }
    @game.trigger(slot: 'slot_12')

    assert_equal File.join(@saves, 'slot_12', 'world.data'), next_event
    assert_nil next_event(0.5), 'only slot_N directories should have produced an event'
  end
end
