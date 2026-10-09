require_relative 'test_helper'
require 'fake_game'
require 'reanimator/archive_store'
require 'reanimator/config'
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
    clock = ticking_clock
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

  def ticking_clock
    -> { START + 60 * (@ticks += 1) }
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

  # --- building an App from the configuration ---

  def build(config_yaml = '', saves_dir: nil, env: { 'HOME' => @root }, **options)
    config = Reanimator::Config.parse(config_yaml, base_dir: @root, home: @root)
    Reanimator::App.build(config, saves_dir: saves_dir, env: env, logger: Logger.new(@log), **options)
  end

  def test_build_prefers_the_command_line_saves_dir_over_the_config
    other = File.join(@root, 'other_saves')
    FileUtils.mkdir_p(other)
    app = build("saves_dir: #{@saves}\n", saves_dir: other)

    assert_equal other, app.saves_dir
  end

  def test_build_uses_the_saves_dir_from_the_config_even_if_another_could_be_discovered
    discoverable = File.join(@root, '.config', 'AtomicTorchStudio', 'VoidExpanse', 'Saves')
    FileUtils.mkdir_p(File.join(discoverable, 'slot_0'))
    FileUtils.touch(File.join(discoverable, 'slot_0', 'world.data'))

    assert_equal @saves, build("saves_dir: #{@saves}\n").saves_dir
  end

  def test_build_autodiscovers_the_saves_dir_when_none_is_configured
    found = File.join(@root, '.config', 'AtomicTorchStudio', 'VoidExpanse', 'Saves')
    FileUtils.mkdir_p(File.join(found, 'slot_0'))
    FileUtils.touch(File.join(found, 'slot_0', 'world.data'))

    assert_equal found, build.saves_dir
  end

  def test_build_fails_helpfully_when_no_saves_dir_can_be_found
    e = assert_raises(Reanimator::App::NoSavesDirectory) { build }
    assert_match(/saves_dir/, e.message)
  end

  def test_build_fails_when_the_saves_dir_does_not_exist
    missing = File.join(@root, 'nope')
    e = assert_raises(Reanimator::App::NoSavesDirectory) { build("saves_dir: #{missing}\n") }
    assert_includes e.message, missing
  end

  def test_build_passes_the_archive_settings_through
    saves = File.join(@root, 'configured_saves')
    archive = File.join(@root, 'configured_archive')
    FileUtils.mkdir_p(File.join(saves, 'slot_0'))
    # Different counts for normal and death saves, so swapped settings would show.
    app = build(<<~YAML, clock: ticking_clock, retry_delay: 0.01)
      saves_dir: #{saves}
      archive_dir: #{archive}
      max_saves: 2
      death_dir: rip
      max_death_saves: 3
    YAML
    app.start
    game = FakeGame.new(saves)
    names = ->(dir) { Dir.exist?(dir) ? Dir.children(dir).reject { |n| n == 'rip' }.sort : [] }

    (1..3).each { |n| game.trigger; wait_until("save #{n}") { names.(archive).include?(archive_name(n)) } }
    wait_until('normal saves pruned to 2') { names.(archive) == [archive_name(2), archive_name(3)] }

    (4..7).each { |n| game.trigger(death: true); wait_until("death save #{n}") { names.(File.join(archive, 'rip')).include?(archive_name(n)) } }
    wait_until('death saves pruned to 3') { names.(File.join(archive, 'rip')) == [archive_name(5), archive_name(6), archive_name(7)] }
    assert_equal [archive_name(2), archive_name(3)], names.(archive)
  ensure
    game&.stop
    app&.stop
  end

  # --- not archiving what is already archived ---

  def test_restoring_an_archive_does_not_create_a_new_archive
    (1..3).each { |n| @game.trigger; wait_until("archive #{n}") { archive_names.include?(archive_name(n)) } }
    store = Reanimator::ArchiveStore.new(archive_dir: @archive, death_dir: File.join(@archive, 'death'))
    sleep 1.1 # a restore made within moments of the last save is swallowed by the file watcher itself

    store.restore(store.entries(:good).last, @saves) # the oldest
    sleep 1.2 # long enough for the watcher to report it and the app to retry if it were going to

    assert_equal [archive_name(1), archive_name(2), archive_name(3)], archive_names
  end

  # --- watching state and manual backups ---

  def test_reports_whether_it_is_watching
    assert @app.watching?, 'the app from setup is started'
    @app.stop
    refute @app.watching?
  end

  def idle_app(saves)
    Reanimator::App.new(saves, archive_dir: File.join(@root, 'manual_archive'), clock: ticking_clock,
                               logger: Logger.new(@log), retry_delay: 0.01)
  end

  def write_slot(saves, slot, **doc)
    FileUtils.mkdir_p(File.join(saves, slot))
    SaveBuilder.write_world_data(File.join(saves, slot, 'world.data'), **doc)
  end

  def test_backup_now_archives_every_slot_and_sorts_death_saves_from_normal_ones
    saves = File.join(@root, 'manual_saves')
    write_slot(saves, 'slot_0', items: 3)
    write_slot(saves, 'slot_1', items: 0, cargo: 0)
    FileUtils.mkdir_p(File.join(saves, 'backup_slot_0')) # not a slot
    File.write(File.join(saves, 'backup_slot_0', 'world.data'), 'ignored')

    created = idle_app(saves).backup_now

    assert_equal 2, created.size
    assert_equal [File.join(@root, 'manual_archive', archive_name(1))], created.grep_v(/death/)
    assert_equal [File.join(@root, 'manual_archive', 'death', archive_name(2).sub('slot_0', 'slot_1'))], created.grep(/death/)
  end

  def test_backup_now_skips_saves_that_are_already_archived
    saves = File.join(@root, 'manual_saves')
    write_slot(saves, 'slot_0')
    write_slot(saves, 'slot_1', items: 0, cargo: 0) # a death save
    app = idle_app(saves)
    assert_equal 2, app.backup_now.size

    assert_empty app.backup_now
  end

  def test_backup_now_skips_unreadable_slots_but_still_backs_up_the_others
    saves = File.join(@root, 'manual_saves')
    FileUtils.mkdir_p(File.join(saves, 'slot_0'))
    File.write(File.join(saves, 'slot_0', 'world.data'), 'not a zip')
    write_slot(saves, 'slot_1')

    created = idle_app(saves).backup_now

    assert_equal 1, created.size
    assert_match(/slot_1/, created.first)
    assert_match(/slot_0/, @log.string)
  end
end
