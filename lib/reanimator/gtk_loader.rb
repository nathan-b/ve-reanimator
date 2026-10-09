require 'stringio'

module Reanimator
  # Loading ruby-gnome's Pango bindings prints "Unsupported PangoCairo function: ..."
  # for every Pango function newer than the gem's name patterns (Pango 1.58 has
  # layout_path_for_components). It only means a binding we never call is missing.
  module GtkLoader
    BENIGN = /\AUnsupported PangoCairo function: /

    # Runs the block, discarding BENIGN lines written to $stderr and passing the
    # rest through, even if the block raises.
    def self.quietly
      real = $stderr
      $stderr = captured = StringIO.new
      yield
    ensure
      $stderr = real
      captured.string.each_line { |line| real.write(line) unless line.match?(BENIGN) }
    end
  end
end
