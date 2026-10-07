# VoidExpanse save format: findings for death detection

Phase 0 research output. Goal: decide whether a save has an empty player inventory, without resolving item names.

Samples used (all pilot `electronomancer`, ship ID 17814):

| Sample | Description |
|---|---|
| `examples/before_death/` | Save made just before dying (`world.data` later reformatted with `jq` and re-zipped; see File layout) |
| `examples/after_death/` | Save made after dying (about 2 minutes of play later) |
| `test/slot_0/` | Older, unrelated save with a small inventory (2 items) |
| `examples/before_death_with_cargo/` | Save in open space with 16 items plus mined ore in the ship's cargo hold |
| `examples/after_death_with_cargo/` | Save after blowing up the ship again: inventory and cargo both gone |

## TL;DR

A save is a **death save** when the player's ship inventory container has no items **and** no cargo:

```ruby
j      = JSON.parse(json)
player = j['PlayersManager']['playersCollection'].reject { |k, _| k == '$id' }.values.first
ci     = j['ItemsModule']['inventories'][player['ShipID'].to_s]   # container index
inv    = j['ItemsModule']['containers'][ci.to_s]
items  = inv['itemsSlots'].reject { |k, _| k == '$id' }.values.reject(&:zero?)
cargo  = inv['cargoItems'].reject { |k, _| k == '$id' }
empty  = items.empty? && cargo.empty?
```

Verified on all five samples: `slot_0`, `before_death` and `before_death_with_cargo` are not empty;
`after_death` and `after_death_with_cargo` are empty. Death clears both items and cargo, so requiring both
to be empty detects every death while avoiding a false positive for a player who holds only cargo.

## File layout

- `world.data` is a ZIP archive (deflate) with a single entry named `data`. It is not gzip. `save.data`,
  `save_info.data` and `screenshot.jpg` are not needed for detection.
- The entry is one JSON document (Json.NET output, with `$id` reference tracking). 12 to 32 MB uncompressed.
- **Game-written saves start with a UTF-8 BOM** (`EF BB BF`) and are minified (`after_death` and
  `test/slot_0` are genuine game output). Strip the BOM before parsing; `jq` rejects it.
- `before_death/world.data` is **not** in the game's native format: the author pretty-printed it with `jq` and
  re-zipped it with the system `zip` utility while investigating. The game was confirmed to load such a file,
  so the game is tolerant of both formats, but real saves from the game will look like `after_death`.
  Detection results are unaffected, since only whitespace and the BOM differ. Detector tests should use
  game-native saves, not `before_death`'s format. A tolerant parser (BOM stripped if present) costs nothing.
- `$id` values are Json.NET reference IDs. They renumber between saves, so ignore them when diffing.
- Performance in Ruby 3.4 (`rubyzip` + stdlib `JSON`): unzip about 0.05 to 0.08 s, parse about 0.2 to 0.3 s for
  the largest sample. Parsing the whole document is fast enough; no streaming or partial parsing is needed.

## Top-level keys

`Game`, `GlobalGameTimer`, `ItemsManager` (about 2.3 MB), `ItemsModule` (about 140 KB), `ObjectsManager`
(about 13.8 MB, world objects), `PlayersManager` (about 36 KB), `RelationsManager`, `Seed`, `SpawnData`,
`TradeModule`, `WorldManager*` and `<ScopeStorage>k__BackingField`.

Only `PlayersManager` and `ItemsModule` are needed for detection.

## Where the inventory lives

1. `PlayersManager.playersCollection.<pilot name>` is the player record. The key is the pilot name
   (`electronomancer`); `$id` is a sibling key and must be skipped. It holds `money`, `ShipID`, quests and so on.
   `PlayersManager.lastPlayerId` is 1 (single player).
