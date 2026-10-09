$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift File.expand_path('support', __dir__)

# GTK must be loaded before Minitest. Both run code from at_exit hooks, and Ruby
# runs those in reverse order of registration: if Minitest registered first,
# GTK's hook would run first, invalidate every signal handler, and the tests
# would then run without any ever firing. (A missing display just skips the
# window tests; see main_window_test.rb.)
begin
  require 'gtk3'
rescue LoadError, StandardError
  nil
end

require 'minitest/autorun'
require 'tmpdir'
