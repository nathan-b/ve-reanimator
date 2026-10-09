require_relative 'test_helper'
require 'fileutils'
require 'reanimator/archive_store'

class ArchiveStoreTest < Minitest::Test
  SAVE_FILES = %w[save.data save_info.data screenshot.jpg world.data].freeze

  def setup
    @root = Dir.mktmpdir('ve-store')
    @archive = File.join(@root, 'archive')
    @death = File.join(@archive, 'death')
    @saves = File.join(@root, 'Saves')
    FileUtils.mkdir_p([@archive, @death, @saves])
    @store = Reanimator::ArchiveStore.new(archive_dir: @archive, death_dir: @death)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # Make an archive directory holding the standard save files, each containing +content+.
  def make_archive(dir, name, content = name)
    path = File.join(dir, name)
    FileUtils.mkdir_p(path)
    SAVE_FILES.each { |f| File.write(File.join(path, f), "#{f}:#{content}") }
    path
  end

  # --- listing ---

  def test_lists_normal_saves_newest_first
    make_archive(@archive, 'slot_0_20261006_180000')
    make_archive(@archive, 'slot_1_20261007_090000')
    make_archive(@archive, 'slot_0_20261006_190000')

    entries = @store.entries(:good)

    assert_equal %w[slot_1_20261007_090000 slot_0_20261006_190000 slot_0_20261006_180000], entries.map { |e| File.basename(e.path) }
  end

  def test_entries_know_their_slot_time_and_kind
    make_archive(@archive, 'slot_3_20261006_180629')

    e = @store.entries(:good).first

    assert_equal 'slot_3', e.slot
    assert_equal Time.local(2026, 10, 6, 18, 6, 29), e.time
    assert_equal :good, e.kind
    assert_equal File.join(@archive, 'slot_3_20261006_180629'), e.path
  end

  def test_lists_death_saves_from_the_death_directory
    make_archive(@archive, 'slot_0_20261006_180000')
    make_archive(@death, 'slot_0_20261006_181000')

    assert_equal %w[slot_0_20261006_181000], @store.entries(:death).map { |e| File.basename(e.path) }
    assert_equal %i[death], @store.entries(:death).map(&:kind)
  end

  def test_normal_listing_ignores_the_death_directory_and_other_clutter
    make_archive(@archive, 'slot_0_20261006_180000')
    FileUtils.mkdir_p(File.join(@archive, '.slot_0_20261006_190000.tmp'))
    FileUtils.mkdir_p(File.join(@archive, 'slot_0_notes'))
    File.write(File.join(@archive, 'readme.txt'), 'hi')

    assert_equal %w[slot_0_20261006_180000], @store.entries(:good).map { |e| File.basename(e.path) }
  end

  def test_missing_directories_list_as_empty
    store = Reanimator::ArchiveStore.new(archive_dir: File.join(@root, 'nope'), death_dir: File.join(@root, 'nope', 'death'))

    assert_empty store.entries(:good)
    assert_empty store.entries(:death)
  end

  # --- deleting ---

  def test_delete_removes_the_archive
    make_archive(@archive, 'slot_0_20261006_180000')
    make_archive(@archive, 'slot_0_20261006_190000')

    @store.delete(@store.entries(:good).last)

    assert_equal %w[slot_0_20261006_190000], @store.entries(:good).map { |e| File.basename(e.path) }
  end

  def test_deleting_an_archive_that_is_already_gone_is_not_an_error
    make_archive(@archive, 'slot_0_20261006_180000')
    entry = @store.entries(:good).first
    @store.delete(entry)

    @store.delete(entry)
  end

  # --- restoring ---

  def test_restore_copies_the_archived_files_into_the_slot
    make_archive(@archive, 'slot_0_20261006_180000', 'old')
    FileUtils.mkdir_p(File.join(@saves, 'slot_0'))
    SAVE_FILES.each { |f| File.write(File.join(@saves, 'slot_0', f), 'current') }

    @store.restore(@store.entries(:good).first, @saves)

    SAVE_FILES.each { |f| assert_equal "#{f}:old", File.read(File.join(@saves, 'slot_0', f)), f }
  end

  def test_restore_keeps_the_slot_directory_itself_and_leaves_other_files_alone
    make_archive(@archive, 'slot_0_20261006_180000')
    slot = File.join(@saves, 'slot_0')
    FileUtils.mkdir_p(slot)
    File.write(File.join(slot, 'world.data.bak'), 'mine')
    inode = File.stat(slot).ino

    @store.restore(@store.entries(:good).first, @saves)

    assert_equal inode, File.stat(slot).ino, 'the game and the watcher expect the same directory'
    assert_equal 'mine', File.read(File.join(slot, 'world.data.bak'))
    assert_equal (SAVE_FILES + ['world.data.bak']).sort, Dir.children(slot).sort, 'no temporary files left behind'
  end

  def test_restore_creates_the_slot_directory_if_it_is_missing
    make_archive(@archive, 'slot_2_20261006_180000', 'old')

    @store.restore(@store.entries(:good).first, @saves)

    assert_equal 'world.data:old', File.read(File.join(@saves, 'slot_2', 'world.data'))
  end

  def test_restoring_a_death_save_works_too
    make_archive(@death, 'slot_0_20261006_180000', 'dead')

    @store.restore(@store.entries(:death).first, @saves)

    assert_equal 'world.data:dead', File.read(File.join(@saves, 'slot_0', 'world.data'))
  end

  def test_restore_of_an_archive_that_has_vanished_raises_without_touching_the_slot
    make_archive(@archive, 'slot_0_20261006_180000')
    slot = File.join(@saves, 'slot_0')
    FileUtils.mkdir_p(slot)
    File.write(File.join(slot, 'world.data'), 'current')
    entry = @store.entries(:good).first
    @store.delete(entry)

    assert_raises(Reanimator::ArchiveStore::Error) { @store.restore(entry, @saves) }
    assert_equal 'current', File.read(File.join(slot, 'world.data'))
  end
end
