require_relative 'test_helper'
require 'open3'
require 'rbconfig'
require 'stringio'
require 'reanimator/gtk_loader'

class GtkLoaderTest < Minitest::Test
  LIB = File.expand_path('../lib', __dir__)

  # Runs +body+ with $stderr captured; returns what was written to it.
  def capture_stderr
    saved = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = saved
  end

  def test_drops_the_pangocairo_unsupported_function_warning
    out = capture_stderr do
      Reanimator::GtkLoader.quietly { warn 'Unsupported PangoCairo function: layout_path_for_components' }
    end

    assert_equal '', out
  end

  def test_lets_every_other_warning_through
    out = capture_stderr do
      Reanimator::GtkLoader.quietly do
        warn 'Unsupported PangoCairo function: layout_path_for_components'
        warn 'something genuinely wrong'
      end
    end

    assert_equal "something genuinely wrong\n", out
  end

  def test_returns_the_blocks_value
    assert_equal 42, Reanimator::GtkLoader.quietly { 42 }
  end

  def test_restores_stderr_and_still_reports_other_output_when_the_block_raises
    out = capture_stderr do
      stream = $stderr
      assert_raises(RuntimeError) do
        Reanimator::GtkLoader.quietly do
          warn 'before the failure'
          raise 'boom'
        end
      end
      assert_same stream, $stderr
    end

    assert_equal "before the failure\n", out
  end

  # The real thing, in a fresh process because gtk3 is already loaded here.
  def test_requiring_the_loader_prints_nothing
    _, err, status = Open3.capture3(RbConfig.ruby, '-I', LIB, '-e', "require 'reanimator/gtk'")

    assert_equal '', err
    assert status.success?
  end

  def test_the_loader_really_loads_gtk
    out, err, status = Open3.capture3(RbConfig.ruby, '-I', LIB, '-e',
                                      "require 'reanimator/gtk'; puts Gtk::Window.name")

    assert_equal "Gtk::Window\n", out, err
    assert status.success?
  end
end
