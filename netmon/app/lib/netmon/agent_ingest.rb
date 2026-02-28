# frozen_string_literal: true

module Netmon
  class AgentIngest
    def self.ingest_event!(event_type:, router_id:, data:, ts:)
      data = normalize_data(data)
      case event_type
      when "flow"
        ingest_flow!(router_id:, data:, ts:)
      when "heartbeat"
        # collector heartbeat only
      else
        # no-op for now
      end
    end

    def self.ingest_flow!(router_id:, data:, ts:)
      now = ts || Time.current
      src_ip = data["src_ip"].to_s
      dst_ip = data["dst_ip"].to_s
      return if src_ip.empty? || dst_ip.empty?

      proto = normalize_proto(data["l4proto"])
      src_port = parse_nullable_int(data["src_port"])
      dst_port = parse_nullable_int(data["dst_port"])

      device = Device.find_or_initialize_by(ip: src_ip)
      if device.new_record?
        device.first_seen_at = now
        device.name = src_ip if device.name.to_s.strip.empty?
      end
      device.last_seen_at = now
      device.save!

      remote_host = RemoteHost.find_or_initialize_by(ip: dst_ip)
      if remote_host.new_record?
        remote_host.first_seen_at = now
      end
      remote_host.last_seen_at = now
      Netmon::HostEnricher.apply(remote_host, now:)
      remote_host.save!

      connection = Connection.find_or_initialize_by(
        proto: proto,
        src_ip: src_ip,
        src_port: src_port,
        dst_ip: dst_ip,
        dst_port: dst_port
      )

      if connection.new_record?
        connection.first_seen_at = parse_time(data["first_seen"]) || now
      end

      cur_up_b = parse_int(data["bytes_orig"])
      cur_dn_b = parse_int(data["bytes_reply"])
      cur_up_p = parse_int(data["packets_orig"])
      cur_dn_p = parse_int(data["packets_reply"])

      deltas = compute_deltas(connection, cur_up_b:, cur_dn_b:, cur_up_p:, cur_dn_p:)

      connection.uplink_packets = cur_up_p
      connection.uplink_bytes = cur_up_b
      connection.downlink_packets = cur_dn_p
      connection.downlink_bytes = cur_dn_b
      connection.last_uplink_packets = cur_up_p
      connection.last_uplink_bytes = cur_up_b
      connection.last_downlink_packets = cur_dn_p
      connection.last_downlink_bytes = cur_dn_b
      connection.last_delta_at = now
      connection.last_seen_at = parse_time(data["last_seen"]) || now

      state = normalize_state(data["state"] || data["event"])
      flags = normalize_flags(data["flags"] || data["dir"])
      connection.state = state if state
      connection.flags = flags if flags

      baseline = DeviceBaseline.find_by(device_id: device.id)
      stats = Netmon::Anomaly::DeviceStats.current(device.id, now: now)
      anomaly = Netmon::Anomaly::Scorer.score_connection(
        connection: connection,
        device: device,
        remote_host: remote_host,
        baseline: baseline,
        device_stats: stats,
        now: now
      )
      connection.anomaly_score = anomaly[:score]
      connection.anomaly_reasons_json = anomaly[:reasons].to_json
      connection.save!

      bucket_ts = now.utc.change(sec: 0)
      device_minute = DeviceMinute.find_or_initialize_by(device_id: device.id, bucket_ts: bucket_ts)
      device_minute.conn_count += 1
      device_minute.uplink_bytes += deltas[:d_up_b]
      device_minute.downlink_bytes += deltas[:d_dn_b]
      device_minute.uplink_packets += deltas[:d_up_p]
      device_minute.downlink_packets += deltas[:d_dn_p]
      device_minute.save!

      remote_minute = RemoteHostMinute.find_or_initialize_by(remote_host_id: remote_host.id, bucket_ts: bucket_ts)
      remote_minute.conn_count += 1
      remote_minute.uplink_bytes += deltas[:d_up_b]
      remote_minute.downlink_bytes += deltas[:d_dn_b]
      remote_minute.uplink_packets += deltas[:d_up_p]
      remote_minute.downlink_packets += deltas[:d_dn_p]
      remote_minute.save!

      if dst_port
        host_port = RemoteHostPort.find_or_initialize_by(remote_host_id: remote_host.id, dst_port: dst_port)
        host_port.first_seen_at ||= now
        host_port.last_seen_at = now
        if connection.previous_changes.key?("id") || deltas.values.any?(&:positive?)
          host_port.seen_count = host_port.seen_count.to_i + 1
        end
        host_port.save!
      end
    end

    def self.normalize_proto(value)
      case value.to_i
      when 6
        "tcp"
      when 17
        "udp"
      else
        value.to_s.presence || "unknown"
      end
    end
    private_class_method :normalize_proto

    def self.normalize_state(value)
      return nil if value.blank?

      value.to_s.gsub(/\AEvent/i, "").upcase
    end
    private_class_method :normalize_state

    def self.normalize_flags(value)
      return nil if value.blank?

      value.to_s.upcase
    end
    private_class_method :normalize_flags

    def self.parse_int(value)
      Integer(value)
    rescue ArgumentError, TypeError
      0
    end
    private_class_method :parse_int

    def self.parse_nullable_int(value)
      return nil if value.nil? || value == ""

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :parse_nullable_int

    def self.parse_time(value)
      return nil if value.blank?

      Time.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :parse_time

    def self.normalize_data(data)
      return {} if data.nil?
      if data.respond_to?(:to_unsafe_h)
        data = data.to_unsafe_h
      elsif data.respond_to?(:to_h)
        data = data.to_h
      end
      data = data.transform_keys(&:to_s) if data.is_a?(Hash)
      data
    rescue StandardError
      {}
    end
    private_class_method :normalize_data

    def self.compute_deltas(connection, cur_up_b:, cur_dn_b:, cur_up_p:, cur_dn_p:)
      if connection.new_record?
        return { d_up_b: 0, d_dn_b: 0, d_up_p: 0, d_dn_p: 0 }
      end

      {
        d_up_b: [cur_up_b - connection.last_uplink_bytes.to_i, 0].max,
        d_dn_b: [cur_dn_b - connection.last_downlink_bytes.to_i, 0].max,
        d_up_p: [cur_up_p - connection.last_uplink_packets.to_i, 0].max,
        d_dn_p: [cur_dn_p - connection.last_downlink_packets.to_i, 0].max
      }
    end
    private_class_method :compute_deltas
  end
end
