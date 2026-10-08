require 'reanimator/slot'

module Reanimator
  # Finds the VoidExpanse Saves directory by looking in the places the game is
  # known to keep it. A candidate only counts if it holds at least one slot with a
  # world.data; if several do, the one with the most recently written save wins.
  #
  # Verified: Steam app 324260 under Proton (including Flatpak Steam). The native
  # Linux and Windows locations follow from the Proton one and are untested.
  module SaveLocator
    STEAM_APP_ID = '324260'
    GAME_PATH = File.join('AtomicTorchStudio', 'VoidExpanse', 'Saves').freeze
    FLATPAK_STEAM = File.join('.var', 'app', 'com.valvesoftware.Steam').freeze

    module_function

    # The Saves directory with the newest save, or nil if none is found.
    def locate(env = ENV)
      candidates(env).select { |dir| newest_save_time(dir) }.max_by { |dir| newest_save_time(dir) }
    end

    # Every place a Saves directory might be, whether or not it exists.
    def candidates(env = ENV)
      home = env['HOME']
      profile = env['USERPROFILE']
      paths = []

      if home
        steam_roots(home).each { |root|
          paths << File.join(root, 'steamapps', 'compatdata', STEAM_APP_ID, 'pfx', 'drive_c', 'users',
                             'steamuser', 'Documents', GAME_PATH)
        }
        paths << File.join(home, '.config', GAME_PATH)
        paths << File.join(home, FLATPAK_STEAM, '.config', GAME_PATH)
      end
      paths << File.join(profile, 'Documents', GAME_PATH) if profile

      paths
    end

    def steam_roots(home)
      [
        File.join(home, '.local', 'share', 'Steam'),
        File.join(home, '.steam', 'steam'),
        File.join(home, FLATPAK_STEAM, '.local', 'share', 'Steam')
      ]
    end

    # Modification time of the newest slot's world.data in +dir+, or nil if there is none.
    def newest_save_time(dir)
      return nil unless File.directory?(dir)

      Dir.children(dir).select { |name| Slot.name?(name) }.map { |name| File.join(dir, name, 'world.data') }
         .select { |f| File.file?(f) }.map { |f| File.mtime(f) }.max
    end
  end
end
