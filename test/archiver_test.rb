require_relative 'test_helper'
require 'fileutils'
require 'reanimator/archiver'

class ArchiverTest < Minitest::Test
  SLOT_FIXTURE = File.expand_path('slot_0', __dir__)
  SAVE_FILES = %w[save.data save_info.data screenshot.jpg world.data].freeze

  def setup
    @root = Dir.mktmpdir('ve-archiver')
    @saves = File.join(@root, 'saves')
    @archive = File.join(@root, 'archive') # deliberately not created
    @now = Time.local(2026, 10, 6, 18, 6, 29)
    FileUtils.mkdir_p(@saves)
    FileUtils.cp_r(SLOT_FIXTURE, @saves)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def archiver(**opts)
    Reanimator::Archiver.new(archive_dir: @archive, clock: -> { @now }, **opts)
  end

  def world_data(slot = 'slot_0')
    File.join(@saves, slot, 'world.data')
  end

  def test_copies_the_whole_slot_into_a_timestamped_directory
    dest = archiver.archive(world_data)

    assert_equal File.join(@archive, 'slot_0_20261006_180629'), dest
    SAVE_FILES.each { |f|
      assert_equal File.binread(File.join(SLOT_FIXTURE, f)), File.binread(File.join(dest, f)), f
    }
  end

  # Archive +world_data+ once per minute for +times+ minutes, using a clock that advances.
  def archive_repeatedly(arch, times, path = world_data)
    times.times { arch.archive(path); @now += 60 }
  end

  def archive_names
    Dir.children(@archive).sort
  end

  def test_keeps_only_the_newest_three_by_default
    archive_repeatedly(archiver, 5)

    assert_equal %w[slot_0_20261006_180829 slot_0_20261006_180929 slot_0_20261006_181029], archive_names
  end

  def test_max_saves_is_configurable
    archive_repeatedly(archiver(max_saves: 2), 4)

    assert_equal %w[slot_0_20261006_180829 slot_0_20261006_180929], archive_names
  end

  def test_rotation_is_per_slot
    FileUtils.cp_r(SLOT_FIXTURE, File.join(@saves, 'slot_1'))
    archive_repeatedly(archiver(max_saves: 1), 1, world_data('slot_0'))
    archive_repeatedly(archiver(max_saves: 1), 2, world_data('slot_1'))

    assert_equal %w[slot_0_20261006_180629 slot_1_20261006_180829], archive_names
  end

  def test_rotation_leaves_unrelated_entries_alone
    FileUtils.mkdir_p(File.join(@archive, 'death'))
    FileUtils.mkdir_p(File.join(@archive, 'slot_0_notes'))
    File.write(File.join(@archive, 'readme.txt'), 'hi')
    archive_repeatedly(archiver(max_saves: 1), 3)

    assert_equal %w[death readme.txt slot_0_20261006_180829 slot_0_notes], archive_names
  end

  def test_two_saves_in_the_same_second_leave_one_archive_with_the_latest_contents
    arch = archiver
    arch.archive(world_data)
    File.write(File.join(@saves, 'slot_0', 'save.data'), 'newer')
    arch.archive(world_data)

    assert_equal %w[slot_0_20261006_180629], archive_names
    assert_equal 'newer', File.read(File.join(@archive, 'slot_0_20261006_180629', 'save.data'))
  end

  def test_archive_is_not_visible_under_its_final_name_until_the_copy_is_complete
    seen_during_copy = nil
    real_cp_r = FileUtils.method(:cp_r)
    probe = ->(*args, **opts) {
      seen_during_copy = Dir.children(@archive)
      real_cp_r.call(*args, **opts)
    }

    FileUtils.stub(:cp_r, probe) { archiver.archive(world_data) }

    assert_empty seen_during_copy.grep(/\Aslot_0_\d{8}_\d{6}\z/)
    assert_equal %w[slot_0_20261006_180629], archive_names, 'no temporary directories should be left behind'
  end

  # --- recognising saves that are already archived ---

  def test_holds_a_save_after_archiving_it
    arch = archiver
    refute arch.holds?(world_data)

    arch.archive(world_data)

    assert arch.holds?(world_data)
  end

  def test_does_not_hold_a_save_whose_world_data_has_changed
    arch = archiver
    arch.archive(world_data)
    File.binwrite(world_data, File.binread(world_data) + 'x')

    refute arch.holds?(world_data)
  end

  def test_holds_a_save_if_any_archive_of_the_slot_matches
    arch = archiver
    arch.archive(world_data)
    original = File.binread(world_data)
    @now += 60
    File.binwrite(world_data, 'a newer save')
    arch.archive(world_data)
    File.binwrite(world_data, original)

    assert arch.holds?(world_data), 'restoring an older archive must be recognised'
  end

  def test_archives_of_other_slots_do_not_count
    FileUtils.cp_r(SLOT_FIXTURE, File.join(@saves, 'slot_1'))
    arch = archiver
    arch.archive(world_data('slot_0'))

    refute arch.holds?(world_data('slot_1'))
  end
end
