# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    @connections, @new_threshold = Netmon::ConnectionsQuery.call(params)
    @hosts_by_ip = RemoteHost.where(ip: @connections.map(&:dst_ip)).index_by(&:ip)
  end
end
