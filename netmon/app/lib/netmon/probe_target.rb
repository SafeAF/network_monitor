# frozen_string_literal: true

require "ipaddr"

module Netmon
  class ProbeTarget
    def self.parse(value)
      # Reject CIDRs, whitespace, zone IDs, hostnames and command options.
      return unless value.is_a?(String) && value.match?(/\A[0-9a-fA-F:.]+\z/)

      ip = IPAddr.new(value)
      return if ip.loopback? || ip.to_i.zero?
      return if IPAddr.new("224.0.0.0/4").include?(ip) || IPAddr.new("ff00::/8").include?(ip)
      return if IPAddr.new("169.254.0.0/16").include?(ip) || IPAddr.new("fe80::/10").include?(ip)
      return if ip.ipv4_mapped?

      ip.to_s
    rescue IPAddr::InvalidAddressError
      nil
    end
  end
end
