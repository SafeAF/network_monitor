# frozen_string_literal: true

class ConnectionsController < ApplicationController
  def index
    threshold = Time.current - 60.seconds

    connections = Connection.order(Arel.sql("uplink_bytes + downlink_bytes DESC"))
    hosts = RemoteHost.where(ip: connections.map(&:dst_ip)).index_by(&:ip)

    payload = connections.map do |conn|
      host = hosts[conn.dst_ip]
      seen_before = host.present? && host.first_seen_at < threshold

      {
        proto: conn.proto,
        src_ip: conn.src_ip,
        src_port: conn.src_port,
        dst_ip: conn.dst_ip,
        dst_port: conn.dst_port,
        state: conn.state,
        flags: conn.flags,
        uplink_bytes: conn.uplink_bytes,
        downlink_bytes: conn.downlink_bytes,
        total_bytes: conn.uplink_bytes + conn.downlink_bytes,
        seen_before: seen_before
      }
    end

    render json: payload
  end
end
