# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
ENV["NETMON_ROUTER_ID"] = "router-1"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

require_relative "spec_helper"
require_relative "support/operator_requests"

ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
