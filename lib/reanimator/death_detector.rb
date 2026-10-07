require 'json'
require 'zip'

module Reanimator
  # Decides whether a save was made right after the player died. A death empties
  # the player's ship inventory and cargo hold; see doc/vesave.md.
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
      items_module = save.fetch('ItemsModule')
      container_id = items_module.fetch('inventories').fetch(player.fetch('ShipID').to_s)
      container = items_module.fetch('containers').fetch(container_id.to_s)

      items = container.fetch('itemsSlots').reject { |k, v| k == '$id' || v == 0 }
      cargo = container.fetch('cargoItems').reject { |k, _| k == '$id' }
      items.empty? && cargo.empty?
    rescue KeyError, NoMethodError, TypeError => e
      raise UnreadableSave, "#{world_data_path}: unexpected save structure (#{e.message})"
    end

    def parse(path)
      json = Zip::File.open(path) { |zip| zip.first.get_input_stream.read }
      JSON.parse(json.force_encoding('UTF-8').delete_prefix("\uFEFF"))
    rescue Zip::Error, JSON::ParserError, SystemCallError, EOFError, NoMethodError => e
      raise UnreadableSave, "#{path}: #{e.message}"
    end
  end
end
