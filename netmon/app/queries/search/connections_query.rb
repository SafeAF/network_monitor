# frozen_string_literal: true

require_relative "../../lib/search/param_normalizer"

module Search
  class ConnectionsQuery
    ALLOWED_SORTS = %w[last_seen_at total_bytes uplink_bytes downlink_bytes dst_ip dst_port anomaly_score].freeze

    attr_reader :params, :page, :per, :sort, :dir

    def initialize(params)
      @params = normalize(params)
      @page = ParamNormalizer.page(@params[:page])
      @per = ParamNormalizer.per(@params[:per])
      @sort = ALLOWED_SORTS.include?(@params[:sort]) ? @params[:sort] : "last_seen_at"
      @dir = @params[:dir] == "asc" ? "asc" : "desc"
    end

    def results
      scoped = apply_sort(base_scope)
      scoped.limit(per).offset((page - 1) * per)
    end

    def total_count
      @total_count ||= base_scope.count
    end

    def total_pages
      (total_count / per.to_f).ceil
    end

    def saved_params
      params.slice(
        :device,
        :src_ip,
        :dst_ip,
        :dst_port,
        :proto,
        :state,
        :min_score,
        :reason,
        :seen_since,
        :min_total_bytes,
        :min_uplink_bytes,
        :min_downlink_bytes,
        :allowlisted,
        :sort,
        :dir
      ).reject { |_k, v| v.blank? }
    end

    private

    def normalize(raw)
      {
        device: ParamNormalizer.clean_string(raw[:device]),
        src_ip: ParamNormalizer.clean_string(raw[:src_ip]),
        dst_ip: ParamNormalizer.clean_string(raw[:dst_ip]),
        dst_port: ParamNormalizer.clean_int(raw[:dst_port]),
        proto: ParamNormalizer.clean_downcase(raw[:proto]),
        state: ParamNormalizer.clean_upcase(raw[:state]),
        min_score: ParamNormalizer.clean_int(raw[:min_score]),
        reason: ParamNormalizer.clean_string(raw[:reason]),
        seen_since: ParamNormalizer.clean_window(raw[:seen_since]),
        min_total_bytes: ParamNormalizer.clean_int(raw[:min_total_bytes]),
        min_uplink_bytes: ParamNormalizer.clean_int(raw[:min_uplink_bytes]),
        min_downlink_bytes: ParamNormalizer.clean_int(raw[:min_downlink_bytes]),
        allowlisted: ParamNormalizer.clean_bool(raw[:allowlisted]),
        sort: ParamNormalizer.clean_string(raw[:sort]),
        dir: ParamNormalizer.clean_string(raw[:dir]),
        page: raw[:page],
        per: raw[:per]
      }
    end

    def base_scope
      scope = Connection.all

      if params[:device].present?
        device = params[:device]
        scope = scope.joins("LEFT JOIN devices ON devices.ip = connections.src_ip")
                     .where("devices.name = ? OR devices.ip = ? OR connections.src_ip = ?", device, device, device)
      end

      scope = apply_ip_filter(scope, "connections.src_ip", params[:src_ip]) if params[:src_ip].present?
      scope = apply_ip_filter(scope, "connections.dst_ip", params[:dst_ip]) if params[:dst_ip].present?

      scope = scope.where(dst_port: params[:dst_port]) if params[:dst_port].present?
      scope = scope.where("LOWER(proto) = ?", params[:proto]) if params[:proto].present?
      scope = scope.where(state: params[:state]) if params[:state].present?

      scope = scope.where("anomaly_score >= ?", params[:min_score]) if params[:min_score].present?
      scope = scope.where("anomaly_reasons_json LIKE ?", "%#{params[:reason]}%") if params[:reason].present?

      if params[:seen_since].present?
        scope = scope.where("last_seen_at >= ?", window_start(params[:seen_since]))
      end

      if params[:min_total_bytes].present?
        scope = scope.where("(uplink_bytes + downlink_bytes) >= ?", params[:min_total_bytes])
      end
      scope = scope.where("uplink_bytes >= ?", params[:min_uplink_bytes]) if params[:min_uplink_bytes].present?
      scope = scope.where("downlink_bytes >= ?", params[:min_downlink_bytes]) if params[:min_downlink_bytes].present?

      if params[:allowlisted] == true || params[:allowlisted] == false
        scope = scope.joins("LEFT JOIN devices ON devices.ip = connections.src_ip")
        exists_sql = <<~SQL.squish
          EXISTS (
            SELECT 1 FROM allowlist_rules
            WHERE (
              (allowlist_rules.kind = 'ip' AND allowlist_rules.value = connections.dst_ip)
              OR (allowlist_rules.kind = 'port' AND allowlist_rules.value = CAST(connections.dst_port AS TEXT))
              OR (allowlist_rules.kind = 'device_port' AND allowlist_rules.value = CAST(connections.dst_port AS TEXT)
                  AND (allowlist_rules.device_id IS NULL OR allowlist_rules.device_id = devices.id))
            )
          )
        SQL
        scope = params[:allowlisted] ? scope.where(exists_sql) : scope.where("NOT #{exists_sql}")
      end

      scope
    end

    def apply_sort(scope)
      dir_sql = dir == "asc" ? "ASC" : "DESC"
      case sort
      when "total_bytes"
        scope.order(Arel.sql("uplink_bytes + downlink_bytes #{dir_sql}"))
      when "uplink_bytes"
        scope.order(Arel.sql("uplink_bytes #{dir_sql}"))
      when "downlink_bytes"
        scope.order(Arel.sql("downlink_bytes #{dir_sql}"))
      when "dst_ip"
        scope.order(Arel.sql("dst_ip #{dir_sql}"))
      when "dst_port"
        scope.order(Arel.sql("dst_port #{dir_sql}"))
      when "anomaly_score"
        scope.order(Arel.sql("anomaly_score #{dir_sql}"))
      else
        scope.order(Arel.sql("last_seen_at #{dir_sql}"))
      end
    end

    def apply_ip_filter(scope, column, value)
      ip = value
      if ip.include?("*")
        scope.where("#{column} LIKE ?", ip.tr("*", "%"))
      elsif ip.include?("%")
        scope.where("#{column} LIKE ?", ip)
      elsif ip.end_with?(".") || ip.count(".") < 3
        scope.where("#{column} LIKE ?", "#{ip}%")
      else
        scope.where(column => ip)
      end
    end

    def window_start(value)
      case value
      when "10m" then Time.current - 10.minutes
      when "1h" then Time.current - 1.hour
      when "24h" then Time.current - 24.hours
      when "7d" then Time.current - 7.days
      when "30d" then Time.current - 30.days
      else Time.current - 24.hours
      end
    end
  end
end
