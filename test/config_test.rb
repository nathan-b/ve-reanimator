require_relative 'test_helper'
require 'fileutils'
require 'reanimator/config'

class ConfigTest < Minitest::Test
  Config = Reanimator::Config

  def setup
    @root = Dir.mktmpdir('ve-config')
    @home = File.join(@root, 'home')
    @base = File.join(@root, 'base')
    FileUtils.mkdir_p([@home, @base])
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def parse(yaml)
    Config.parse(yaml, base_dir: @base, home: @home)
  end

  def test_defaults
    c = parse('')

    assert_nil c.saves_dir
    assert_equal 3, c.max_saves
    assert_equal File.join(@home, '.cache', 've-reanimator'), c.archive_dir
    assert_equal File.join(@home, '.cache', 've-reanimator', 'death'), c.death_dir
    assert_equal 1, c.max_death_saves
  end

  def test_all_options_can_be_set
    c = parse(<<~YAML)
      saves_dir: /games/ve/Saves
      max_saves: 5
      archive_dir: /backups/ve
      death_dir: /backups/ve-death
      max_death_saves: 2
    YAML

    assert_equal '/games/ve/Saves', c.saves_dir
    assert_equal 5, c.max_saves
    assert_equal '/backups/ve', c.archive_dir
    assert_equal '/backups/ve-death', c.death_dir
    assert_equal 2, c.max_death_saves
  end

  def test_a_file_containing_only_comments_gives_the_defaults
    assert_equal 3, parse("# nothing to see here\n").max_saves
  end

  # --- paths ---

  def test_relative_archive_and_saves_dirs_are_relative_to_the_config_directory
    c = parse("archive_dir: backups\nsaves_dir: ../Saves\n")

    assert_equal File.join(@base, 'backups'), c.archive_dir
    assert_equal File.expand_path('../Saves', @base), c.saves_dir
  end

  def test_relative_death_dir_is_relative_to_the_archive_dir
    c = parse("archive_dir: /backups/ve\ndeath_dir: rip\n")

    assert_equal '/backups/ve/rip', c.death_dir
  end

  def test_default_death_dir_follows_a_configured_archive_dir
    assert_equal '/backups/ve/death', parse("archive_dir: /backups/ve\n").death_dir
  end

  def test_tilde_means_the_home_directory
    c = parse("archive_dir: ~/ve\nsaves_dir: ~/Saves\ndeath_dir: ~/dead\n")

    assert_equal File.join(@home, 've'), c.archive_dir
    assert_equal File.join(@home, 'Saves'), c.saves_dir
    assert_equal File.join(@home, 'dead'), c.death_dir
  end

  # --- validation ---

  def assert_invalid(yaml, message_pattern)
    e = assert_raises(Config::Error) { parse(yaml) }
    assert_match message_pattern, e.message
  end

  def test_save_counts_must_be_between_1_and_16
    assert_equal 1, parse("max_saves: 1\n").max_saves
    assert_equal 16, parse("max_saves: 16\n").max_saves
    assert_invalid("max_saves: 0\n", /max_saves.*1.*16/)
    assert_invalid("max_saves: 17\n", /max_saves.*1.*16/)
    assert_invalid("max_death_saves: 0\n", /max_death_saves.*1.*16/)
    assert_invalid("max_death_saves: 17\n", /max_death_saves.*1.*16/)
  end

  def test_save_counts_must_be_integers
    assert_invalid("max_saves: three\n", /max_saves.*integer/)
    assert_invalid("max_saves: 2.5\n", /max_saves.*integer/)
    assert_invalid("max_death_saves: '2'\n", /max_death_saves.*integer/)
  end

  def test_paths_must_be_non_empty_strings
    assert_invalid("archive_dir: ''\n", /archive_dir/)
    assert_invalid("saves_dir: 42\n", /saves_dir/)
    assert_invalid("death_dir: [a, b]\n", /death_dir/)
  end

  def test_unknown_options_are_rejected_so_typos_are_not_silently_ignored
    assert_invalid("max_save: 4\n", /unknown option.*max_save/)
  end

  def test_malformed_yaml_is_rejected
    assert_invalid("max_saves: [1, 2\n", /YAML/)
  end

  def test_a_file_that_is_not_a_mapping_is_rejected
    assert_invalid("- just\n- a list\n", /mapping|options/)
  end

  # --- finding the config file ---

  FILE = 've-reanimator.yaml'

  def user_config_dir
    File.join(@home, '.config', 've-reanimator')
  end

  def write_config(dir, text)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, FILE), text)
    File.join(dir, FILE)
  end

  def load_config
    Config.load(cwd: @base, home: @home)
  end

  def test_without_any_config_file_the_defaults_are_used
    c = load_config

    assert_nil c.source
    assert_equal 3, c.max_saves
  end

  def test_config_in_the_current_directory_is_used
    path = write_config(@base, "max_saves: 7\n")

    c = load_config
    assert_equal path, c.source
    assert_equal 7, c.max_saves
  end

  def test_config_in_the_user_config_directory_is_used
    path = write_config(user_config_dir, "max_saves: 9\n")

    c = load_config
    assert_equal path, c.source
    assert_equal 9, c.max_saves
  end

  def test_the_current_directory_wins_over_the_user_config_directory
    write_config(user_config_dir, "max_saves: 9\n")
    write_config(@base, "max_saves: 7\n")

    assert_equal 7, load_config.max_saves
  end

  def test_relative_paths_are_relative_to_the_directory_of_the_file_that_was_found
    write_config(user_config_dir, "archive_dir: backups\n")

    assert_equal File.join(user_config_dir, 'backups'), load_config.archive_dir
  end

  def test_errors_name_the_file_they_came_from
    path = write_config(@base, "max_saves: 99\n")

    e = assert_raises(Config::Error) { load_config }
    assert_includes e.message, path
  end
end
