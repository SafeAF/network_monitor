# frozen_string_literal: true

class MetricsController < ApplicationController
  def index
    interfaces = params[:interfaces].to_s.split(",").map(&:strip).reject(&:empty?)
    render json: Netmon::Metrics.read(interfaces: interfaces)
  end

  def series
    window = params[:window].to_s
    render json: Netmon::MetricsReporter.series_for_window(window: window, now: Time.current)
  end
end
