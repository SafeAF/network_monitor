# frozen_string_literal: true

module Netmon
  class ConnectionsQuery
    DEFAULT_WINDOW = 10.minutes
    HIDEABLE_STATES = %w[TIME_WAIT DESTROY SYN_SENT CLOSE].freeze

    def self.call(params, now: Time.current)
      threshold = now - RemoteHost::NEW_WINDOW
      scope = Connection.all

      src_ip = params[:src_ip].to_s.strip
      dst_ip = params[:dst_ip].to_s.strip
      proto = params[:proto].to_s.strip.downcase
      dport = params[:dport].to_s.strip
      min_score = params[:min_score].to_s.strip
      hidden_states = normalize_hidden_states(params)

      scope = scope.where(src_ip:) if src_ip.present?
      scope = scope.where(dst_ip:) if dst_ip.present?
      scope = scope.where(proto:) if proto.present?
      scope = scope.where(dst_port: dport.to_i) if dport.match?(/\A\d+\z/)
      scope = scope.where("anomaly_score >= ?", min_score.to_i) if min_score.match?(/\A\d+\z/)

      scope = scope.where.not(state: hidden_states) if hidden_states.any?
      unless truthy_param?(params[:include_stale])
        scope = scope.where("connections.last_seen_at >= ?", now - DEFAULT_WINDOW)
      end

      if truthy_param?(params[:only_new])
        scope = scope.joins("INNER JOIN remote_hosts ON remote_hosts.ip = connections.dst_ip")
                     .where("remote_hosts.first_seen_at >= ?", threshold)
      end

      sort = params[:sort].to_s
      dir = params[:dir].to_s == "asc" ? "ASC" : "DESC"
      case sort
      when "total_bytes"
        scope = scope.order(Arel.sql("connections.uplink_bytes + connections.downlink_bytes #{dir}"))
      when "uplink_bytes"
        scope = scope.order(Arel.sql("connections.uplink_bytes #{dir}"))
      when "downlink_bytes"
        scope = scope.order(Arel.sql("connections.downlink_bytes #{dir}"))
      when "score"
        scope = scope.order(Arel.sql("connections.anomaly_score #{dir}"))
      when "age"
        scope = scope.joins("LEFT JOIN remote_hosts ON remote_hosts.ip = connections.dst_ip")
                     .order(Arel.sql("COALESCE(remote_hosts.first_seen_at, connections.first_seen_at) #{dir}"))
      when "dst_ip"
        scope = scope.order(Arel.sql("connections.dst_ip #{dir}"))
      when "dst_port"
        scope = scope.order(Arel.sql("connections.dst_port #{dir}"))
      else
        scope = scope.order(Arel.sql("connections.uplink_bytes + connections.downlink_bytes DESC"))
      end
      [scope, threshold]
    end

    def self.normalize_hidden_states(params)
      states = Array(params[:hide_states]).map { |state| state.to_s.strip.upcase }
      states << "TIME_WAIT" if truthy_param?(params[:hide_time_wait])
      states.uniq & HIDEABLE_STATES
    end
    private_class_method :normalize_hidden_states

    def self.truthy_param?(value)
      value.to_s.strip.downcase.in?(%w[1 true yes on])
    end
    private_class_method :truthy_param?
  end
end