2. `ItemsModule.inventories` maps **ship object ID → container index**. `inventories["17814"]` is 322.
3. `ItemsModule.containers["322"]` is the inventory container (`Type` 0):
   - `itemsSlots`: slot number → item ID. 16 entries in `before_death`, **0 entries in `after_death`**
     (emptied slots are deleted, not zeroed). `slot_0` has 2.
   - `cargoItems`: trade goods and ore, keyed by cargo type ID, e.g.
     `"ore_glepsite": {"Count": 66, "AverageBuyingPrice": 2.0, "XmlCargoTypeId": "ore_glepsite"}`. Empty hash
     after death. The `$id` key must be skipped when counting.
   - `cargo`: always empty in every sample, including NPC containers. Ignored.
   - `OwnerID`: the ship ID.
4. Item IDs index into `ItemsManager._table`. After death all 16 inventory items are gone from the table.

Container `Type` values seen: 0 = ship inventory, 1 = equipment, 2 = station storage owned by the player
(holds `cargoItems` such as ore). Types are inferred from contents; there are no names in the save.

## What a death changes

Compared `before_death` and `after_death` for the player:

| Thing | Effect of death |
|---|---|
| Inventory container (322) `itemsSlots` | **Emptied** (16 → 0 entries). Detection signal. |
| Inventory container (322) `cargoItems` | **Emptied** (3 ore types → none; confirmed with the cargo samples). Detection signal. |
| Money | Reduced by 10%: 25037 → 22533, and 35037 → 31533. Matches `death_money_loss: 10`. |
| Equipment container (321) | **Unchanged**. Equipped gear survives. |
| Station storages (Type 2: 323, 330, 399, …) | Unchanged. Ore stored at stations survives death. |
| `ShipID` | Unchanged (`ship_loss: 0`) |
| `Game.gameEndResult`, `IsGameOverSent` | Unchanged. There is no explicit "dead" flag. |

`PlayersManager.GeneratorArgs` holds the death-penalty settings. The game has three penalty modes:

1. Lose all inventory, cargo and 10% of money. This is the mode all samples were made in:
   `death_money_loss: 10`, `inventory_loss: 1`, `ship_loss: 0`, `permadeath: 0`.
2. Everything in (1) plus the entire ship (presumably `ship_loss: 1`).
3. Permadeath: the character dies permanently and the player starts over (presumably `permadeath: 1`).

Only mode 1 was observed; the field values for modes 2 and 3 are inferred. **Scope:** reanimator targets
mode 1 only. Its purpose is to make death cost nothing but a restore from an earlier save, which is only
meaningful when death leaves a recognizable empty-inventory save and the ship survives. Players in modes 2
and 3 are assumed not to use the tool, and no samples of their death saves exist, so the detector is
neither designed nor tested for them.

Optional hardening for a later phase: read `GeneratorArgs` and warn at startup if `inventory_loss`
is 0 (detection would never fire) or if `ship_loss` or `permadeath` is non-zero (unsupported mode).

## Open questions and edge cases

- **Trade-goods cargo.** Resolved: death clears the ship's `cargoItems` along with `itemsSlots`. A save is
  only treated as a death save if both are empty.
- **Location.** `before_death_with_cargo` was made in open space rather than at a station. The layout is the
  same, so location does not affect detection.
- **Legitimate empty inventory.** A new game or a player who sold everything and carries no cargo is
  indistinguishable from a death save by this signal. The design in `reanimator.md` already accepts
  this: the next non-empty save moves back to the primary store.
- **Multiple players.** Only one player exists in these saves. Code should use the player record's own
  `ShipID` rather than a hard-coded ship ID or name.
- **Ship changes.** Inventories are keyed by ship ID, so always look up the current `ShipID`; do not cache it.
- **Missing keys.** If `inventories[ShipID]` is absent (fresh game or an unexpected format), treat it as
  "unknown", not "death". The detector should not move saves to the death directory on a parse failure.
- **Mid-write reads.** The game writes `world.data` in place. A watcher can see a partial file, so retry or
  wait for the file to settle if the zip or JSON fails to parse.

## Reproducing

```sh
unzip -o world.data -d out/       # produces out/data (strip the BOM before using jq)
```

Container 322 is not special; look it up through `inventories[ShipID]` as shown above.
