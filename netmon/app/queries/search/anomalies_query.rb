# frozen_string_literal: true

require_relative "../../lib/search/param_normalizer"

module Search
  class AnomaliesQuery
    ALLOWED_SORTS = %w[occurred_at score dst_ip dst_port device].freeze

    attr_reader :params, :page, :per, :sort, :dir

    def initialize(params)
      @params = normalize(params)
      @page = ParamNormalizer.page(@params[:page])
      @per = ParamNormalizer.per(@params[:per])
      @sort = ALLOWED_SORTS.include?(@params[:sort]) ? @params[:sort] : "occurred_at"
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
        :min_score,
        :code,
        :codes,
        :device,
        :dst_ip,
        :dst_port,
        :proto,
        :window,
        :ack,
        :incident,
        :alertable,
        :fingerprint,
        :summary,
        :sort,
        :dir
      ).reject { |_k, v| v.blank? }
    end

    private

    def normalize(raw)
      {
        min_score: ParamNormalizer.clean_int(raw[:min_score]),
        code: ParamNormalizer.clean_upcase(raw[:code]),
        codes: ParamNormalizer.clean_upcase(raw[:codes]),
        device: ParamNormalizer.clean_string(raw[:device]),
        dst_ip: ParamNormalizer.clean_string(raw[:dst_ip]),
        dst_port: ParamNormalizer.clean_int(raw[:dst_port]),
        proto: ParamNormalizer.clean_downcase(raw[:proto]),
        window: ParamNormalizer.clean_window(raw[:window]) || "24h",
        ack: ParamNormalizer.clean_bool(raw[:ack]),
        incident: ParamNormalizer.clean_bool(raw[:incident]),
        alertable: ParamNormalizer.clean_bool(raw[:alertable]),
        fingerprint: ParamNormalizer.clean_string(raw[:fingerprint]),
        summary: ParamNormalizer.clean_string(raw[:summary]),
        sort: ParamNormalizer.clean_string(raw[:sort]),
        dir: ParamNormalizer.clean_string(raw[:dir]),
        page: raw[:page],
        per: raw[:per]
      }
    end

    def base_scope
      scope = AnomalyHit.includes(:device, :remote_host, :incident)

      scope = scope.where("score >= ?", params[:min_score]) if params[:min_score].present?
      scope = scope.where(dst_ip: params[:dst_ip]) if params[:dst_ip].present?
      scope = scope.where(dst_port: params[:dst_port]) if params[:dst_port].present?
      scope = scope.where("LOWER(proto) = ?", params[:proto]) if params[:proto].present?

      if params[:device].present?
        device = params[:device]
        scope = scope.joins(:device).where("devices.id = ? OR devices.ip = ? OR devices.name = ?", device, device, device)
      end

      if params[:code].present?
        scope = scope.where("reasons_json LIKE ?", "%#{params[:code]}%")
      end
      if params[:codes].present?
        codes = params[:codes].split(",").map(&:strip).reject(&:empty?)
        if codes.any?
          clauses = codes.map { "reasons_json LIKE ?" }.join(" OR ")
          values = codes.map { |code| "%#{code}%" }
          scope = scope.where(clauses, *values)
        end
      end

      scope = scope.where("occurred_at >= ?", window_start(params[:window])) if params[:window].present?

      if params[:ack] == true
        scope = scope.where.not(acknowledged_at: nil)
      elsif params[:ack] == false
        scope = scope.where(acknowledged_at: nil)
      end

      if params[:incident] == true
        scope = scope.where.not(incident_id: nil)
      elsif params[:incident] == false
        scope = scope.where(incident_id: nil)
      end

      if params[:alertable] == true
        scope = scope.where(alertable: true)
      elsif params[:alertable] == false
        scope = scope.where(alertable: false)
      end

      scope = scope.where(fingerprint: params[:fingerprint]) if params[:fingerprint].present?
      scope = scope.where("summary LIKE ?", "%#{params[:summary]}%") if params[:summary].present?

      scope
    end

    def apply_sort(scope)
      dir_sql = dir == "asc" ? "ASC" : "DESC"
      case sort
      when "score"
        scope.order(Arel.sql("score #{dir_sql}"))
      when "dst_ip"
        scope.order(Arel.sql("dst_ip #{dir_sql}"))
      when "dst_port"
        scope.order(Arel.sql("dst_port #{dir_sql}"))
      when "device"
        scope.joins("LEFT JOIN devices ON devices.id = anomaly_hits.device_id")
             .order(Arel.sql("COALESCE(devices.name, devices.ip, '') #{dir_sql}"))
      else
        scope.order(Arel.sql("occurred_at #{dir_sql}"))
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
