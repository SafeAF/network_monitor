# frozen_string_literal: true

class DrilldownsController < ApplicationController
  ROW_LIMIT = 200

  def new_dst
    now = Time.current
    window = params[:window].presence || "10m"
    start_time = window_start(window, now)
    device = device_filter

    hosts = RemoteHost.where("first_seen_at >= ?", start_time)
    if device
      hosts = hosts.joins("INNER JOIN connections ON connections.dst_ip = remote_hosts.ip")
                   .where("connections.src_ip = ?", device.ip)
    end
    hosts = hosts.order(first_seen_at: :desc)
                 .limit(ROW_LIMIT + 1)

    limited = hosts.length > ROW_LIMIT
    hosts = hosts.first(ROW_LIMIT)

    rows = hosts.map do |host|
      conn = Connection.where(dst_ip: host.ip)
                       .yield_self { |scope| device ? scope.where(src_ip: device.ip) : scope }
                       .order(last_seen_at: :desc)
                       .first
      device = Device.find_by(ip: conn&.src_ip)
      {
        timestamp: host.first_seen_at&.iso8601,
        device: device&.name.presence || conn&.src_ip,
        proto: conn&.proto,
        dst_ip: host.ip,
        dst_port: conn&.dst_port,
        bytes: conn ? (conn.uplink_bytes + conn.downlink_bytes) : 0,
        reason: "NEW_DST"
      }
    end

    render json: { window: window, generated_at: now.iso8601, limited: limited, rows: rows }
  end

  def unique_ports
    now = Time.current
    window = params[:window].presence || "10m"
    start_time = window_start(window, now)
    device = device_filter

    ports_scope = Connection.where("last_seen_at >= ?", start_time)
                            .where.not(dst_port: nil)
    ports_scope = ports_scope.where(src_ip: device.ip) if device

    ports = ports_scope.group(:dst_port)
                       .order(Arel.sql("COUNT(*) DESC"))
                       .limit(ROW_LIMIT + 1)
                       .pluck(:dst_port, Arel.sql("COUNT(*)"), Arel.sql("MIN(last_seen_at)"), Arel.sql("MAX(last_seen_at)"))

    limited = ports.length > ROW_LIMIT
    ports = ports.first(ROW_LIMIT)

    rows = ports.map do |port, count, first_seen_at, last_seen_at|
      conn = Connection.where("last_seen_at >= ?", start_time)
                       .where(dst_port: port)
                       .yield_self { |scope| device ? scope.where(src_ip: device.ip) : scope }
                       .order(last_seen_at: :desc)
                       .first
      device = Device.find_by(ip: conn&.src_ip)
      ips = Connection.where("last_seen_at >= ?", start_time)
                      .where(dst_port: port)
                      .yield_self { |scope| device ? scope.where(src_ip: device.ip) : scope }
                      .distinct
                      .limit(50)
                      .pluck(:dst_ip)
      {
        timestamp: conn&.last_seen_at&.iso8601,
        device: device&.name.presence || conn&.src_ip,
        proto: conn&.proto,
        dst_ip: conn&.dst_ip,
        dst_port: port,
        bytes: conn ? (conn.uplink_bytes + conn.downlink_bytes) : 0,
        reason: "UNIQUE_PORT",
        count: count,
        ips: ips,
        first_seen_at: first_seen_at&.iso8601,
        last_seen_at: last_seen_at&.iso8601
      }
    end

    render json: { window: window, generated_at: now.iso8601, limited: limited, rows: rows }
  end

  def new_asns
    now = Time.current
    window = params[:window].presence || "1h"
    start_time = window_start(window, now)
    device = device_filter

    hosts = RemoteHost.where("first_seen_at >= ?", start_time)
                      .where.not(whois_asn: nil)
    if device
      hosts = hosts.joins("INNER JOIN connections ON connections.dst_ip = remote_hosts.ip")
                   .where("connections.src_ip = ?", device.ip)
    end
    hosts = hosts.order(first_seen_at: :desc)
                 .limit(ROW_LIMIT + 1)

    limited = hosts.length > ROW_LIMIT
    hosts = hosts.first(ROW_LIMIT)

    rows = hosts.map do |host|
      conn = Connection.where(dst_ip: host.ip)
                       .yield_self { |scope| device ? scope.where(src_ip: device.ip) : scope }
                       .order(last_seen_at: :desc)
                       .first
      device = Device.find_by(ip: conn&.src_ip)
      {
        timestamp: host.first_seen_at&.iso8601,
        device: device&.name.presence || conn&.src_ip,
        proto: conn&.proto,
        dst_ip: host.ip,
        dst_port: conn&.dst_port,
        bytes: conn ? (conn.uplink_bytes + conn.downlink_bytes) : 0,
        reason: "NEW_ASN",
        asn: host.whois_asn
      }
    end

    render json: { window: window, generated_at: now.iso8601, limited: limited, rows: rows }
  end

  def rare_ports
    now = Time.current
    window = params[:window].presence || "24h"
    start_time = window_start(window, now)
    device = device_filter
    common_ports = Array(load_config["common_ports"].presence || [53, 80, 123, 443]).map(&:to_i)

    ports_scope = Connection.where("last_seen_at >= ?", start_time)
                            .where.not(dst_port: nil)
                            .where.not(dst_port: common_ports)
    ports_scope = ports_scope.where(src_ip: device.ip) if device
    ports = ports_scope.group(:dst_port)
                       .order(Arel.sql("COUNT(*) DESC"))
                       .limit(ROW_LIMIT + 1)
                       .pluck(:dst_port, Arel.sql("COUNT(*)"), Arel.sql("MIN(last_seen_at)"), Arel.sql("MAX(last_seen_at)"))

    limited = ports.length > ROW_LIMIT
    ports = ports.first(ROW_LIMIT)

    rows = ports.map do |port, count, first_seen_at, last_seen_at|
      conn = Connection.where("last_seen_at >= ?", start_time)
                       .where(dst_port: port)
                       .yield_self { |scope| device ? scope.where(src_ip: device.ip) : scope }
                       .order(last_seen_at: :desc)
                       .first
      device = Device.find_by(ip: conn&.src_ip)
      ips = Connection.where("last_seen_at >= ?", start_time)
                      .where(dst_port: port)
                      .yield_self { |scope| device ? scope.where(src_ip: device.ip) : scope }
                      .distinct
                      .limit(50)
                      .pluck(:dst_ip)
      {
        timestamp: conn&.last_seen_at&.iso8601,
        device: device&.name.presence || conn&.src_ip,
        proto: conn&.proto,
        dst_ip: conn&.dst_ip,
        dst_port: port,
        bytes: conn ? (conn.uplink_bytes + conn.downlink_bytes) : 0,
        reason: "RARE_PORT",
        count: count,
        ips: ips,
        first_seen_at: first_seen_at&.iso8601,
        last_seen_at: last_seen_at&.iso8601
      }
    end

    render json: { window: window, generated_at: now.iso8601, limited: limited, rows: rows }
  end

  private

  def window_start(window, now)
    case window
    when "10m" then now - 10.minutes
    when "1h" then now - 1.hour
    when "24h" then now - 24.hours
    when "7d", "1w" then now - 7.days
    else now - 10.minutes
    end
  end

  def device_filter
    return nil if params[:device_id].blank?

    Device.find_by(id: params[:device_id])
  end

  def load_config
    path = Rails.root.join("config/netmon.yml")
    YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false) || {}
  rescue Errno::ENOENT
    {}
  end
end
