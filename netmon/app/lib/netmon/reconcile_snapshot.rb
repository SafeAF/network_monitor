# frozen_string_literal: true

module Netmon
  class ReconcileSnapshot
    Result = Struct.new(:remote_hosts_upserted, :connections_upserted, :connections_deleted, keyword_init: true)

    def self.run(input_file: ENV["CONNTRACK_INPUT_FILE"], now: Time.current, enricher: Netmon::HostEnricher)
      entries = Conntrack::Snapshot.read(input_file:)
      outbound = entries.select { |entry| Netmon::Filter.outbound?(entry) }

      seen_connection_ids = []
      remote_hosts_upserted = 0
      connections_upserted = 0

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
