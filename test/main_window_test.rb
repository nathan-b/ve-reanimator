require_relative 'test_helper'
require 'fileutils'
require 'logger'
require 'stringio'
require 'save_builder'
require 'reanimator/app'
require 'reanimator/archive_store'

# The window is built but never shown, so these tests need a display to exist
# (GTK refuses to start without one) but nothing appears on it.
GUI_ERROR =
  begin
    require 'gtk3'
    nil
  rescue LoadError, StandardError => e
    e
  end
# Only the display may be missing; a broken window class must fail loudly.
unless GUI_ERROR
  require 'reanimator/gui/main_window'
  require 'reanimator/gui'
end

class MainWindowTest < Minitest::Test
  # Answers the window's questions instead of showing dialogs.
  class FakeDialogs
    attr_accessor :answer
    attr_reader :questions, :errors

    def initialize
      @answer = true
      @questions = []
      @errors = []
    end

    def confirm(_window, text)
      @questions << text
      @answer
    end

    def error(_window, text)
      @errors << text
    end
  end

  def setup
    skip "no usable GTK display: #{GUI_ERROR.message}" if GUI_ERROR
    @root = Dir.mktmpdir('ve-gui')
    @saves = File.join(@root, 'Saves')
    @archive = File.join(@root, 'archive')
    @death = File.join(@archive, 'death')
    FileUtils.mkdir_p([@saves, @archive, @death])
    @store = Reanimator::ArchiveStore.new(archive_dir: @archive, death_dir: @death)
    @dialogs = FakeDialogs.new
    @windows = []
  end

  def teardown
    @windows&.each(&:destroy)
    FileUtils.remove_entry(@root) if @root
  end

  def make_archive(dir, name, content = name)
    path = File.join(dir, name)
    FileUtils.mkdir_p(path)
    %w[save.data save_info.data screenshot.jpg world.data].each { |f| File.write(File.join(path, f), "#{f}:#{content}") }
    path
  end

  def window(app: nil, saves_dir: @saves)
    w = Reanimator::GUI::MainWindow.new(store: @store, app: app, saves_dir: saves_dir, dialogs: @dialogs)
    @windows << w
    w
  end

  def idle_app
    Reanimator::App.new(@saves, archive_dir: @archive, death_dir: @death, logger: Logger.new(StringIO.new), retry_delay: 0.01)
  end

  def write_slot(slot, **doc)
    FileUtils.mkdir_p(File.join(@saves, slot))
    SaveBuilder.write_world_data(File.join(@saves, slot, 'world.data'), **doc)
  end

  # --- layout and listing ---

  def test_has_a_good_saves_tab_and_a_death_saves_tab
    assert_equal ['Good saves', 'Death saves'], window.tab_labels
  end

  def test_each_tab_lists_its_saves_newest_first
    make_archive(@archive, 'slot_0_20261006_180000')
    make_archive(@archive, 'slot_0_20261006_190000')
    make_archive(@death, 'slot_0_20261006_181500')

    w = window

    assert_equal ['slot_0  2026-10-06 19:00:00', 'slot_0  2026-10-06 18:00:00'], w.row_texts(:good)
    assert_equal ['slot_0  2026-10-06 18:15:00'], w.row_texts(:death)
  end

  def test_refresh_picks_up_new_and_removed_archives
    w = window
    assert_empty w.row_texts(:good)

    make_archive(@archive, 'slot_1_20261007_100000')
    w.refresh
    assert_equal ['slot_1  2026-10-07 10:00:00'], w.row_texts(:good)

    FileUtils.rm_rf(File.join(@archive, 'slot_1_20261007_100000'))
    w.refresh
    assert_empty w.row_texts(:good)
  end

  def test_refresh_keeps_the_selection
    make_archive(@archive, 'slot_0_20261006_180000')
    make_archive(@archive, 'slot_0_20261006_190000')
    w = window
    w.select(:good, 1)

    make_archive(@archive, 'slot_0_20261006_200000')
    w.refresh

    assert_equal 'slot_0  2026-10-06 18:00:00', w.selected_text
  end

  # --- buttons ---

  def test_button_labels
    w = window
    assert_equal ['Restore selected save', 'Delete selected save', 'Manual backup'],
                 [w.restore_button, w.delete_button, w.backup_button].map(&:label)
  end

  def test_restore_and_delete_need_a_selection
    make_archive(@archive, 'slot_0_20261006_180000')
    w = window(app: idle_app)
    refute w.restore_button.sensitive?
    refute w.delete_button.sensitive?

    w.select(:good, 0)

    assert w.restore_button.sensitive?
    assert w.delete_button.sensitive?
  end

  def test_restore_copies_the_selected_save_into_its_slot_after_confirming
    make_archive(@archive, 'slot_0_20261006_180000', 'old')
    FileUtils.mkdir_p(File.join(@saves, 'slot_0'))
    File.write(File.join(@saves, 'slot_0', 'world.data'), 'current')
    w = window(app: idle_app)
    w.select(:good, 0)

    w.restore_button.clicked

    assert_equal 'world.data:old', File.read(File.join(@saves, 'slot_0', 'world.data'))
    assert_match(/slot_0/, @dialogs.questions.first)
    assert_match(/overwrit/i, @dialogs.questions.first)
  end

  def test_restore_does_nothing_if_the_user_declines
    make_archive(@archive, 'slot_0_20261006_180000', 'old')
    FileUtils.mkdir_p(File.join(@saves, 'slot_0'))
    File.write(File.join(@saves, 'slot_0', 'world.data'), 'current')
    @dialogs.answer = false
    w = window(app: idle_app)
    w.select(:good, 0)

    w.restore_button.clicked

    assert_equal 'current', File.read(File.join(@saves, 'slot_0', 'world.data'))
  end

  def test_restore_works_from_the_death_tab
    make_archive(@death, 'slot_0_20261006_180000', 'dead')
    w = window(app: idle_app)
    w.select(:death, 0)

    w.restore_button.clicked

    assert_equal 'world.data:dead', File.read(File.join(@saves, 'slot_0', 'world.data'))
  end

  def test_delete_removes_the_selected_save_after_confirming
    make_archive(@archive, 'slot_0_20261006_180000')
    make_archive(@archive, 'slot_0_20261006_190000')
    w = window
    w.select(:good, 0)

    w.delete_button.clicked

    assert_equal ['slot_0  2026-10-06 18:00:00'], w.row_texts(:good)
    assert_equal %w[slot_0_20261006_180000], Dir.children(@archive).grep(/slot_/)
    assert_match(/delete/i, @dialogs.questions.first)
  end

  def test_delete_does_nothing_if_the_user_declines
    make_archive(@archive, 'slot_0_20261006_180000')
    @dialogs.answer = false
    w = window
    w.select(:good, 0)

    w.delete_button.clicked

    assert_equal ['slot_0  2026-10-06 18:00:00'], w.row_texts(:good)
  end

  def test_manual_backup_archives_the_current_saves_and_shows_them
    write_slot('slot_0')
    w = window(app: idle_app)

    w.backup_button.clicked

    assert_equal 1, w.row_texts(:good).size
    assert_match(/slot_0/, w.row_texts(:good).first)
  end

  def test_manual_backup_of_a_death_save_shows_in_the_death_tab
    write_slot('slot_0', items: 0, cargo: 0)
    w = window(app: idle_app)

    w.backup_button.clicked

    assert_empty w.row_texts(:good)
    assert_equal 1, w.row_texts(:death).size
  end

  def test_actions_that_touch_the_game_saves_are_unavailable_without_a_saves_directory
    make_archive(@archive, 'slot_0_20261006_180000')
    w = window(app: nil, saves_dir: nil)
    w.select(:good, 0)

    refute w.restore_button.sensitive?
    refute w.backup_button.sensitive?
    assert w.delete_button.sensitive?, 'archives can still be deleted'
  end

  def test_a_failed_restore_is_reported_and_leaves_the_window_working
    path = make_archive(@archive, 'slot_0_20261006_180000')
    w = window(app: idle_app)
    w.select(:good, 0)
    FileUtils.rm_rf(path) # vanishes behind the window's back

    w.restore_button.clicked

    assert_equal 1, @dialogs.errors.size
    assert_match(/no longer exists/, @dialogs.errors.first)
  end

  # --- status bar ---

  def test_status_bar_says_what_is_being_watched
    app = idle_app
    app.start
    w = window(app: app)

    assert_equal "Watching #{@saves}", w.status_text
  ensure
    app&.stop
  end

  def test_status_bar_says_when_nothing_is_being_watched
    assert_match(/Not watching/, window(app: nil, saves_dir: nil).status_text)
  end

  def test_status_bar_notices_when_watching_stops
    app = idle_app
    app.start
    w = window(app: app)
    app.stop

    w.refresh

    assert_match(/Not watching/, w.status_text)
  end
