# frozen_string_literal: true

class IncidentsController < ApplicationController
  RESULTS_LIMIT = 200

  def index
    @filters = params.permit(:unacknowledged, :min_score, :code, :device, :window)
    scope = Incident.order(last_seen_at: :desc)

    if @filters[:unacknowledged].to_s == "true"
      scope = scope.where(acknowledged_at: nil)
    end

    if @filters[:min_score].to_s.match?(/\A\d+\z/)
      scope = scope.where("max_score >= ?", @filters[:min_score].to_i)
    end

    if @filters[:code].present?
      scope = scope.where("codes_csv LIKE ?", "%#{@filters[:code]}%")
    end

    if @filters[:device].present?
      device = @filters[:device].to_s
      scope = scope.joins("LEFT JOIN devices ON devices.id = incidents.device_id")
                   .where("devices.id = ? OR devices.ip = ? OR devices.name = ?", device, device, device)
    end

    if @filters[:window].present?
      scope = scope.where("last_seen_at >= ?", window_start(@filters[:window]))
    end

    @page = [params[:page].to_i, 1].max
    @total = scope.count
    @total_pages = (@total / RESULTS_LIMIT.to_f).ceil
    @incidents = scope.limit(RESULTS_LIMIT).offset((@page - 1) * RESULTS_LIMIT)

    hit_scope = AnomalyHit.where(incident_id: @incidents.map(&:id)).order(occurred_at: :desc)
    @incident_hits = hit_scope.group_by(&:incident_id)
    @devices_by_id = Device.where(id: @incidents.map(&:device_id).compact).index_by(&:id)
  end

  def show
    @incident = Incident.find(params[:id])
    @device = Device.find_by(id: @incident.device_id)
    @hits = AnomalyHit.where(incident_id: @incident.id).order(occurred_at: :desc).limit(50)
  end

  def ack
    incident = Incident.find(params[:id])
    incident.update!(ack_params.merge(acknowledged_at: Time.current))
    redirect_to "/incidents"
  end

  private

  def ack_params
    params.require(:incident).permit(:ack_notes)
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
