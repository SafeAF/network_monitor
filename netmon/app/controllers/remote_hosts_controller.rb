# frozen_string_literal: true

class RemoteHostsController < ApplicationController
  PER_PAGE = 50

  def index
    @window = params[:window].presence || "10m"
    @page = [params[:page].to_i, 1].max
    start_time = window_start(@window)

    scope = RemoteHost.where("first_seen_at >= ?", start_time).order(first_seen_at: :desc)
    @total = scope.count
    @total_pages = (@total / PER_PAGE.to_f).ceil
    @hosts = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
  end

  def show
    @ip = params[:ip]
    @host = RemoteHost.find_by(ip: @ip)
    @connections = Connection.where(dst_ip: @ip)
    @ports = @connections.where.not(dst_port: nil).distinct.order(:dst_port).pluck(:dst_port)
    @port_history = if @host
                      RemoteHostPort.where(remote_host_id: @host.id).order(:dst_port)
                    else
                      []
                    end
    @traffic = @connections.sum("uplink_bytes + downlink_bytes")
    @first_seen = @host&.first_seen_at || @connections.minimum(:first_seen_at)
    @last_seen = @host&.last_seen_at || @connections.maximum(:last_seen_at)
    @rdns = @host&.rdns_name
    @whois = @host&.whois_name
    @whois_raw = @host&.respond_to?(:whois_raw_line) ? @host.whois_raw_line : nil
    @geo = geo_lookup(@ip)
  end

  def traceroute
    ip = params[:ip]
    key = traceroute_cache_key(ip)
    payload = Rails.cache.read(key)

    if params[:cancel].present?
      Rails.cache.write(key, { status: "cancelled", output: nil, updated_at: Time.current.to_i })
    elsif params[:start].present? && (payload.nil? || payload[:status] == "error" || payload[:status] == "done")
      Rails.cache.write(key, { status: "queued", output: nil, updated_at: Time.current.to_i })
      TracerouteJob.perform_later(ip)
    end

    payload = Rails.cache.read(key) || { status: "idle", output: nil, updated_at: nil }
    render json: payload
  end

  private

  def window_start(window)
    case window
    when "10m" then Time.current - 10.minutes
    when "1h" then Time.current - 1.hour
    when "24h" then Time.current - 24.hours
    when "1w" then Time.current - 7.days
    else Time.current - 10.minutes
    end
  end

  def geo_lookup(ip)
    stdout = run_cmd(["geoiplookup", ip], timeout: 4)
    return nil if stdout.nil?

    stdout.strip
  end

  def run_cmd(command, timeout:)
    require "open3"
    require "timeout"

    output = nil
    Timeout.timeout(timeout) do
      stdout, status = Open3.capture2e(*command)
      output = status.success? ? stdout : stdout
    end
    output
  rescue Errno::ENOENT, Timeout::Error
    nil
  end

  def traceroute_cache_key(ip)
    "traceroute:#{ip}"
  end

  private :geo_lookup, :run_cmd, :traceroute_cache_key
end
