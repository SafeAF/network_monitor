# frozen_string_literal: true

require "set"
require "yaml"

module Netmon
  class ReconcileSnapshot
    Result = Struct.new(:remote_hosts_upserted, :connections_upserted, :connections_deleted, keyword_init: true)

    def self.run(input_file: ENV["CONNTRACK_INPUT_FILE"], now: Time.current, enricher: Netmon::HostEnricher)
      config = load_config
      common_ports = Array(config["common_ports"].presence || [53, 80, 123, 443]).map(&:to_i)
      new_window_seconds = (config["new_window_seconds"].presence || 600).to_i
      bucket_ts = now.utc.change(sec: 0)

      entries = Conntrack::Snapshot.read(input_file:)
      outbound = entries.select { |entry| Netmon::Filter.outbound?(entry) }

      seen_connection_ids = []
      remote_hosts_upserted = 0
      connections_upserted = 0
      device_minutes = {}
      remote_minutes = {}
      device_stats = Hash.new do |hash, key|
        hash[key] = {
          dst_ips: Set.new,
          dst_ports: Set.new,
          dst_asns: Set.new,
          protos: Set.new,
          rare_ports: Set.new,
          new_dst_ips: Set.new
        }
      end

      outbound.each do |entry|
        orig = entry.orig
        reply = entry.reply

        device = Device.find_or_initialize_by(ip: orig.src)
        if device.new_record?
          device.first_seen_at = now
          device.name = orig.src if device.name.to_s.strip.empty?
        end
        device.last_seen_at = now
        device.save!

        remote_host = RemoteHost.find_or_initialize_by(ip: orig.dst)
        if remote_host.new_record?
          remote_host.first_seen_at = now
          remote_hosts_upserted += 1
        end
        remote_host.last_seen_at = now
        enricher.apply(remote_host, now:)
        remote_host.save!

        connection = Connection.find_or_initialize_by(
          proto: entry.proto,
          src_ip: orig.src,
          src_port: orig.sport,
          dst_ip: orig.dst,
          dst_port: orig.dport
        )

        if connection.new_record?
          connection.first_seen_at = now
          connections_upserted += 1
        end

        cur_up_b = orig.bytes.to_i
        cur_dn_b = reply&.bytes.to_i
        cur_up_p = orig.packets.to_i
        cur_dn_p = reply&.packets.to_i

        deltas = compute_deltas(connection, cur_up_b:, cur_dn_b:, cur_up_p:, cur_dn_p:)

        device_minute = device_minutes[device.id] ||=
          DeviceMinute.find_or_initialize_by(device_id: device.id, bucket_ts:)
        device_minute.conn_count += 1
        device_minute.uplink_bytes += deltas[:d_up_b]
        device_minute.downlink_bytes += deltas[:d_dn_b]
        device_minute.uplink_packets += deltas[:d_up_p]
        device_minute.downlink_packets += deltas[:d_dn_p]

        remote_minute = remote_minutes[remote_host.id] ||=
          RemoteHostMinute.find_or_initialize_by(remote_host_id: remote_host.id, bucket_ts:)
        remote_minute.conn_count += 1
        remote_minute.uplink_bytes += deltas[:d_up_b]
        remote_minute.downlink_bytes += deltas[:d_dn_b]
        remote_minute.uplink_packets += deltas[:d_up_p]
        remote_minute.downlink_packets += deltas[:d_dn_p]

        stats = device_stats[device.id]
        stats[:dst_ips] << orig.dst
        stats[:dst_ports] << orig.dport if orig.dport
        stats[:protos] << entry.proto if entry.proto
        asn_or_org = remote_host.whois_asn.presence || remote_host.whois_name.presence
        stats[:dst_asns] << asn_or_org if asn_or_org
        if orig.dport && !common_ports.include?(orig.dport.to_i)
          stats[:rare_ports] << orig.dport.to_i
        end
        if remote_host.first_seen_at && remote_host.first_seen_at >= now - new_window_seconds
          stats[:new_dst_ips] << orig.dst
        end

        connection.state = entry.state
        connection.flags = Array(entry.flags).join(",")
        connection.uplink_packets = cur_up_p
        connection.uplink_bytes = cur_up_b
        connection.downlink_packets = cur_dn_p
        connection.downlink_bytes = cur_dn_b
        connection.last_uplink_packets = cur_up_p
        connection.last_uplink_bytes = cur_up_b
        connection.last_downlink_packets = cur_dn_p
        connection.last_downlink_bytes = cur_dn_b
        connection.last_delta_at = now
        connection.last_seen_at = now
        connection.save!

        seen_connection_ids << connection.id
      end

      device_minutes.each do |device_id, row|
        stats = device_stats[device_id]
        row.unique_dst_ips = stats[:dst_ips].size
        row.unique_dst_ports = stats[:dst_ports].size
        row.unique_dst_asns = stats[:dst_asns].size
        row.unique_protos = stats[:protos].size
        row.rare_ports = stats[:rare_ports].size
        row.new_dst_ips = stats[:new_dst_ips].size
        row.save!
      end

      remote_minutes.each_value(&:save!)

      connections_deleted = if seen_connection_ids.empty?
                              Connection.delete_all
                            else
                              Connection.where.not(id: seen_connection_ids).delete_all
                            end

      Result.new(
        remote_hosts_upserted:,
        connections_upserted:,
        connections_deleted:
      )
    end

    def self.load_config
      path = Rails.root.join("config/netmon.yml")
      YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false) || {}
    rescue Errno::ENOENT
      {}
    end
    private_class_method :load_config

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
