# frozen_string_literal: true

require "openssl"

module Netmon
  class OperatorCredentials
    # Basic authentication must be served over TLS. No default credentials or
    # development bypass: an unconfigured installation denies operator access.
    def self.role_for(username, password, env: ENV)
      %w[admin reader].each do |role|
        prefix = "NETMON_#{role.upcase}"
        expected_user = env.fetch("#{prefix}_USERNAME", "")
        expected_password = env.fetch("#{prefix}_PASSWORD", "")
        next if expected_user.empty? || expected_password.bytesize < 20
        next if secure_equal?(expected_password, env.fetch("NETMON_API_TOKEN", ""))

        user_matches = secure_equal?(username, expected_user)
        password_matches = secure_equal?(password, expected_password)
        return role if user_matches & password_matches
      end
      nil
    end

    def self.secure_equal?(provided, expected)
      OpenSSL.fixed_length_secure_compare(
        OpenSSL::Digest.digest("SHA256", provided.to_s), OpenSSL::Digest.digest("SHA256", expected.to_s)
      )
    end
    private_class_method :secure_equal?
  end
end
