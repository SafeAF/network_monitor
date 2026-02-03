# frozen_string_literal: true

require "yaml"
require "ipaddr"

namespace :conntrack do
  desc "Print top 20 outbound connections by total bytes"
  task print_outbound: :environment do
    config_path = Rails.root.join("config/netmon.yml")
    config = YAML.safe_load(File.read(config_path), permitted_classes: [], permitted_symbols: [], aliases: false) || {}

    local_subnets = Array(config["local_subnets"]).map { |cidr| IPAddr.new(cidr) }
    exclude_subnets = Array(config["exclude_subnets"]).map { |cidr| IPAddr.new(cidr) }

    entries = Conntrack::Snapshot.read

    outbound = entries.select do |entry|
      orig = entry.orig
      next false if orig.nil? || orig.src.nil? || orig.dst.nil?

      src = IPAddr.new(orig.src) rescue nil
      dst = IPAddr.new(orig.dst) rescue nil
      next false if src.nil? || dst.nil?

      local_subnets.any? { |net| net.include?(src) } && exclude_subnets.none? { |net| net.include?(dst) }
    end

    rows = outbound.map do |entry|
      uplink = entry.orig.bytes.to_i
      downlink = entry.reply&.bytes.to_i
      { entry: entry, total: uplink + downlink, uplink: uplink, downlink: downlink }
    end

    rows.sort_by { |row| -row[:total] }.first(20).each do |row|
      orig = row[:entry].orig
      puts format(
        "%-15s:%-5s -> %-15s:%-5s %8d bytes (up:%d down:%d)",
        orig.src,
        orig.sport || "-",
        orig.dst,
        orig.dport || "-",
        row[:total],
        row[:uplink],
        row[:downlink]
      )
    end
  end
end
