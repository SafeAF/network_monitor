# frozen_string_literal: true

module Netmon
  class ConnectionsQuery
    def self.call(params, now: Time.current)
      threshold = now - RemoteHost::NEW_WINDOW
      scope = Connection.all

      src_ip = params[:src_ip].to_s.strip
      dst_ip = params[:dst_ip].to_s.strip
      proto = params[:proto].to_s.strip.downcase
      dport = params[:dport].to_s.strip
      min_score = params[:min_score].to_s.strip

      scope = scope.where(src_ip:) if src_ip.present?
      scope = scope.where(dst_ip:) if dst_ip.present?
      scope = scope.where(proto:) if proto.present?
      scope = scope.where(dst_port: dport.to_i) if dport.match?(/\A\d+\z/)
      scope = scope.where("anomaly_score >= ?", min_score.to_i) if min_score.match?(/\A\d+\z/)

      scope = scope.where.not(state: "TIME_WAIT") if truthy_param?(params[:hide_time_wait])

      if truthy_param?(params[:only_new])
        scope = scope.joins("INNER JOIN remote_hosts ON remote_hosts.ip = connections.dst_ip")
                     .where("remote_hosts.first_seen_at >= ?", threshold)
      end

      scope = scope.order(Arel.sql("uplink_bytes + downlink_bytes DESC"))
      [scope, threshold]
    end

    def self.truthy_param?(value)
      value.to_s.strip.downcase.in?(%w[1 true yes on])
    end
    private_class_method :truthy_param?
  end
end
