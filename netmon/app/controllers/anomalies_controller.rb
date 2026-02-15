# frozen_string_literal: true

class AnomaliesController < ApplicationController
  RESULTS_LIMIT = 100

  def index
    @filters = filter_params
    scope = AnomalyHit.includes(:device, :remote_host, :incident)

    if @filters[:min_score].present?
      scope = scope.where("score >= ?", @filters[:min_score].to_i)
    end

    if @filters[:dst_ip].present?
      scope = scope.where(dst_ip: @filters[:dst_ip])
    end

    if @filters[:dst_port].present? && @filters[:dst_port].to_s.match?(/\A\d+\z/)
      scope = scope.where(dst_port: @filters[:dst_port].to_i)
    end

    if @filters[:device].present?
      scope = scope.joins(:device).where("devices.id = ? OR devices.ip = ? OR devices.name = ?",
                                         @filters[:device],
                                         @filters[:device],
                                         @filters[:device])
    end

    if @filters[:code].present?
      scope = scope.where("reasons_json LIKE ?", "%#{@filters[:code]}%")
    end

    if @filters[:window].present?
      scope = scope.where("occurred_at >= ?", window_start(@filters[:window]))
    end

    if params[:hit_id].present?
      scope = scope.where(id: params[:hit_id])
    end

    sort = params[:sort].to_s
    dir = params[:dir].to_s == "asc" ? "ASC" : "DESC"
    scope = case sort
            when "occurred_at" then scope.order(Arel.sql("occurred_at #{dir}"))
            when "score" then scope.order(Arel.sql("score #{dir}"))
            when "dst_ip" then scope.order(Arel.sql("dst_ip #{dir}"))
            when "dst_port" then scope.order(Arel.sql("dst_port #{dir}"))
            when "device"
              scope.joins("LEFT JOIN devices ON devices.id = anomaly_hits.device_id")
                   .order(Arel.sql("COALESCE(devices.name, devices.ip, '') #{dir}"))
            else
              scope.order(occurred_at: :desc)
            end

    @page = [params[:page].to_i, 1].max
    @total = scope.count
    @total_pages = (@total / RESULTS_LIMIT.to_f).ceil
    @hits = scope.limit(RESULTS_LIMIT).offset((@page - 1) * RESULTS_LIMIT)
  end

  def update
    hit = AnomalyHit.find(params[:id])
    hit.update!(ack_params.merge(acknowledged_at: Time.current))
    redirect_to "/anomalies"
  end

  private

  def filter_params
    params.permit(:min_score, :device, :code, :dst_ip, :dst_port, :window)
  end

  def ack_params
    params.require(:anomaly_hit).permit(:ack_notes)
  end

  def window_start(value)
    case value
    when "1h" then Time.current - 1.hour
    when "24h" then Time.current - 24.hours
    when "7d" then Time.current - 7.days
    else Time.current - 24.hours
    end
  end
end
