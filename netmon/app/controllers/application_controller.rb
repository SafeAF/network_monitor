class ApplicationController < ActionController::Base
  before_action :authenticate_operator!
  before_action :authorize_operator!
  after_action :audit_operator_change

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

  def authenticate_operator!
    authenticate_or_request_with_http_basic("Netmon") do |username, password|
      @operator_role = Netmon::OperatorCredentials.role_for(username, password)
      @operator_name = username if @operator_role
      @operator_role.present?
    end
  end

  def authorize_operator!
    head :forbidden unless request.get? || request.head? || @operator_role == "admin"
  end

  def audit_operator_change
    return if request.get? || request.head? || response.status >= 400 || @operator_name.nil?

    # Values (including notes and credentials) are deliberately excluded.
    fields = request.request_parameters.except("authenticity_token").transform_values do |value|
      value.respond_to?(:keys) ? value.keys : "changed"
    end
    Rails.logger.info({
      event: "operator_change", actor: @operator_name, role: @operator_role,
      controller: controller_name, action: action_name,
      target: params[:id] || params[:ip], fields: fields,
      request_id: request.request_id, status: response.status, at: Time.current.iso8601
    }.to_json)
  end
end
