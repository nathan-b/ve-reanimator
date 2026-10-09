require 'reanimator/gtk'
require 'reanimator/app'
require 'reanimator/archive_store'
require 'reanimator/config'
require 'reanimator/gui/main_window'

module Reanimator
  module GUI
    module_function

    # Start watching (if a saves directory can be found) and build the window
    # for it. Returns [window, app]; app is nil when there is nothing to watch,
    # in which case the window still opens and says why. +saves_dir+ overrides
    # the configured one. Other options go to App.build.
    def build(config, saves_dir: nil, env: ENV, **app_options)
      app = problem = nil
      begin
        app = App.build(config, saves_dir: saves_dir, env: env, **app_options)
        app.start
      rescue App::NoSavesDirectory => e
        problem = e.message
      end

      store = ArchiveStore.new(archive_dir: config.archive_dir, death_dir: config.death_dir)
      [MainWindow.new(store: store, app: app, saves_dir: app&.saves_dir, problem: problem), app]
    end

    # Open the window and run until it is closed.
    def run(config, saves_dir: nil)
      window, app = build(config, saves_dir: saves_dir)
      window.signal_connect('destroy') {
        app&.stop
        Gtk.main_quit
      }
      window.show_all
      Gtk.main
    end

    # Tell the user something went wrong, for when there may be no terminal.
    def report_error(text)
      warn "ve-reanimator: #{text}"
      GtkDialogs.new.error(nil, text)
    end
  end
end
