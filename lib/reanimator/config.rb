require 'yaml'

module Reanimator
  # Settings from ve-reanimator.yaml, with every path resolved to an absolute one.
  #
  #   saves_dir        game save directory (nil: autodiscover)
  #   max_saves        number of normal saves to keep, 1-16 (default 3)
  #   archive_dir      where normal saves are kept (default ~/.cache/ve-reanimator)
  #   death_dir        where death saves are kept (default "death", inside archive_dir)
  #   max_death_saves  number of death saves to keep, 1-16 (default 1)
  #
  # Relative archive_dir and saves_dir are relative to the config file's
  # directory; a relative death_dir is relative to archive_dir. +source+ is the
  # path of the file the settings came from (nil if there was none).
  Config = Data.define(:saves_dir, :max_saves, :archive_dir, :death_dir, :max_death_saves, :source)

  class Config
    class Error < StandardError; end

    FILE_NAME = 've-reanimator.yaml'
    OPTIONS = %w[saves_dir max_saves archive_dir death_dir max_death_saves].freeze
    COUNT_RANGE = (1..16)

    # Build a Config from the text of a config file. +base_dir+ is the directory
    # relative paths are resolved against and +home+ the meaning of "~".
    def self.parse(yaml, base_dir:, home: Dir.home)
      options = read_options(yaml)

      unknown = options.keys - OPTIONS
      raise Error, "unknown option#{'s' if unknown.size > 1}: #{unknown.join(', ')}" unless unknown.empty?

      archive_dir = resolve(path_option(options, 'archive_dir'), base_dir, home) ||
                    File.join(home, '.cache', 've-reanimator')
      saves_dir = resolve(path_option(options, 'saves_dir'), base_dir, home)
      death_dir = resolve(path_option(options, 'death_dir'), archive_dir, home) ||
                  File.join(archive_dir, 'death')

      new(saves_dir: saves_dir,
          max_saves: count_option(options, 'max_saves', 3),
          archive_dir: archive_dir,
          death_dir: death_dir,
          max_death_saves: count_option(options, 'max_death_saves', 1),
          source: nil)
    end

    # Load ve-reanimator.yaml from +cwd+ or, failing that, ~/.config/ve-reanimator.
    # With no file at all the defaults are returned.
    def self.load(cwd: Dir.pwd, home: Dir.home)
      path = [cwd, File.join(home, '.config', 've-reanimator')]
             .map { |dir| File.join(dir, FILE_NAME) }
             .find { |candidate| File.file?(candidate) }
      return parse('', base_dir: cwd, home: home) unless path

      parse(File.read(path), base_dir: File.dirname(path), home: home).with(source: path)
    rescue Error => e
      raise Error, "#{path}: #{e.message}" if path

      raise
    rescue SystemCallError => e
      raise Error, "cannot read #{path}: #{e.message}"
    end

    def self.read_options(yaml)
      options = YAML.safe_load(yaml) || {}
      raise Error, 'config file must be a mapping of options (name: value)' unless options.is_a?(Hash)

      options
    rescue Psych::Exception => e
      raise Error, "config file is not valid YAML: #{e.message}"
    end
    private_class_method :read_options

    def self.count_option(options, name, default)
      return default unless options.key?(name)

      value = options[name]
      raise Error, "#{name} must be an integer from #{COUNT_RANGE.min} to #{COUNT_RANGE.max}, got #{value.inspect}" unless value.is_a?(Integer) && COUNT_RANGE.cover?(value)

      value
    end
    private_class_method :count_option

    def self.path_option(options, name)
      return nil unless options.key?(name)

      value = options[name]
      raise Error, "#{name} must be a non-empty path, got #{value.inspect}" unless value.is_a?(String) && !value.strip.empty?

      value
    end
    private_class_method :path_option

    def self.resolve(path, base_dir, home)
      return nil if path.nil?

      File.expand_path(path.sub(/\A~(?=\/|\z)/) { home }, base_dir)
    end
    private_class_method :resolve
  end
end
