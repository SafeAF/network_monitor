# frozen_string_literal: true

class RemoteHostsController < ApplicationController
  PER_PAGE = 50
  before_action :validate_probe_target!, only: [:traceroute, :start_traceroute, :cancel_traceroute]

  def index
    @window = params[:window].presence || "10m"
    @page = [params[:page].to_i, 1].max
    start_time = window_start(@window)

    scope = RemoteHost.where("first_seen_at >= ?", start_time)
    sort = params[:sort].to_s
    dir = params[:dir].to_s == "asc" ? :asc : :desc
    scope = case sort
            when "first_seen_at" then scope.order(first_seen_at: dir)
            when "last_seen_at" then scope.order(last_seen_at: dir)
            when "whois_name" then scope.order(Arel.sql("COALESCE(whois_name, '') #{dir.to_s.upcase}"))
            when "tag" then scope.order(Arel.sql("COALESCE(tag, '') #{dir.to_s.upcase}"))
            else scope.order(first_seen_at: :desc)
            end
    @total = scope.count
    @total_pages = (@total / PER_PAGE.to_f).ceil
    @hosts = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
  end

  def show
    @ip = params[:ip]
    @host = RemoteHost.find_by(ip: @ip)
    @connections = Connection.where(dst_ip: @ip).order(last_seen_at: :desc).limit(200)
    @ports = @connections.where.not(dst_port: nil).distinct.order(:dst_port).pluck(:dst_port)
    @port_history = if @host
                      RemoteHostPort.where(remote_host_id: @host.id).order(:dst_port)
                    else
                      []
                    end
    traffic_scope = Connection.where(dst_ip: @ip)
    if @host
      minutes_total = RemoteHostMinute.where(remote_host_id: @host.id)
                                      .sum("uplink_bytes + downlink_bytes")
      @traffic = minutes_total
      @first_seen = @host.first_seen_at
      @last_seen = @host.last_seen_at
    else
      @traffic = traffic_scope.sum("uplink_bytes + downlink_bytes")
      @first_seen = traffic_scope.minimum(:first_seen_at)
      @last_seen = traffic_scope.maximum(:last_seen_at)
    end
    @rdns = @host&.rdns_name
    @whois = @host&.whois_name
    @whois_raw = @host&.respond_to?(:whois_raw_line) ? @host.whois_raw_line : nil
    @recent_domains = if @host
                        RemoteHostDomain.where(remote_host_id: @host.id)
                                        .order(last_seen_at: :desc)
                                        .limit(50)
                      else
                        []
                      end
    @geo = geo_lookup(@ip) if Netmon::ProbeTarget.parse(@ip)
  end

  def update
    @host = RemoteHost.find_by!(ip: params[:ip])
    @host.update!(host_params)
    redirect_to "/remote_hosts/#{@host.ip}"
  end

  def traceroute
    render json: Rails.cache.read(traceroute_cache_key(@probe_ip)) || { status: "idle", output: nil, updated_at: nil }
  end

  def start_traceroute
    key = traceroute_cache_key(@probe_ip)
    payload = Rails.cache.read(key)
    if payload && %w[queued running].include?(payload[:status])
      render json: payload, status: :conflict
      return
    end

    run_id = SecureRandom.uuid
    payload = { status: "queued", run_id: run_id, output: nil, updated_at: Time.current.to_i }
    Rails.cache.write(key, payload, expires_in: 5.minutes)
    TracerouteJob.perform_later(@probe_ip, run_id)
    render json: payload, status: :accepted
  end

  def cancel_traceroute
    key = traceroute_cache_key(@probe_ip)
    payload = Rails.cache.read(key)
    if payload && %w[queued running].include?(payload[:status])
      Rails.cache.write("traceroute:cancelled:#{payload[:run_id]}", true, expires_in: 5.minutes)
      payload = payload.merge(status: "cancelled", updated_at: Time.current.to_i)
      Rails.cache.write(key, payload, expires_in: 5.minutes)
    end
    render json: payload || { status: "idle", output: nil, updated_at: nil }
  end

  private

  def validate_probe_target!
    @probe_ip = Netmon::ProbeTarget.parse(params[:ip])
    head :unprocessable_entity and return unless @probe_ip
    # Probe only literal addresses already observed by the monitor. Private LAN
    # addresses are intentional; arbitrary hostnames and local metadata are not.
    head :not_found unless RemoteHost.exists?(ip: @probe_ip)
  end

  def host_params
    params.require(:remote_host).permit(:notes, :tag)
  end

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
    Rails.cache.fetch("geoip:#{ip}", expires_in: 24.hours) do
      stdout = run_cmd(["geoiplookup", ip], timeout: 1)
      stdout&.strip
    end
  end

  def run_cmd(command, timeout:)
    Netmon::BoundedCommand.capture(*command, timeout: timeout)
  end

  def traceroute_cache_key(ip)
    "traceroute:#{ip}"
  end

  private :geo_lookup, :run_cmd, :traceroute_cache_key
end
