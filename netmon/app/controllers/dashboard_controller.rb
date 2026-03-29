# frozen_string_literal: true

require "yaml"

class DashboardController < ApplicationController
  TOP_PANELS_CACHE_TTL = 15.seconds
  TOP_PANELS_DEFAULT_WINDOWS = {
    top_remote_window: "10m",
    newest_window: "10m",
    rare_window: "24h",
    top_devices_window: "10m"
  }.freeze

  def index
    @connections, @new_threshold = Netmon::ConnectionsQuery.call(params)
    @hosts_by_ip = RemoteHost.where(ip: @connections.map(&:dst_ip).uniq).index_by(&:ip)
    @devices_by_ip = Device.where(ip: @connections.map(&:src_ip).uniq).index_by(&:ip)

    top_panels = top_panels_payload(now: Time.current, windows: panel_windows)
    @top_remote_hosts = top_panels[:top_remote_hosts]
    @newest_remote_hosts = top_panels[:newest_remote_hosts]
    @rare_ports = top_panels[:rare_ports]
    @top_devices_egress = top_panels[:top_devices_egress]
  end

  def top_panels
    render json: top_panels_payload(now: Time.current, windows: panel_windows)
  end

  def load_config
    path = Rails.root.join("config/netmon.yml")
    YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false) || {}
  rescue Errno::ENOENT
    {}
  end
  private :load_config

  def panel_windows
    TOP_PANELS_DEFAULT_WINDOWS.each_with_object({}) do |(key, default), windows|
      windows[key] = params[key].presence || default
    end
  end
  private :panel_windows

  def top_panels_payload(now:, windows:)
    Rails.cache.fetch(top_panels_cache_key(windows), expires_in: TOP_PANELS_CACHE_TTL) do
      {
        top_remote_hosts: top_remote_hosts(window: windows[:top_remote_window], now:),
        newest_remote_hosts: newest_remote_hosts(now:, window: windows[:newest_window]),
        rare_ports: rare_ports(window: windows[:rare_window], now:),
        top_devices_egress: top_devices_egress(window: windows[:top_devices_window], now:),
        recent_incidents: recent_incidents(now:)
      }
    end
  end
  private :top_panels_payload

  def top_panels_cache_key(windows)
    [
      "dashboard",
      "top_panels",
      windows[:top_remote_window],
      windows[:newest_window],
      windows[:rare_window],
      windows[:top_devices_window]
    ].join(":")
  end
  private :top_panels_cache_key

  def top_remote_hosts(window:, now:)
    total_bytes_sql = "SUM(remote_host_minutes.uplink_bytes + remote_host_minutes.downlink_bytes)"

    RemoteHostMinute.joins(:remote_host)
                    .where("remote_host_minutes.bucket_ts >= ?", window_start(window, now))
                    .group("remote_host_minutes.remote_host_id", "remote_hosts.ip")
                    .order(Arel.sql("#{total_bytes_sql} DESC"))
                    .limit(5)
                    .pluck("remote_hosts.ip", Arel.sql(total_bytes_sql))
                    .map do |ip, total_bytes|
                      { ip: ip, total_bytes: total_bytes.to_i }
                    end
  end
  private :top_remote_hosts

  def rare_ports(window:, now:)
    start_time = window_start(window, now)

    Connection.where("last_seen_at >= ?", start_time)
              .where.not(dst_port: nil)
              .where.not(dst_port: common_ports)
              .group(:dst_port)
              .order(Arel.sql("COUNT(*) DESC"))
              .limit(5)
              .count
              .map do |port, count|
                ips = Connection.where("last_seen_at >= ?", start_time)
                                .where(dst_port: port)
                                .distinct
                                .limit(3)
                                .pluck(:dst_ip)
                { port: port, count: count, ips: ips }
              end
  end
  private :rare_ports

  def top_devices_egress(window:, now:)
    total_uplink_sql = "SUM(device_minutes.uplink_bytes)"

    DeviceMinute.joins(:device)
                .where("device_minutes.bucket_ts >= ?", window_start(window, now))
                .group("device_minutes.device_id", "devices.name", "devices.ip")
                .order(Arel.sql("#{total_uplink_sql} DESC"))
                .limit(5)
                .pluck("devices.name", "devices.ip", "device_minutes.device_id", Arel.sql(total_uplink_sql))
                .map do |name, ip, device_id, total_uplink|
                  { label: name.presence || ip || device_id, total_uplink: total_uplink.to_i }
                end
  end
  private :top_devices_egress

  def recent_incidents(now:)
    Incident.where("last_seen_at >= ?", now - 1.hour)
            .where(acknowledged_at: nil)
            .order(last_seen_at: :desc)
            .limit(10)
            .includes(:device)
            .map do |incident|
              device_label = incident.device&.name.presence || incident.device&.ip
              {
                id: incident.id,
                device: device_label,
                dst_ip: incident.dst_ip,
                dst_port: incident.dst_port,
                max_score: incident.max_score,
                codes: incident.codes_csv,
                count: incident.count,
                last_seen_at: incident.last_seen_at.iso8601
              }
            end
  end
  private :recent_incidents

  def common_ports
    @common_ports ||= Array(load_config["common_ports"].presence || [53, 80, 123, 443]).map(&:to_i)
  end
  private :common_ports

  def newest_remote_hosts(now:, window:)
    start_time = window_start(window, now)
    hosts = RemoteHost.where("first_seen_at >= ?", start_time)
                      .order(first_seen_at: :desc)
                      .limit(5)
    hosts.map do |host|
      port = Connection.where(dst_ip: host.ip)
                       .order(last_seen_at: :desc)
                       .limit(1)
                       .pick(:dst_port)
      { ip: host.ip, port: port }
    end
  end
  private :newest_remote_hosts

  def window_start(window, now)
    case window
    when "10m" then now - 10.minutes
    when "1h" then now - 1.hour
    when "24h" then now - 24.hours
    when "1w" then now - 7.days
    else now - 10.minutes
    end
  end
  private :window_start
end