end

# Building the window and app together from a Config, as the program does at startup.
class GuiBuildTest < Minitest::Test
  def setup
    skip "no usable GTK display: #{GUI_ERROR.message}" if GUI_ERROR
    @root = Dir.mktmpdir('ve-guibuild')
    @saves = File.join(@root, 'Saves')
    FileUtils.mkdir_p(File.join(@saves, 'slot_0'))
    @built = []
  end

  def teardown
    @built&.each { |window, app| app&.stop; window.destroy }
    FileUtils.remove_entry(@root) if @root
  end

  def build(yaml, **opts)
    config = Reanimator::Config.parse(yaml, base_dir: @root, home: @root)
    @built << Reanimator::GUI.build(config, env: { 'HOME' => @root }, **opts)
    @built.last
  end

  def test_builds_a_window_for_a_running_app_watching_the_configured_saves_dir
    window, app = build("saves_dir: #{@saves}\narchive_dir: #{@root}/archive\n")

    assert app.watching?
    assert_equal "Watching #{@saves}", window.status_text
  end

  def test_the_command_line_saves_dir_takes_precedence
    other = File.join(@root, 'Other')
    FileUtils.mkdir_p(other)

    window, = build("saves_dir: #{@saves}\narchive_dir: #{@root}/archive\n", saves_dir: other)

    assert_equal "Watching #{other}", window.status_text
  end

  def test_still_opens_when_there_is_no_saves_directory_and_says_why
    window, app = build("archive_dir: #{@root}/archive\n")

    assert_nil app
    assert_match(/Not watching: .*saves_dir/, window.status_text)
  end

  def test_still_lists_existing_archives_when_there_is_no_saves_directory
    FileUtils.mkdir_p(File.join(@root, 'archive', 'slot_0_20261006_180000'))

    window, = build("archive_dir: #{@root}/archive\n")

    assert_equal ['slot_0  2026-10-06 18:00:00'], window.row_texts(:good)
  end
end
