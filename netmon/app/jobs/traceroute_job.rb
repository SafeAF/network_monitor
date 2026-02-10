# frozen_string_literal: true

class TracerouteJob < ApplicationJob
  queue_as :default

  def perform(ip)
    key = cache_key(ip)
    Rails.cache.write(key, { status: "running", output: nil, updated_at: Time.current.to_i })

    output = run_traceroute(ip)
    status = output ? "done" : "error"
    Rails.cache.write(key, { status: status, output: output, updated_at: Time.current.to_i })
  rescue StandardError => e
    Rails.cache.write(key, { status: "error", output: e.message, updated_at: Time.current.to_i })
  end

  private

  def run_traceroute(ip)
    require "open3"
    require "timeout"

    output = nil
    Timeout.timeout(8) do
      stdout, status = Open3.capture2e("traceroute", "-n", ip.to_s)
      output = stdout if status.success?
    end
    output
  rescue Errno::ENOENT, Timeout::Error
    nil
  end

  def cache_key(ip)
    "traceroute:#{ip}"
  end
end
