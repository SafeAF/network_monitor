# frozen_string_literal: true

require "yaml"

class SearchController < ApplicationController
  RESULTS_LIMIT = 200

  def index
    @recent_saved_queries = SavedQuery.order(created_at: :desc).limit(10)
  end

  def hosts
    query = Search::HostsQuery.new(params)
    @filters = query.params
    @hosts = query.results
    @page = query.page
    @per = query.per
    @total = query.total_count
    @total_pages = query.total_pages

    port_rows = RemoteHostPort.where(remote_host_id: @hosts.map(&:id))
                              .order(seen_count: :desc)
    @ports_by_host = port_rows.group_by(&:remote_host_id)

    @saved_query_kind = "hosts"
    @saved_queries = SavedQuery.where(kind: @saved_query_kind).order(created_at: :desc)
    @saved_query_params = query.saved_params
  end

  def connections
    query = Search::ConnectionsQuery.new(params)
    @filters = query.params
    @connections = query.results
    @page = query.page
    @per = query.per
    @total = query.total_count
    @total_pages = query.total_pages

    @hosts_by_ip = RemoteHost.where(ip: @connections.map(&:dst_ip)).index_by(&:ip)
    @devices_by_ip = Device.where(ip: @connections.map(&:src_ip)).index_by(&:ip)

    @saved_query_kind = "connections"
    @saved_queries = SavedQuery.where(kind: @saved_query_kind).order(created_at: :desc)
    @saved_query_params = query.saved_params
  end

  def anomalies
    query = Search::AnomaliesQuery.new(params)
    @filters = query.params
    @hits = query.results
    @page = query.page
    @per = query.per
    @total = query.total_count
    @total_pages = query.total_pages
    @saved_query_kind = "anomalies"
    @saved_queries = SavedQuery.where(kind: @saved_query_kind).order(created_at: :desc)
    @saved_query_params = query.saved_params
  end

  private
end
