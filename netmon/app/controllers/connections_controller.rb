# frozen_string_literal: true

require "json"

class ConnectionsController < ApplicationController
  def index
    connections, threshold = Netmon::ConnectionsQuery.call(params)
    hosts = RemoteHost.where(ip: connections.map(&:dst_ip)).index_by(&:ip)
    devices = Device.where(ip: connections.map(&:src_ip)).index_by(&:ip)

    payload = connections.map do |conn|
      host = hosts[conn.dst_ip]
      device = devices[conn.src_ip]
      seen_before = host.present? && host.first_seen_at < threshold

      whois_raw_line = host&.respond_to?(:whois_raw_line) ? host.whois_raw_line : nil
      reasons = begin
        JSON.parse(conn.anomaly_reasons_json || "[]")
      rescue JSON::ParserError
        []
      end
      reason_codes = reasons.map { |reason| reason["code"] }.compact
      {
        device_id: device&.id,
        device_name: device&.name.presence || conn.src_ip,
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
        seen_before: seen_before,
        seen_age: host&.seen_age || "unknown",
        is_new: host&.new? || false,
        rdns_name: host&.rdns_name,
        whois_name: host&.whois_name,
        whois_raw_line: whois_raw_line,
        anomaly_score: conn.anomaly_score.to_i,
        anomaly_reasons: reason_codes
      }
    end

    render json: payload
  end
end
