# frozen_string_literal: true

require "open3"
require "resolv"

module Netmon
  class HostEnricher
    RDNS_TTL = 6.hours
    WHOIS_TTL = 7.days

    WHOIS_KEYS = [
      "OrgName",
      "Org-name",
      "org-name",
      "Organization",
      "Org",
      "owner",
      "descr",
      "netname",
      "CustName",
      "customer"
    ].freeze

    WHOIS_ASN_KEYS = [
      "OriginAS",
      "origin",
      "originas",
      "aut-num",
      "ASName"
    ].freeze

    def self.apply(remote_host, now: Time.current, resolver: Resolv, runner: Open3)
      if needs_rdns?(remote_host, now)
        remote_host.rdns_name = reverse_dns(remote_host.ip, resolver)
        remote_host.rdns_checked_at = now
      end

      if needs_whois?(remote_host, now)
        whois_name, whois_raw_line, whois_asn = whois(remote_host.ip, runner)
        remote_host.whois_name = whois_name if remote_host.respond_to?(:whois_name=)
        remote_host.whois_raw_line = whois_raw_line if remote_host.respond_to?(:whois_raw_line=)
        remote_host.whois_asn = whois_asn if remote_host.respond_to?(:whois_asn=)
        remote_host.whois_checked_at = now
      end
    end

    def self.needs_rdns?(remote_host, now)
      return true if remote_host.rdns_checked_at.nil?

      remote_host.rdns_checked_at < now - RDNS_TTL
    end
    private_class_method :needs_rdns?

    def self.needs_whois?(remote_host, now)
      return true if remote_host.whois_checked_at.nil?

      remote_host.whois_checked_at < now - WHOIS_TTL
    end
    private_class_method :needs_whois?

    def self.reverse_dns(ip, resolver)
      resolver.getname(ip)
    rescue Resolv::ResolvError, ArgumentError
      nil
    end
    private_class_method :reverse_dns

    def self.whois(ip, runner)
      stdout, status = runner.capture2e("whois", ip.to_s)
      return [nil, nil, nil] unless status.success?

      parse_whois(stdout)
    rescue Errno::ENOENT
      [nil, nil, nil]
    end
    private_class_method :whois

    def self.parse_whois(text)
      asn = nil
      text.each_line do |line|
        next unless line.include?(":")

        key, value = line.split(":", 2).map(&:strip)
        next if value.to_s.empty?

        if WHOIS_ASN_KEYS.include?(key) && asn.nil?
          asn = extract_asn(value)
        end

        return [value, "#{key}: #{value}", asn] if WHOIS_KEYS.include?(key)
      end
      [nil, nil, asn]
    end
    private_class_method :parse_whois

    def self.extract_asn(value)
      match = value.to_s.match(/AS\d+/i)
      match ? match[0].upcase : nil
    end
    private_class_method :extract_asn
  end
end
