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
end
