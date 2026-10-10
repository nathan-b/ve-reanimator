require_relative 'test_helper'
require 'save_builder'
require 'reanimator/death_detector'

class DeathDetectorTest < Minitest::Test
  Detector = Reanimator::DeathDetector

  def setup
    @dir = Dir.mktmpdir('ve-detector')
    @path = File.join(@dir, 'world.data')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Write a synthetic save and return its path.
  def save(**opts)
    SaveBuilder.write_world_data(@path, **opts)
    @path
  end

  # Write a save built from a (mutated) copy of the standard document.
  def save_from_document
    doc = SaveBuilder.document
    yield doc
    SaveBuilder.write_zip(@path, JSON.generate(doc))
    @path
  end

  def inventory(doc)
    doc['ItemsModule']['containers'][SaveBuilder::INVENTORY_CONTAINER.to_s]
  end
  EXAMPLES = File.expand_path('../examples', __dir__)

  def real_save(name)
    File.join(EXAMPLES, name, 'world.data')
  end

  # --- real game saves (see doc/vesave.md for how each was made) ---

  def test_save_with_inventory_is_not_a_death_save
    refute Reanimator::DeathDetector.death_save?(real_save('before_death'))
  end

  def test_save_after_dying_is_a_death_save
    assert Reanimator::DeathDetector.death_save?(real_save('after_death'))
  end

  def test_save_with_inventory_and_cargo_is_not_a_death_save
    refute Reanimator::DeathDetector.death_save?(real_save('before_death_with_cargo'))
  end

  def test_save_after_dying_with_cargo_is_a_death_save
    assert Reanimator::DeathDetector.death_save?(real_save('after_death_with_cargo'))
  end

  def test_save_with_only_a_couple_of_items_is_not_a_death_save
    refute Reanimator::DeathDetector.death_save?(File.expand_path('slot_0/world.data', __dir__))
  end

  # Saved by choosing "save and exit" right after dying: the ship is destroyed but the
  # game has not respawned the player yet, so inventory and money are still intact.
  def test_save_made_while_dead_is_a_death_save_though_the_inventory_is_still_full
    assert Reanimator::DeathDetector.death_save?(real_save('dead_before_respawn'))
  end

  # --- synthetic saves ---

  def test_empty_inventory_and_cargo_is_a_death_save
    assert Detector.death_save?(save(items: 0, cargo: 0))
  end

  def test_items_without_cargo_is_not_a_death_save
    refute Detector.death_save?(save(items: 1, cargo: 0))
  end

  def test_cargo_without_items_is_not_a_death_save
    refute Detector.death_save?(save(items: 0, cargo: 1))
  end

  def test_destroyed_ship_is_a_death_save_even_with_items_and_cargo
    assert Detector.death_save?(save(items: 3, cargo: 2, structure: 0.0))
  end

  def test_ship_with_hull_left_is_not_a_death_save
    refute Detector.death_save?(save(items: 3, structure: 0.5))
  end

  def test_only_the_players_ship_counts_not_other_destroyed_ships
    # the builder's other ship has no structure left and is not the player's
    refute Detector.death_save?(save(items: 3, structure: 4000.0))
  end

  def test_without_a_ship_object_the_inventory_alone_decides
    refute Detector.death_save?(save(items: 3, structure: nil))
    assert Detector.death_save?(save(items: 0, structure: nil))
  end

  def test_a_ship_without_a_structure_value_is_judged_by_its_inventory
    path = save_from_document { |doc|
      ship = doc['ObjectsManager']['dictionary'].last['value']['dictionary'][SaveBuilder::SHIP_ID.to_s]
      ship['currentValues'].delete('structure')
    }

    refute Detector.death_save?(path)
  end

  def test_slots_that_point_at_item_zero_count_as_empty
    path = save_from_document { |doc|
      slots = inventory(doc)['itemsSlots']
      slots.each_key { |k| slots[k] = 0 unless k == '$id' }
      inventory(doc)['cargoItems'].clear
    }

    assert Detector.death_save?(path)
  end

  def test_reads_saves_without_a_bom_that_are_pretty_printed
    assert Detector.death_save?(save(items: 0, bom: false, pretty: true))
    refute Detector.death_save?(save(items: 2, bom: false, pretty: true))
  end

  # --- saves that cannot be classified must raise, never read as a death ---

  def assert_unreadable(path)
    assert_raises(Detector::UnreadableSave) { Detector.death_save?(path) }
  end

  def test_missing_file_is_unreadable
    assert_unreadable File.join(@dir, 'nope', 'world.data')
  end

  def test_file_that_is_not_a_zip_is_unreadable
    File.write(@path, 'this is not a zip')
    assert_unreadable @path
  end

  def test_empty_file_is_unreadable
    File.write(@path, '')
    assert_unreadable @path
  end

  def test_truncated_zip_is_unreadable
    FileUtils.cp(real_save('after_death'), @path)
    File.truncate(@path, File.size(@path) / 2)
    assert_unreadable @path
  end

  def test_zip_with_invalid_json_is_unreadable
    SaveBuilder.write_zip(@path, '{"PlayersManager": {')
    assert_unreadable @path
  end

  def test_json_without_the_expected_structure_is_unreadable
    SaveBuilder.write_zip(@path, '{"Game": {}}')
    assert_unreadable @path
  end

  def test_player_whose_ship_has_no_inventory_is_unreadable
    assert_unreadable save_from_document { |doc|
      doc['ItemsModule']['inventories'].delete(SaveBuilder::SHIP_ID.to_s)
    }
  end

  def test_save_with_no_players_is_unreadable
    assert_unreadable save_from_document { |doc|
      doc['PlayersManager']['playersCollection'] = { '$id' => '7' }
    }
  end
end
