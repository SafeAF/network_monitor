# frozen_string_literal: true

require "yaml"

module Netmon
  class MetricsRecorder
    SAMPLE_INTERVAL = 60.seconds
    BASELINE_WINDOW = 7.days

    def self.record_if_due(now: Time.current)
      last_sample = MetricSample.order(captured_at: :desc).limit(1).pick(:captured_at)
      return if last_sample && last_sample >= now - SAMPLE_INTERVAL

      record!(now:)
    end

    def self.record!(now: Time.current)
      sample = build_sample(now:)
      record = MetricSample.create!(sample)
      record_system!(now:)
      record
    end

    def self.build_sample(now: Time.current)
      window_10m = now - 10.minutes
      window_1h = now - 1.hour

      new_dst_ips_last_10m = RemoteHost.where("first_seen_at >= ?", window_10m).count
      unique_dports_last_10m = Connection.where("last_seen_at >= ?", window_10m)
                                         .where.not(dst_port: nil)
                                         .distinct
                                         .count(:dst_port)
      uplink_bytes_last_10m = Connection.where("last_seen_at >= ?", window_10m)
                                        .sum(:uplink_bytes)

      new_asns_last_1h = if RemoteHost.column_names.include?("whois_asn")
                           RemoteHost.where("first_seen_at >= ?", window_1h)
                                     .where.not(whois_asn: nil)
                                     .distinct
                                     .count(:whois_asn)
                         else
                           0
                         end

      baseline_p95 = baseline_p95_uplink(now:)

      {
        captured_at: now,
        new_dst_ips_last_10m:,
        unique_dports_last_10m:,
        uplink_bytes_last_10m:,
        baseline_p95_uplink_bytes_last_10m: baseline_p95,
        new_asns_last_1h:
      }
    end

    def self.record_system!(now:)
      bucket_ts = now.utc.change(sec: 0)
      loadavg1 = read_loadavg1
      disk_read, disk_write = read_disk_bytes
      rx, tx = read_network_bytes

      last_disk_read = Rails.cache.read("netmon:last_disk_read_bytes").to_i
      last_disk_write = Rails.cache.read("netmon:last_disk_write_bytes").to_i
      last_rx = Rails.cache.read("netmon:last_rx_bytes").to_i
      last_tx = Rails.cache.read("netmon:last_tx_bytes").to_i

      delta_disk_read = [disk_read - last_disk_read, 0].max
      delta_disk_write = [disk_write - last_disk_write, 0].max
      delta_rx = [rx - last_rx, 0].max
      delta_tx = [tx - last_tx, 0].max

      Rails.cache.write("netmon:last_disk_read_bytes", disk_read)
      Rails.cache.write("netmon:last_disk_write_bytes", disk_write)
      Rails.cache.write("netmon:last_rx_bytes", rx)
      Rails.cache.write("netmon:last_tx_bytes", tx)

      record = SystemMinute.find_or_initialize_by(bucket_ts: bucket_ts)
      record.loadavg1 = loadavg1
      record.disk_read_bytes = record.disk_read_bytes.to_i + delta_disk_read
      record.disk_write_bytes = record.disk_write_bytes.to_i + delta_disk_write
      record.rx_bytes = record.rx_bytes.to_i + delta_rx
      record.tx_bytes = record.tx_bytes.to_i + delta_tx
      record.save!
    end

    def self.read_loadavg1
      text = File.read("/proc/loadavg")
      text.to_s.split.first.to_f
    rescue Errno::ENOENT
      nil
    end
    private_class_method :read_loadavg1

    def self.read_disk_bytes
      text = File.read("/proc/diskstats")
      read_sectors = 0
      write_sectors = 0
      text.each_line do |line|
        parts = line.split
        name = parts[2].to_s
        next unless name.match?(/\A(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme\d+n\d+|mmcblk\d+)\z/)

        read_sectors += parts[5].to_i
        write_sectors += parts[9].to_i
      end
      [read_sectors * 512, write_sectors * 512]
    rescue Errno::ENOENT
      [0, 0]
    end
    private_class_method :read_disk_bytes

    def self.read_network_bytes
      config = load_config
      interfaces = Array(config["interfaces"].presence || Netmon::Metrics::DEFAULT_INTERFACES)
      interfaces = Netmon::Metrics.send(:list_interfaces) if interfaces.empty?

      rx_total = 0
      tx_total = 0
      interfaces.each do |iface|
        base = "/sys/class/net/#{iface}/statistics"
        rx_total += Integer(File.read("#{base}/rx_bytes").to_s.strip, 10) rescue 0
        tx_total += Integer(File.read("#{base}/tx_bytes").to_s.strip, 10) rescue 0
      end
      [rx_total, tx_total]
    rescue Errno::ENOENT
      [0, 0]
    end
    private_class_method :read_network_bytes

    def self.load_config
      path = Rails.root.join("config/netmon.yml")
      YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false) || {}
    rescue Errno::ENOENT
      {}
    end
    private_class_method :load_config

    def self.baseline_p95_uplink(now:)
      window_start = now - BASELINE_WINDOW
      values = MetricSample.where("captured_at >= ?", window_start)
                           .order(captured_at: :desc)
                           .limit(2000)
                           .pluck(:uplink_bytes_last_10m)
      percentile(values, 0.95)
    end
    private_class_method :baseline_p95_uplink

    def self.percentile(values, p)
      return 0 if values.empty?

      sorted = values.sort
      rank = (p * (sorted.length - 1)).round
      sorted[rank].to_i
    end
    private_class_method :percentile
  end
end
