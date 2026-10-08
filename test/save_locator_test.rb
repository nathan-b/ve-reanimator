require_relative 'test_helper'
require 'fileutils'
require 'reanimator/save_locator'

class SaveLocatorTest < Minitest::Test
  APP_ID = '324260' # VoidExpanse on Steam
  GAME_PATH = File.join('AtomicTorchStudio', 'VoidExpanse', 'Saves')

  def setup
    @home = Dir.mktmpdir('ve-home')
  end

  def teardown
    FileUtils.remove_entry(@home)
  end

  def locate(env = {})
    Reanimator::SaveLocator.locate({ 'HOME' => @home }.merge(env))
  end

  # Where Steam puts the Proton prefix of the game, under a given Steam root.
  def proton_saves(steam_root)
    File.join(@home, steam_root, 'steamapps', 'compatdata', APP_ID, 'pfx', 'drive_c', 'users', 'steamuser', 'Documents', GAME_PATH)
  end

  # Create a Saves directory containing +slots+ slot directories, each with a world.data.
  def make_saves(dir, slots: %w[slot_0], mtime: Time.now)
    FileUtils.mkdir_p(dir)
    slots.each { |slot|
      FileUtils.mkdir_p(File.join(dir, slot))
      world_data = File.join(dir, slot, 'world.data')
      File.write(world_data, 'x')
      File.utime(mtime, mtime, world_data)
    }
    dir
  end

  def test_finds_saves_in_the_proton_prefix_of_a_native_steam_install
    dir = make_saves(proton_saves('.local/share/Steam'))

    assert_equal dir, locate
  end

  def test_finds_saves_in_the_other_standard_steam_locations
    dir = make_saves(proton_saves('.steam/steam'))

    assert_equal dir, locate
  end

  def test_finds_saves_in_a_flatpak_steam_install
    dir = make_saves(proton_saves('.var/app/com.valvesoftware.Steam/.local/share/Steam'))

    assert_equal dir, locate
  end

  def test_finds_saves_of_a_native_linux_build
    dir = make_saves(File.join(@home, '.config', GAME_PATH))

    assert_equal dir, locate
  end

  def test_finds_saves_on_windows
    profile = File.join(@home, 'winuser')
    dir = make_saves(File.join(profile, 'Documents', GAME_PATH))

    assert_equal dir, locate('USERPROFILE' => profile)
  end

  def test_returns_nil_when_there_are_no_saves_anywhere
    assert_nil locate
  end

  def test_returns_nil_without_a_home_directory
    assert_nil Reanimator::SaveLocator.locate({})
  end

  def test_a_candidate_with_no_slots_does_not_count
    # This is the real situation on a Flatpak Steam + Proton machine: the native-style
    # directory exists but only holds Steam's autocloud file.
    native = File.join(@home, '.var/app/com.valvesoftware.Steam/.config', GAME_PATH)
    FileUtils.mkdir_p(native)
    File.write(File.join(native, 'steam_autocloud.vdf'), '')
    proton = make_saves(proton_saves('.var/app/com.valvesoftware.Steam/.local/share/Steam'))

    assert_equal proton, locate
  end

  def test_a_slot_directory_without_world_data_does_not_count
    dir = File.join(@home, '.config', GAME_PATH)
    FileUtils.mkdir_p(File.join(dir, 'slot_0'))

    assert_nil locate
  end

  def test_the_candidate_with_the_most_recent_save_wins
    older = make_saves(File.join(@home, '.config', GAME_PATH), mtime: Time.now - 3600)
    newer = make_saves(proton_saves('.local/share/Steam'), mtime: Time.now - 60)

    assert_equal newer, locate
    FileUtils.touch(File.join(older, 'slot_0', 'world.data'))
    assert_equal older, locate
  end

  def test_recency_is_judged_by_the_newest_slot
    mixed = make_saves(proton_saves('.steam/steam'), slots: %w[slot_0 slot_1], mtime: Time.now - 7200)
    FileUtils.touch(File.join(mixed, 'slot_1', 'world.data'))
    other = make_saves(File.join(@home, '.config', GAME_PATH), mtime: Time.now - 600)

    assert_equal mixed, locate
    refute_equal other, locate
  end

  def test_paths_containing_glob_characters_are_matched_literally
    weird_home = File.join(@home, 'we[ir]d*ho?me')
    dir = make_saves(File.join(weird_home, '.config', GAME_PATH))

    assert_equal dir, Reanimator::SaveLocator.locate({ 'HOME' => weird_home })
  end

  def test_directories_that_are_not_game_slots_do_not_count
    make_saves(File.join(@home, '.config', GAME_PATH), slots: %w[backup_slot_0 slot_0_old notes])

    assert_nil locate
  end
end
