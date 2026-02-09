# frozen_string_literal: true

require "yaml"

class DashboardController < ApplicationController
  def index
    @connections, @new_threshold = Netmon::ConnectionsQuery.call(params)
    @hosts_by_ip = RemoteHost.where(ip: @connections.map(&:dst_ip)).index_by(&:ip)
    @devices_by_ip = Device.where(ip: @connections.map(&:src_ip)).index_by(&:ip)
    now = Time.current
    common_ports = Array(load_config["common_ports"].presence || [53, 80, 123, 443]).map(&:to_i)

    @top_remote_hosts = RemoteHostMinute
                         .where("bucket_ts >= ?", now - 10.minutes)
                         .group(:remote_host_id)
                         .select("remote_host_id, SUM(uplink_bytes + downlink_bytes) AS total_bytes")
                         .order(Arel.sql("total_bytes DESC"))
                         .limit(5)
                         .map do |row|
                           host = RemoteHost.find_by(id: row.remote_host_id)
                           { ip: host&.ip || row.remote_host_id, total_bytes: row.total_bytes }
                         end

    @newest_remote_hosts = RemoteHost.where("first_seen_at >= ?", now - 10.minutes)
                                     .order(first_seen_at: :desc)
                                     .limit(5)

    @rare_ports = Connection.where("last_seen_at >= ?", now - 24.hours)
                            .where.not(dst_port: nil)
                            .where.not(dst_port: common_ports)
                            .group(:dst_port)
                            .order(Arel.sql("COUNT(*) DESC"))
                            .limit(5)
                            .count

    @top_devices_egress = DeviceMinute.where("bucket_ts >= ?", now - 10.minutes)
                                      .group(:device_id)
                                      .select("device_id, SUM(uplink_bytes) AS total_uplink")
                                      .order(Arel.sql("total_uplink DESC"))
                                      .limit(5)
                                      .map do |row|
                                        device = Device.find_by(id: row.device_id)
                                        label = device&.name.presence || device&.ip || row.device_id
                                        { label: label, total_uplink: row.total_uplink }
                                      end
  end

  def top_panels
    now = Time.current
    common_ports = Array(load_config["common_ports"].presence || [53, 80, 123, 443]).map(&:to_i)

    top_remote_hosts = RemoteHostMinute
                        .where("bucket_ts >= ?", now - 10.minutes)
                        .group(:remote_host_id)
                        .select("remote_host_id, SUM(uplink_bytes + downlink_bytes) AS total_bytes")
                        .order(Arel.sql("total_bytes DESC"))
                        .limit(5)
                        .map do |row|
                          host = RemoteHost.find_by(id: row.remote_host_id)
                          { ip: host&.ip || row.remote_host_id, total_bytes: row.total_bytes.to_i }
                        end

    newest_remote_hosts = RemoteHost.where("first_seen_at >= ?", now - 10.minutes)
                                     .order(first_seen_at: :desc)
                                     .limit(5)
                                     .pluck(:ip)

    rare_ports = Connection.where("last_seen_at >= ?", now - 24.hours)
                           .where.not(dst_port: nil)
                           .where.not(dst_port: common_ports)
                           .group(:dst_port)
                           .order(Arel.sql("COUNT(*) DESC"))
                           .limit(5)
                           .count
                           .map { |port, count| { port: port, count: count } }

    top_devices_egress = DeviceMinute.where("bucket_ts >= ?", now - 10.minutes)
                                     .group(:device_id)
                                     .select("device_id, SUM(uplink_bytes) AS total_uplink")
                                     .order(Arel.sql("total_uplink DESC"))
                                     .limit(5)
                                     .map do |row|
                                       device = Device.find_by(id: row.device_id)
                                       label = device&.name.presence || device&.ip || row.device_id
                                       { label: label, total_uplink: row.total_uplink.to_i }
                                     end

    render json: {
      top_remote_hosts: top_remote_hosts,
      newest_remote_hosts: newest_remote_hosts,
      rare_ports: rare_ports,
      top_devices_egress: top_devices_egress
    }
  end

  def load_config
    path = Rails.root.join("config/netmon.yml")
    YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false) || {}
  rescue Errno::ENOENT
    {}
  end
  private :load_config
end
