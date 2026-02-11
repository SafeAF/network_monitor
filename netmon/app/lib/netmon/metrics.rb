# frozen_string_literal: true

require "yaml"
require "time"

module Netmon
  class Metrics
    DEFAULT_INTERFACES = ["enp42s0", "enp2s0", "enp3s0"].freeze

    def self.read(now: Time.current, config: nil, file_reader: File, interfaces: nil)
      config ||= load_config
      interfaces = Array(interfaces.presence || config["interfaces"].presence || DEFAULT_INTERFACES)
      interfaces = list_interfaces if interfaces.empty?

      Netmon::MetricsRecorder.record_if_due(now:)
      analytics = Netmon::MetricsReporter.current(now:)
      series = Netmon::MetricsReporter.series
      last_ingest = Rails.cache.read("netmon:last_ingest_at")
      if last_ingest.nil?
        fallback = Connection.maximum(:last_seen_at) || RemoteHost.maximum(:last_seen_at)
        last_ingest = fallback&.to_i
      end
      age_seconds = last_ingest ? (now.to_i - last_ingest.to_i) : nil

      {
        timestamp: now.iso8601,
        loadavg: parse_loadavg(read_text("/proc/loadavg", file_reader)),
        meminfo: parse_meminfo(read_text("/proc/meminfo", file_reader)),
        interfaces: interfaces.filter_map { |iface| read_interface(iface, file_reader) },
        analytics: analytics,
        series: series,
        collector: {
          last_ingest_at: last_ingest ? Time.at(last_ingest).utc.iso8601 : nil,
          age_seconds: age_seconds
        }
      }
    end

    def self.read_interface(iface, file_reader)
      base = "/sys/class/net/#{iface}/statistics"
      stats = {
        name: iface,
        rx_bytes: read_int("#{base}/rx_bytes", file_reader),
        tx_bytes: read_int("#{base}/tx_bytes", file_reader),
        rx_packets: read_int("#{base}/rx_packets", file_reader),
        tx_packets: read_int("#{base}/tx_packets", file_reader)
      }

      return nil if stats.values_at(:rx_bytes, :tx_bytes, :rx_packets, :tx_packets).all?(&:nil?)

      stats
    rescue Errno::ENOENT
      nil
    end
    private_class_method :read_interface

    def self.list_interfaces
      Dir.children("/sys/class/net").sort
    rescue Errno::ENOENT
      []
    end
    private_class_method :list_interfaces

    def self.parse_loadavg(text)
      return { one: nil, five: nil, fifteen: nil } if text.nil?

      parts = text.split
      {
        one: parts[0].to_f,
        five: parts[1].to_f,
        fifteen: parts[2].to_f
      }
    end
    private_class_method :parse_loadavg

    def self.parse_meminfo(text)
      return {} if text.nil?

      wanted = %w[MemTotal MemFree MemAvailable Buffers Cached]
      values = {}
      text.each_line do |line|
        key, rest = line.split(":", 2)
        next unless wanted.include?(key)

        values[key] = rest.to_s.strip.split.first.to_i
      end

      {
        total_kb: values["MemTotal"],
        free_kb: values["MemFree"],
        available_kb: values["MemAvailable"],
        buffers_kb: values["Buffers"],
        cached_kb: values["Cached"]
      }
    end
    private_class_method :parse_meminfo

    def self.read_text(path, file_reader)
      file_reader.read(path)
    rescue Errno::ENOENT
      nil
    end
    private_class_method :read_text

    def self.read_int(path, file_reader)
      Integer(file_reader.read(path).to_s.strip, 10)
    rescue Errno::ENOENT, ArgumentError
      nil
    end
    private_class_method :read_int

    def self.load_config
      path = Rails.root.join("config/netmon.yml")
      YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false) || {}
    rescue Errno::ENOENT
      {}
    end
    private_class_method :load_config
  end
end
