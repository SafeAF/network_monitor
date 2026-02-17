# frozen_string_literal: true

require_relative "../../lib/search/param_normalizer"

module Search
  class HostsQuery
    ALLOWED_SORTS = %w[last_seen_at first_seen_at ip tag whois_name].freeze

    attr_reader :params, :page, :per, :sort, :dir

    def initialize(params)
      @params = normalize(params)
      @page = ParamNormalizer.page(@params[:page])
      @per = ParamNormalizer.per(@params[:per])
      @sort = ALLOWED_SORTS.include?(@params[:sort]) ? @params[:sort] : "last_seen_at"
      @dir = @params[:dir] == "asc" ? :asc : :desc
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
        :ip,
        :tag,
        :rdns,
        :whois,
        :asn,
        :seen_since,
        :first_seen_since,
        :has_rdns,
        :has_whois,
        :notes,
        :dst_port,
        :sort,
        :dir
      ).reject { |_k, v| v.blank? }
    end

    private

    def normalize(raw)
      {
        ip: ParamNormalizer.clean_string(raw[:ip]),
        tag: ParamNormalizer.clean_downcase(raw[:tag]),
        rdns: ParamNormalizer.clean_string(raw[:rdns]),
        whois: ParamNormalizer.clean_string(raw[:whois]),
        asn: ParamNormalizer.clean_string(raw[:asn]),
        seen_since: ParamNormalizer.clean_window(raw[:seen_since]),
        first_seen_since: ParamNormalizer.clean_window(raw[:first_seen_since]),
        has_rdns: ParamNormalizer.clean_bool(raw[:has_rdns]),
        has_whois: ParamNormalizer.clean_bool(raw[:has_whois]),
        notes: ParamNormalizer.clean_string(raw[:notes]),
        dst_port: ParamNormalizer.clean_int(raw[:dst_port]),
        sort: ParamNormalizer.clean_string(raw[:sort]),
        dir: ParamNormalizer.clean_string(raw[:dir]),
        page: raw[:page],
        per: raw[:per]
      }
    end

    def base_scope
      scope = RemoteHost.all

      if params[:ip].present?
        ip = params[:ip]
        if ip.include?("*")
          scope = scope.where("ip LIKE ?", ip.tr("*", "%"))
        elsif ip.include?("%")
          scope = scope.where("ip LIKE ?", ip)
        elsif ip.end_with?(".") || ip.count(".") < 3
          scope = scope.where("ip LIKE ?", "#{ip}%")
        else
          scope = scope.where(ip: ip)
        end
      end

      scope = scope.where(tag: params[:tag]) if params[:tag].present?
      scope = scope.where("rdns_name LIKE ?", "%#{params[:rdns]}%") if params[:rdns].present?
      scope = scope.where("whois_name LIKE ?", "%#{params[:whois]}%") if params[:whois].present?
      scope = scope.where("whois_asn LIKE ?", "%#{params[:asn]}%") if params[:asn].present?
      scope = scope.where("notes LIKE ?", "%#{params[:notes]}%") if params[:notes].present?

      if params[:seen_since].present?
        scope = scope.where("last_seen_at >= ?", window_start(params[:seen_since]))
      end
      if params[:first_seen_since].present?
        scope = scope.where("first_seen_at >= ?", window_start(params[:first_seen_since]))
      end

      if params[:has_rdns] == true
        scope = scope.where("rdns_name IS NOT NULL AND rdns_name != ''")
      elsif params[:has_rdns] == false
        scope = scope.where("rdns_name IS NULL OR rdns_name = ''")
      end

      if params[:has_whois] == true
        scope = scope.where("whois_name IS NOT NULL AND whois_name != ''")
      elsif params[:has_whois] == false
        scope = scope.where("whois_name IS NULL OR whois_name = ''")
      end

      if params[:dst_port].present?
        scope = scope.joins(:remote_host_ports).where(remote_host_ports: { dst_port: params[:dst_port] }).distinct
      end

      scope
    end

    def apply_sort(scope)
      case sort
      when "first_seen_at"
        scope.order(first_seen_at: dir)
      when "ip"
        scope.order(ip: dir)
      when "tag"
        scope.order(tag: dir)
      when "whois_name"
        scope.order(Arel.sql("COALESCE(whois_name, '') #{dir.to_s.upcase}"))
      else
        scope.order(last_seen_at: dir)
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
