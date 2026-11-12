# frozen_string_literal: true

module Netmon
  class AgentIngest
    def self.ingest_event!(event_type:, router_id:, data:, ts:)
      RouterScope.authorize!(router_id)
      data = normalize_data(data)
      case event_type
      when "flow"
        Connection.transaction { ingest_flow!(router_id:, data:, ts:) }
      when "dns_response"
        Netmon::Dns::IngestEvent.call(router_id:, data:, ts:, strict: true)
      when "heartbeat", "firewall_drop"
        # Explicit raw-only types: receipt persistence is the full work.
      else
        # no-op for now
      end
    end

    def self.ingest_flow!(router_id:, data:, ts:)
      now = ts || Time.current
      # Match database timestamp precision when comparing reordered events.
      now = now.change(usec: now.usec)
      src_ip = data["src_ip"].to_s
      dst_ip = data["dst_ip"].to_s
      return if src_ip.empty? || dst_ip.empty?
      config = Anomaly::Scorer.configuration
      # Out-of-scope observations remain raw receipts, matching the snapshot
      # path's LAN-source/excluded-destination policy for normalized detections.
      return unless Filter.outbound_addresses?(src_ip, dst_ip, config: config)
      RouterScope.bind_flow_collector!(router_id, "agent")

      proto = normalize_proto(data["l4proto"])
      src_port = parse_nullable_int(data["src_port"])
      dst_port = parse_nullable_int(data["dst_port"])

      tuple = { proto: proto, src_ip: src_ip, src_port: src_port, dst_ip: dst_ip, dst_port: dst_port }
      connection = Connection.find_or_initialize_by(tuple)
      result = FlowLifetimes.apply!(router_id: router_id, tuple: tuple, data: data, now: now, connection: connection)
      return if result.accounting.stale
      lifetime = result.lifetime
      deltas = result.accounting.deltas
      count_delta = result.accounting.count_delta
      persist_projection = connection.new_record? || connection.last_delta_at.nil? || now > connection.last_delta_at ||
        (now == connection.last_delta_at && [nil, lifetime.flow_uid].include?(connection.agent_flow_uid))
      connection = Connection.new(tuple) unless persist_projection
      if connection.agent_flow_uid != lifetime.flow_uid
        connection.first_seen_at = lifetime.first_observed_at
        connection.last_domain = nil
        connection.last_domain_observed_at = nil
      end
      connection.agent_flow_uid = lifetime.flow_uid

      device = Device.find_or_initialize_by(ip: src_ip)
      if device.new_record?
        device.first_seen_at = now
        device.name = src_ip if device.name.to_s.strip.empty?
      end
      device.first_seen_at = [device.first_seen_at, now].compact.min
      device.last_seen_at = [device.last_seen_at, now].compact.max
      device.save!

      remote_host = RemoteHost.find_or_initialize_by(ip: dst_ip)
      if remote_host.new_record?
        remote_host.first_seen_at = now
      end
      remote_host.first_seen_at = [remote_host.first_seen_at, now].compact.min
      remote_host.last_seen_at = [remote_host.last_seen_at, now].compact.max
      enqueue_enrichment = Netmon::HostEnricher.due?(remote_host) &&
        (remote_host.enrichment_requested_at.nil? || remote_host.enrichment_requested_at < Time.current - 5.minutes)
      remote_host.enrichment_requested_at = Time.current if enqueue_enrichment
      remote_host.save!
      HostEnrichmentJob.perform_later(remote_host.id) if enqueue_enrichment

      connection.first_seen_at ||= lifetime.first_observed_at
      connection.uplink_packets = lifetime.packets_orig
      connection.uplink_bytes = lifetime.bytes_orig
      connection.downlink_packets = lifetime.packets_reply
      connection.downlink_bytes = lifetime.bytes_reply
      connection.last_uplink_packets = lifetime.packets_orig
      connection.last_uplink_bytes = lifetime.bytes_orig
      connection.last_downlink_packets = lifetime.packets_reply
      connection.last_downlink_bytes = lifetime.bytes_reply
      connection.last_delta_at = now
      connection.last_seen_at = now

      state = lifetime.closed_at ? "DESTROY" : normalize_state(data["state"] || data["event"])
      flags = normalize_flags(data["flags"] || data["dir"])
      connection.state = state if state
      connection.flags = flags if flags

      dns_match = nil
      if refresh_dns_match?(connection, now: now)
        dns_match = Netmon::Dns::CorrelateConnection.call(connection: connection, router_id: router_id, now: now)
        connection.last_domain = dns_match&.dig(:domain)
        connection.last_domain_observed_at = dns_match&.dig(:observed_at)
      end

      connection.save! if persist_projection

      if dns_match
        Netmon::Dns::LinkRemoteHostDomain.call(
          remote_host: remote_host,
          domain: dns_match[:domain],
          device_ip: src_ip,
          seen_at: dns_match[:observed_at],
          strict: true
        )
      end

      bucket_ts = now.utc.change(sec: 0)
      device_minute = DeviceMinute.find_or_initialize_by(device_id: device.id, bucket_ts: bucket_ts)
      device_minute.conn_count += count_delta
      device_minute.uplink_bytes += deltas.fetch("bytes_orig")
      device_minute.downlink_bytes += deltas.fetch("bytes_reply")
      device_minute.uplink_packets += deltas.fetch("packets_orig")
      device_minute.downlink_packets += deltas.fetch("packets_reply")
      device_minute.save!

      remote_minute = RemoteHostMinute.find_or_initialize_by(remote_host_id: remote_host.id, bucket_ts: bucket_ts)
      remote_minute.conn_count += count_delta
      remote_minute.uplink_bytes += deltas.fetch("bytes_orig")
      remote_minute.downlink_bytes += deltas.fetch("bytes_reply")
      remote_minute.uplink_packets += deltas.fetch("packets_orig")
      remote_minute.downlink_packets += deltas.fetch("packets_reply")
      remote_minute.save!

      if dst_port
        host_port = RemoteHostPort.find_or_initialize_by(remote_host_id: remote_host.id, dst_port: dst_port)
        host_port.first_seen_at ||= now
        host_port.last_seen_at = [host_port.last_seen_at, now].compact.max
        host_port.seen_count = host_port.seen_count.to_i + count_delta
        host_port.save!
      end
      Anomaly::Detection.call(connection: connection, device: device, remote_host: remote_host, now: now, config: config,
        persist_score: persist_projection)
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

    def self.parse_nullable_int(value)
      return nil if value.nil? || value == ""

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :parse_nullable_int

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

    def self.refresh_dns_match?(connection, now:)
      observed = connection.last_domain_observed_at
      connection.last_domain.to_s.strip.empty? || observed.nil? ||
        !observed.between?(now - Dns::CorrelateConnection::DEFAULT_WINDOW, now)
    end
    private_class_method :refresh_dns_match?

  end
end
