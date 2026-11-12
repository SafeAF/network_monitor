class Api::V1::Netmon::EventsController < ApplicationController
  skip_before_action :authenticate_operator!, :authorize_operator!
  skip_after_action :audit_operator_change
  skip_before_action :verify_authenticity_token
  before_action :authenticate!

  def batch
    result = Netmon::BatchIngest.call(request.request_parameters)
    # Older agents discard every 2xx response without inspecting its body.
    # Keep their whole batch retryable until an acknowledgement-aware upgrade.
    legacy_failure = request.headers["X-Netmon-Protocol-Version"] != "1" &&
      (result[:rejected].positive? || result[:retryable].positive?)
    render json: result, status: legacy_failure ? :service_unavailable : :ok
  rescue Netmon::RouterPolicy::Unavailable => e
    render json: { protocol_version: 1, error: "router_unavailable", code: e.message, retryable: true }, status: :service_unavailable
  rescue Netmon::EventContract::Invalid => e
    render json: { protocol_version: 1, error: "invalid_batch", code: e.message, retryable: false }, status: :bad_request
  end

  private

  def authenticate!
    token = request.authorization.to_s.match(/\ABearer[ \t]+([^\s]+)\z/i)&.[](1).to_s
    expected = ENV.fetch("NETMON_API_TOKEN", "")
    head :unauthorized and return if expected.empty? || (Rails.env.production? && expected.bytesize < 32) ||
      !ActiveSupport::SecurityUtils.secure_compare(token, expected)
  end

end
