# frozen_string_literal: true

require "open3"
require "pathname"
require "shellwords"

module Conntrack
  class Snapshot
    DEFAULT_COMMAND = ["conntrack", "-L", "-o", "extended"].freeze

    def self.read(command: command_from_env, input_file: ENV["CONNTRACK_INPUT_FILE"], output: nil, runner: Open3)
      raw_output = output || read_output(command, input_file, runner)
      parse_output(raw_output)
    end

    def self.read_output(command, input_file, runner)
      path = input_file.to_s.strip
      unless path.empty?
        if defined?(Rails) && !Pathname.new(path).absolute?
          path = Rails.root.join(path).to_s
        end
        return File.read(path)
      end

      stdout, status = runner.capture2e(*command)
      raise "conntrack snapshot failed: #{stdout.strip}" unless status.success?

      stdout
    rescue Errno::ENOENT
      raise "conntrack not found. Install conntrack-tools or set CONNTRACK_INPUT_FILE=spec/fixtures/conntrack/router_extended.txt"
    end
    private_class_method :read_output

    def self.command_from_env
      raw = ENV["CONNTRACK_COMMAND"].to_s.strip
      return DEFAULT_COMMAND if raw.empty?

      Shellwords.split(raw)
    end
    private_class_method :command_from_env

    def self.parse_output(raw_output)
      unless defined?(Conntrack::Parser) && Conntrack::Parser.respond_to?(:parse_line)
        raise "Conntrack::Parser.parse_line is not available"
      end

      entries = []
      raw_output.each_line do |line|
        next if line.strip.empty?

        entry = Conntrack::Parser.parse_line(line)
        entries << entry if entry
      end
      entries
    end
    private_class_method :parse_output
  end
end
