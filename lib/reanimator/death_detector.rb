require 'json'
require 'zip'

module Reanimator
  # Decides whether a save was made right after the player died; see doc/vesave.md.
  # There are two signs. Once the game has respawned the player, the ship inventory
  # and cargo hold are empty. Before that (choosing "save and exit" on the death
  # screen) the inventory is still full but the ship has no structure left.
  module DeathDetector
    # The file could not be read as a VoidExpanse save: it is missing, partial
    # (the game may still be writing it), corrupt, or not shaped as expected.
    # Such a save must not be treated as a death.
    class UnreadableSave < StandardError; end

    module_function

    # +world_data_path+ is the path of a world.data file. Returns true if it is a
    # death save and false if it is a normal one. Raises UnreadableSave if it
    # cannot be classified.
    def death_save?(world_data_path)
      save = parse(world_data_path)
      player = save.fetch('PlayersManager').fetch('playersCollection').reject { |k, _| k == '$id' }.values.first
      ship_id = player.fetch('ShipID')
      items_module = save.fetch('ItemsModule')
      container_id = items_module.fetch('inventories').fetch(ship_id.to_s)
      container = items_module.fetch('containers').fetch(container_id.to_s)

      items = container.fetch('itemsSlots').reject { |k, v| k == '$id' || v == 0 }
      cargo = container.fetch('cargoItems').reject { |k, _| k == '$id' }
      (items.empty? && cargo.empty?) || ship_destroyed?(save, ship_id)
    rescue KeyError, NoMethodError, TypeError => e
      raise UnreadableSave, "#{world_data_path}: unexpected save structure (#{e.message})"
    end

    # True if the ship's hull is gone. A save where the ship or its structure can't be
    # found just has no such sign, so the inventory decides alone.
    def ship_destroyed?(save, ship_id)
      groups = save.dig('ObjectsManager', 'dictionary')
      return false unless groups.is_a?(Array)

      groups.each do |group|
        ship = group.dig('value', 'dictionary', ship_id.to_s)
        structure = ship.dig('currentValues', 'structure') if ship.is_a?(Hash)
        return structure <= 0 if structure.is_a?(Numeric)
      end
      false
    end

    def parse(path)
      json = Zip::File.open(path) { |zip| zip.first.get_input_stream.read }
      JSON.parse(json.force_encoding('UTF-8').delete_prefix("\uFEFF"))
    rescue Zip::Error, JSON::ParserError, SystemCallError, EOFError, NoMethodError => e
      raise UnreadableSave, "#{path}: #{e.message}"
    end
  end
end
