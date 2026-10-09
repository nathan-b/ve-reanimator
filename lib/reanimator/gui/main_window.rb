require 'reanimator/gtk'
require 'reanimator/archive_store'

module Reanimator
  module GUI
    # The real dialogs. The window talks to this interface so tests can answer
    # its questions without anything appearing on screen.
    class GtkDialogs
      def confirm(window, text)
        ask(window, :question, :yes_no, text) == Gtk::ResponseType::YES
      end

      def error(window, text)
        ask(window, :error, :close, text)
      end

      private

      def ask(window, type, buttons, text)
        dialog = Gtk::MessageDialog.new(parent: window, flags: :modal, type: type, buttons: buttons, message: text)
        response = dialog.run
        dialog.destroy
        response
      end
    end

    # Two columns: a stack of buttons on the left, and on the right a tabbed
    # list of archived saves (good saves and death saves, newest first). A
    # status bar along the bottom says whether and what is being watched.
    class MainWindow < Gtk::Window
      TABS = { good: 'Good saves', death: 'Death saves' }.freeze
      REFRESH_SECONDS = 2
      MESSAGE_SECONDS = 6

      attr_reader :restore_button, :delete_button, :backup_button, :status_text

      # +app+ is the running Reanimator::App (nil if there is no saves directory
      # to watch), +saves_dir+ the game's save directory (nil likewise) and
      # +problem+ says why there is none.
      def initialize(store:, app:, saves_dir:, problem: nil, dialogs: GtkDialogs.new)
        super()
        @store = store
        @app = app
        @saves_dir = saves_dir
        @problem = problem
        @dialogs = dialogs
        @entries = TABS.keys.to_h { |kind| [kind, []] }
        @lists = {}

        self.title = 'VoidExpanse Reanimator'
        set_default_size(640, 400)
        add(build_layout)
        refresh
        @timer = GLib::Timeout.add_seconds(REFRESH_SECONDS) { refresh && true }
        signal_connect('destroy') { GLib::Source.remove(@timer) }
      end

      def tab_labels
        TABS.values
      end

      # The text of each row of the +kind+ (:good or :death) list.
      def row_texts(kind)
        @lists[kind].children.map { |row| row.child.text }
      end

      def selected_text
        row = @lists[current_kind].selected_row
        row&.child&.text
      end

      # Show the +kind+ tab and select its +index+th row.
      def select(kind, index)
        @notebook.page = TABS.keys.index(kind)
        @lists[kind].select_row(@lists[kind].get_row_at_index(index))
      end

      # Reload the lists and the status bar from disk.
      def refresh
        selected = selected_entry&.path
        TABS.each_key { |kind| reload(kind, selected) }
        update_buttons
        update_status
        true
      end

      private

      def build_layout
        @restore_button = Gtk::Button.new(label: 'Restore selected save')
        @delete_button = Gtk::Button.new(label: 'Delete selected save')
        @backup_button = Gtk::Button.new(label: 'Manual backup')
        @restore_button.signal_connect('clicked') { restore_selected }
        @delete_button.signal_connect('clicked') { delete_selected }
        @backup_button.signal_connect('clicked') { backup_now }

        buttons = Gtk::Box.new(:vertical, 6)
        [@restore_button, @delete_button, @backup_button].each { |b| buttons.pack_start(b, expand: false, fill: true, padding: 0) }

        @notebook = Gtk::Notebook.new
        TABS.each { |kind, label| @notebook.append_page(build_list(kind), Gtk::Label.new(label)) }
        @notebook.signal_connect('switch-page') { |_nb, _page, index| update_buttons(TABS.keys[index]) }

        columns = Gtk::Box.new(:horizontal, 12)
        columns.border_width = 12
        columns.pack_start(buttons, expand: false, fill: true, padding: 0)
        columns.pack_start(@notebook, expand: true, fill: true, padding: 0)

        @statusbar = Gtk::Statusbar.new
        @watch_context = @statusbar.get_context_id('watching')
        @message_context = @statusbar.get_context_id('message')

        layout = Gtk::Box.new(:vertical, 0)
        layout.pack_start(columns, expand: true, fill: true, padding: 0)
        layout.pack_start(@statusbar, expand: false, fill: true, padding: 0)
        layout.show_all # the contents; the window itself stays hidden until the caller shows it
        layout
      end

      def build_list(kind)
        list = Gtk::ListBox.new
        list.selection_mode = :single
        list.signal_connect('row-selected') { update_buttons }
        @lists[kind] = list
        scroll = Gtk::ScrolledWindow.new
        scroll.add(list)
        scroll
      end

      def current_kind
        TABS.keys[@notebook.page]
      end

      def selected_entry(kind = current_kind)
        row = @lists[kind].selected_row
        row && @entries[kind][row.index]
      end

      def describe(entry)
        "#{entry.slot}  #{entry.time.strftime('%Y-%m-%d %H:%M:%S')}"
      end

      # Rebuild a list if what is on disk differs from what is shown, keeping the
      # selection (identified by archive path) where it still exists.
      def reload(kind, selected_path)
        entries = @store.entries(kind)
        return if entries.map(&:path) == @entries[kind].map(&:path)

        list = @lists[kind]
        list.children.each { |row| list.remove(row) }
        @entries[kind] = entries
        entries.each { |entry|
          label = Gtk::Label.new(describe(entry))
          label.xalign = 0
          label.set_margin(6)
          list.add(label)
        }
        list.show_all
        index = entries.index { |e| e.path == selected_path }
        list.select_row(list.get_row_at_index(index)) if index
      end

      def update_buttons(kind = current_kind)
        selected = !selected_entry(kind).nil?
        @restore_button.sensitive = selected && !@saves_dir.nil?
        @delete_button.sensitive = selected
        @backup_button.sensitive = !@app.nil? && !@saves_dir.nil?
      end

      def update_status
        text = if @app&.watching?
                 "Watching #{@saves_dir}"
               elsif @problem
                 "Not watching: #{@problem}"
               else
                 "Not watching #{@saves_dir}"
               end
        return if text == @status_text

        @statusbar.pop(@watch_context) if @status_text
        @statusbar.push(@watch_context, text)
        @status_text = text
      end

      # Show +text+ in the status bar for a few seconds.
      def flash(text)
        id = @statusbar.push(@message_context, text)
        GLib::Timeout.add_seconds(MESSAGE_SECONDS) {
          @statusbar.remove(@message_context, id)
          false
        }
      end

      def restore_selected
        entry = selected_entry or return
        question = "Restore #{describe(entry)}?\n\nThis overwrites the current #{entry.slot} save. " \
                   'Exit VoidExpanse first if it is running.'
        return unless @dialogs.confirm(self, question)

        @store.restore(entry, @saves_dir)
        flash("Restored #{describe(entry)}")
      rescue ArchiveStore::Error, SystemCallError => e
        @dialogs.error(self, "Could not restore: #{e.message}")
        refresh
      end

      def delete_selected
        entry = selected_entry or return
        return unless @dialogs.confirm(self, "Delete the saved copy #{describe(entry)}?\n\nThis cannot be undone.")

        @store.delete(entry)
        refresh
        flash("Deleted #{describe(entry)}")
      rescue SystemCallError => e
        @dialogs.error(self, "Could not delete: #{e.message}")
      end

      def backup_now
        created = @app.backup_now
        refresh
        flash(created.empty? ? 'Nothing new to back up' : "Backed up #{created.size} save#{'s' if created.size > 1}")
      rescue SystemCallError => e
        @dialogs.error(self, "Could not back up: #{e.message}")
      end
    end
  end
end
