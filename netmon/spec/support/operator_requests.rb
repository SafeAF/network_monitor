# frozen_string_literal: true

module OperatorRequests
  %i[get head post patch put delete].each do |verb|
    define_method(verb) do |path, **options|
      unless RSpec.current_example.metadata[:operator_auth] == false || path.start_with?("/api/")
        auth = ActionController::HttpAuthentication::Basic.encode_credentials("test-admin", "test-admin-password-123456")
        options[:headers] = { "Authorization" => auth }.merge(options[:headers] || {})
      end
      super(path, **options)
    end
  end
end

RSpec.configure do |config|
  config.include OperatorRequests, type: :request
  config.around(type: :request) do |example|
    values = {
      "NETMON_ADMIN_USERNAME" => "test-admin", "NETMON_ADMIN_PASSWORD" => "test-admin-password-123456",
      "NETMON_READER_USERNAME" => "test-reader", "NETMON_READER_PASSWORD" => "test-reader-password-123456"
    }
    previous = values.to_h { |key, _| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    begin
      example.run
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end
