# frozen_string_literal: true

require "yaml"

class SearchController < ApplicationController
  RESULTS_LIMIT = 200

  def index
    redirect_to "/search/hosts"
  end

  def hosts
    @filters = params.permit(
      :ip,
      :whois_name,
      :whois_asn,
      :rdns,
      :rdns_missing,
      :first_seen_within,
      :last_seen_within,
      :seen_port,
      :min_total_bytes_ever,
      :min_max_score_ever,
      :tag,
      :sort
    )

    base = RemoteHost.all

    if @filters[:ip].present?
      ip = @filters[:ip].to_s.strip
      if ip.include?("*")
        base = base.where("ip LIKE ?", ip.tr("*", "%"))
      elsif ip.include?("%")
        base = base.where("ip LIKE ?", ip)
      elsif ip.end_with?(".") || ip.count(".") < 3
        base = base.where("ip LIKE ?", "#{ip}%")
      else
        base = base.where(ip: ip)
      end
    end

    if @filters[:whois_name].present?
      base = base.where("whois_name LIKE ?", "%#{@filters[:whois_name]}%")
    end
    if @filters[:whois_asn].present?
      base = base.where("whois_asn LIKE ?", "%#{@filters[:whois_asn]}%")
    end
    if @filters[:rdns].present?
      base = base.where("rdns_name LIKE ?", "%#{@filters[:rdns]}%")
    end
    if @filters[:rdns_missing].to_s == "true"
      base = base.where("rdns_name IS NULL OR rdns_name = ''")
    end
    if @filters[:tag].present?
      base = base.where(tag: @filters[:tag])
    end

    if @filters[:first_seen_within].present?
      base = base.where("first_seen_at >= ?", window_start(@filters[:first_seen_within]))
    end
    if @filters[:last_seen_within].present?
      base = base.where("last_seen_at >= ?", window_start(@filters[:last_seen_within]))
    end

    if @filters[:seen_port].to_s.match?(/\A\d+\z/)
      base = base.joins(:remote_host_ports).where(remote_host_ports: { dst_port: @filters[:seen_port].to_i })
    end

    conn_stats = Connection.select("dst_ip, SUM(uplink_bytes + downlink_bytes) AS total_bytes, MAX(anomaly_score) AS max_score")
                           .group(:dst_ip)
    base = base.joins("LEFT JOIN (#{conn_stats.to_sql}) AS conn_stats ON conn_stats.dst_ip = remote_hosts.ip")

    if @filters[:min_total_bytes_ever].to_s.match?(/\A\d+\z/)
      base = base.where("COALESCE(conn_stats.total_bytes, 0) >= ?", @filters[:min_total_bytes_ever].to_i)
    end
    if @filters[:min_max_score_ever].to_s.match?(/\A\d+\z/)
      base = base.where("COALESCE(conn_stats.max_score, 0) >= ?", @filters[:min_max_score_ever].to_i)
    end

    sort = @filters[:sort].presence || "last_seen_desc"
    @page = [params[:page].to_i, 1].max
    @total = base.except(:select, :order).count
    @total_pages = (@total / RESULTS_LIMIT.to_f).ceil

    base = base.select("remote_hosts.*, conn_stats.total_bytes AS total_bytes, conn_stats.max_score AS max_score")

    @hosts = case sort
             when "first_seen_desc" then base.order(first_seen_at: :desc)
             when "max_total_bytes_desc" then base.order(Arel.sql("COALESCE(conn_stats.total_bytes, 0) DESC"))
             when "max_score_desc" then base.order(Arel.sql("COALESCE(conn_stats.max_score, 0) DESC"))
             else base.order(last_seen_at: :desc)
             end.limit(RESULTS_LIMIT).offset((@page - 1) * RESULTS_LIMIT)

    @saved_query_kind = "hosts"
    @saved_queries = SavedQuery.where(kind: @saved_query_kind).order(created_at: :desc)
  end

  def connections
    @filters = params.permit(
      :device,
      :src_ip,
      :dst_ip,
      :dst_port,
      :proto,
      :hide_time_wait,
      :min_score,
      :reason_contains,
      :only_new_dst,
      :sort
    )

    scope = Connection.all

    if @filters[:device].present?
      device = @filters[:device].to_s.strip
      scope = scope.joins("LEFT JOIN devices ON devices.ip = connections.src_ip")
                   .where("devices.name = ? OR devices.ip = ? OR connections.src_ip = ?", device, device, device)
    end

    scope = scope.where(src_ip: @filters[:src_ip]) if @filters[:src_ip].present?
    scope = scope.where(dst_ip: @filters[:dst_ip]) if @filters[:dst_ip].present?
    scope = scope.where(dst_port: @filters[:dst_port].to_i) if @filters[:dst_port].to_s.match?(/\A\d+\z/)
    scope = scope.where(proto: @filters[:proto]) if @filters[:proto].present?

    if @filters[:hide_time_wait].to_s == "true"
      scope = scope.where.not(state: "TIME_WAIT")
    end
    if @filters[:min_score].to_s.match?(/\A\d+\z/)
      scope = scope.where("anomaly_score >= ?", @filters[:min_score].to_i)
    end
    if @filters[:reason_contains].present?
      scope = scope.where("anomaly_reasons_json LIKE ?", "%#{@filters[:reason_contains]}%")
    end
    if @filters[:only_new_dst].to_s == "true"
      window = (load_config["new_window_seconds"].presence || 600).to_i
      scope = scope.joins("INNER JOIN remote_hosts ON remote_hosts.ip = connections.dst_ip")
                   .where("remote_hosts.first_seen_at >= ?", Time.current - window)
    end

    sort = @filters[:sort].presence || "score_desc"
    @page = [params[:page].to_i, 1].max
    @connections = case sort
                   when "total_bytes_desc"
                     scope.order(Arel.sql("uplink_bytes + downlink_bytes DESC"))
                   when "last_seen_desc"
                     scope.order(last_seen_at: :desc)
                   else
                     scope.order(anomaly_score: :desc)
                   end.limit(RESULTS_LIMIT).offset((@page - 1) * RESULTS_LIMIT)
    @total = scope.count
    @total_pages = (@total / RESULTS_LIMIT.to_f).ceil

    @saved_query_kind = "connections"
    @saved_queries = SavedQuery.where(kind: @saved_query_kind).order(created_at: :desc)
  end

  def anomalies
    @filters = params.permit(:device, :dst_ip, :dst_port, :min_score, :code, :window)
    scope = AnomalyHit.includes(:device, :remote_host)

    scope = scope.where("score >= ?", @filters[:min_score].to_i) if @filters[:min_score].to_s.match?(/\A\d+\z/)
    scope = scope.where(dst_ip: @filters[:dst_ip]) if @filters[:dst_ip].present?
    scope = scope.where(dst_port: @filters[:dst_port].to_i) if @filters[:dst_port].to_s.match?(/\A\d+\z/)
    if @filters[:device].present?
      device = @filters[:device].to_s
      scope = scope.joins(:device).where("devices.id = ? OR devices.ip = ? OR devices.name = ?", device, device, device)
    end
    scope = scope.where("reasons_json LIKE ?", "%#{@filters[:code]}%") if @filters[:code].present?
    scope = scope.where("occurred_at >= ?", window_start(@filters[:window])) if @filters[:window].present?

    @page = [params[:page].to_i, 1].max
    @hits = scope.order(occurred_at: :desc).limit(RESULTS_LIMIT).offset((@page - 1) * RESULTS_LIMIT)
    @total = scope.count
    @total_pages = (@total / RESULTS_LIMIT.to_f).ceil
    @saved_query_kind = "anomalies"
    @saved_queries = SavedQuery.where(kind: @saved_query_kind).order(created_at: :desc)
  end

  private

  def load_config
    path = Rails.root.join("config/netmon.yml")
    YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false) || {}
  rescue Errno::ENOENT
    {}
  end

  def window_start(value)
    case value
    when "1h" then Time.current - 1.hour
    when "24h" then Time.current - 24.hours
    when "7d" then Time.current - 7.days
    when "30d" then Time.current - 30.days
    else Time.current - 1.hour
    end
  end
end
