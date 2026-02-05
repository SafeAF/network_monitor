# frozen_string_literal: true

require "yaml"
require "ipaddr"

module Netmon
  class Filter
    DEFAULT_LOCAL_SUBNETS = ["10.0.0.0/24"].freeze
    DEFAULT_EXCLUDE_SUBNETS = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
      "127.0.0.0/8",
      "169.254.0.0/16"
    ].freeze

    def self.outbound?(entry, config: nil)
      return false if entry.nil? || entry.orig.nil?

      orig = entry.orig
      return false if orig.src.nil? || orig.dst.nil?

      config ||= load_config
      local_subnets = subnet_list(config["local_subnets"], DEFAULT_LOCAL_SUBNETS)
      exclude_subnets = subnet_list(config["exclude_subnets"], DEFAULT_EXCLUDE_SUBNETS)

      src = IPAddr.new(orig.src) rescue nil
      dst = IPAddr.new(orig.dst) rescue nil
      return false if src.nil? || dst.nil?

      local_subnets.any? { |net| net.include?(src) } && exclude_subnets.none? { |net| net.include?(dst) }
    end

    def self.load_config
      path = Rails.root.join("config/netmon.yml")
      YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false) || {}
    rescue Errno::ENOENT
      {}
    end
    private_class_method :load_config

    def self.subnet_list(value, fallback)
      Array(value.presence || fallback).map { |cidr| IPAddr.new(cidr) }
    end
    private_class_method :subnet_list
  end
end
