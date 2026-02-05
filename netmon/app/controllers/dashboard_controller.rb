# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    @connections = Connection.order(Arel.sql("uplink_bytes + downlink_bytes DESC"))
    @hosts_by_ip = RemoteHost.where(ip: @connections.map(&:dst_ip)).index_by(&:ip)
    @new_threshold = Time.current - 60.seconds
  end
end
