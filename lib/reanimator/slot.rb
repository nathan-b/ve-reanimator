module Reanimator
  # The game keeps each save in a directory named slot_<number>. Other
  # directories next to them (such as a hand-made backup_slot_0) are not saves.
  module Slot
    PATTERN = 'slot_\d+'
    NAME = /\A#{PATTERN}\z/

    def self.name?(dir_name)
      NAME.match?(dir_name)
    end
  end
end
