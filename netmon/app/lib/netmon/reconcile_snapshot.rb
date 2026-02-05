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

        connection.state = entry.state
        connection.flags = Array(entry.flags).join(",")
        connection.uplink_packets = orig.packets.to_i
        connection.uplink_bytes = orig.bytes.to_i
        connection.downlink_packets = reply&.packets.to_i
        connection.downlink_bytes = reply&.bytes.to_i
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
  end
end
