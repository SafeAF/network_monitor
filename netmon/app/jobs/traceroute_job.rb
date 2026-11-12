# frozen_string_literal: true

class TracerouteJob < ApplicationJob
  queue_as :default

  def perform(ip, run_id)
    return unless Netmon::ProbeTarget.parse(ip) == ip

    key = cache_key(ip)
    return if cancelled?(key, run_id)

    Rails.cache.write(key, { status: "running", run_id: run_id, output: nil, updated_at: Time.current.to_i }, expires_in: 5.minutes)

    output = Netmon::BoundedCommand.capture("traceroute", "-n", ip,
      timeout: 8, cancelled: -> { cancelled?(key, run_id) })
    if cancelled?(key, run_id)
      payload = Rails.cache.read(key)
      if payload && payload[:run_id] == run_id
        Rails.cache.write(key, payload.merge(status: "cancelled", updated_at: Time.current.to_i), expires_in: 5.minutes)
      end
      return
    end

    status = output ? "done" : "error"
    Rails.cache.write(key, { status: status, run_id: run_id, output: output, updated_at: Time.current.to_i }, expires_in: 5.minutes)
  rescue StandardError => e
    Rails.logger.error("[traceroute] failed error=#{e.class}")
    unless key.nil? || cancelled?(key, run_id)
      Rails.cache.write(key, { status: "error", run_id: run_id, output: "Probe failed", updated_at: Time.current.to_i }, expires_in: 5.minutes)
    end
  end

  private

  def cancelled?(key, run_id)
    payload = Rails.cache.read(key)
    Rails.cache.read("traceroute:cancelled:#{run_id}") || payload.nil? ||
      payload[:run_id] != run_id || payload[:status] == "cancelled"
  end

  def cache_key(ip)
    "traceroute:#{ip}"
  end
end
