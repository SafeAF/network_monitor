# frozen_string_literal: true

require "open3"
require "pathname"

module Conntrack
  class Snapshot
    COMMAND = ["conntrack", "-L", "-o", "extended"].freeze

    def self.read(command: COMMAND, input_file: ENV["CONNTRACK_INPUT_FILE"], output: nil, runner: Open3)
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
    end
    private_class_method :read_output

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
