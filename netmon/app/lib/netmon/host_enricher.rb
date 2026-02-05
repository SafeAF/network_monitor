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

    def self.apply(remote_host, now: Time.current, resolver: Resolv, runner: Open3)
      if needs_rdns?(remote_host, now)
        remote_host.rdns_name = reverse_dns(remote_host.ip, resolver)
        remote_host.rdns_checked_at = now
      end

      if needs_whois?(remote_host, now)
        remote_host.whois_name = whois(remote_host.ip, runner)
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
      return nil unless status.success?

      parse_whois(stdout)
    rescue Errno::ENOENT
      nil
    end
    private_class_method :whois

    def self.parse_whois(text)
      text.each_line do |line|
        next unless line.include?(":")

        key, value = line.split(":", 2).map(&:strip)
        next if value.to_s.empty?

        return value if WHOIS_KEYS.include?(key)
      end
      nil
    end
    private_class_method :parse_whois
  end
end
