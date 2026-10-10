require 'json'
require 'zip'

# Builds world.data files shaped like the real thing, but containing only the
# parts of the save that reanimator reads (see doc/vesave.md).
module SaveBuilder
  SHIP_ID = 17_814
  INVENTORY_CONTAINER = 322

  # The save document as a Hash. +items+ is the number of items in the ship
  # inventory and +cargo+ the number of trade-goods types in the cargo hold.
  # +save_number+ makes otherwise identical saves differ. +structure+ is the
  # player ship's hull integrity (0 means destroyed); nil leaves the ship object out.
  def self.document(items: 3, cargo: 0, save_number: 0, structure: 4000.0)
    slots = { '$id' => '9001' }
    items.times { |i| slots[i.to_s] = 5000 + i }
    cargo_items = { '$id' => '9002' }
    cargo.times { |i|
      cargo_items["ore_#{i}"] = { 'Count' => 10 + i, 'XmlCargoTypeId' => "ore_#{i}" }
    }
    doc = {
      '$id' => '1',
      'SaveNumber' => save_number,
      'ItemsModule' => {
        '$id' => '2',
        'inventories' => { '$id' => '3', SHIP_ID.to_s => INVENTORY_CONTAINER },
        'containers' => {
          '$id' => '4',
          INVENTORY_CONTAINER.to_s => {
            '$id' => '5', 'Type' => 0, 'OwnerID' => SHIP_ID,
            'itemsSlots' => slots, 'cargoItems' => cargo_items, 'cargo' => { '$id' => '9003' }
          }
        }
      },
      'PlayersManager' => {
        '$id' => '6',
        'playersCollection' => { '$id' => '7', 'testpilot' => { '$id' => '8', 'ShipID' => SHIP_ID, 'money' => 1000 } }
      }
    }
    doc['ObjectsManager'] = objects_manager(structure) if structure
    doc
  end

  # Objects are grouped by kind; the player's ship is one entry in one group.
  def self.objects_manager(structure)
    ship = { '$id' => '13', 'currentValues' => { '$id' => '14', 'structure' => structure } }
    other = { '$id' => '15', 'currentValues' => { '$id' => '16', 'structure' => 0.0 } }
    {
      '$id' => '10',
      'dictionary' => [
        { 'key' => 11, 'value' => { '$id' => '17', 'dictionary' => { '$id' => '18', '99' => other } } },
        { 'key' => 1, 'value' => { '$id' => '11', 'dictionary' => { '$id' => '12', SHIP_ID.to_s => ship } } }
      ]
    }
  end

  # Zip +json+ the way the game does: a single entry named `data`.
  def self.write_zip(path, json)
    Zip::OutputStream.open(path) { |z|
      z.put_next_entry('data')
      z.write(json)
    }
  end

  # Write a world.data at +path+. The game writes a UTF-8 BOM and minified JSON;
  # +bom+ and +pretty+ allow the other forms for tolerance tests.
  def self.write_world_data(path, bom: true, pretty: false, **doc_opts)
    doc = document(**doc_opts)
    json = pretty ? JSON.pretty_generate(doc) : JSON.generate(doc)
    write_zip(path, (bom ? "﻿" : '') + json)
  end
end
