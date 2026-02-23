class Api::V1::Netmon::EventsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate!

  def batch
    payload = request.request_parameters
    events = Array(payload["events"])
    router_id = payload["router_id"].to_s
    sent_at = parse_time(payload["sent_at"])

    accepted = 0
    rejected = 0

    NetmonEvent.transaction do
      events.each do |evt|
        event_type = evt["type"].to_s
        ts = parse_time(evt["ts"]) || sent_at || Time.current
        data = evt["data"] || {}

        if event_type.empty? || router_id.empty?
          rejected += 1
          next
        end

        NetmonEvent.create!(event_type: event_type, ts: ts, router_id: router_id, data: data)
        Netmon::AgentIngest.ingest_event!(event_type: event_type, router_id: router_id, data: data, ts: ts)
        accepted += 1
      rescue StandardError
        rejected += 1
      end
    end

    render json: { accepted: accepted, rejected: rejected }
  end

  private

  def authenticate!
    token = request.authorization.to_s.sub(/^Bearer\s+/i, "").strip
    expected = ENV.fetch("NETMON_API_TOKEN", "")
    head :unauthorized and return if expected.empty? || token != expected
  end

  def parse_time(value)
    return if value.blank?
    Time.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
