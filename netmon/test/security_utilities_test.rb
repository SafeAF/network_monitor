# frozen_string_literal: true

require "minitest/autorun"
require "rbconfig"
require_relative "../app/lib/netmon/operator_credentials"
require_relative "../app/lib/netmon/probe_target"
require_relative "../app/lib/netmon/bounded_command"

class SecurityUtilitiesTest < Minitest::Test
  def credentials
    {
      "NETMON_ADMIN_USERNAME" => "operator", "NETMON_ADMIN_PASSWORD" => "long-admin-password-123456",
      "NETMON_READER_USERNAME" => "observer", "NETMON_READER_PASSWORD" => "long-reader-password-123456",
      "NETMON_API_TOKEN" => "independent-agent-credential"
    }
  end

  def test_credentials_fail_closed
    assert_nil Netmon::OperatorCredentials.role_for("", "", env: {})
    assert_nil Netmon::OperatorCredentials.role_for("operator", "wrong", env: credentials)
    assert_nil Netmon::OperatorCredentials.role_for("wrong", credentials["NETMON_ADMIN_PASSWORD"], env: credentials)
    assert_nil Netmon::OperatorCredentials.role_for("operator", "short", env: credentials.merge("NETMON_ADMIN_PASSWORD" => "short"))
  end

  def test_admin_and_reader_roles
    assert_equal "admin", Netmon::OperatorCredentials.role_for("operator", credentials["NETMON_ADMIN_PASSWORD"], env: credentials)
    assert_equal "reader", Netmon::OperatorCredentials.role_for("observer", credentials["NETMON_READER_PASSWORD"], env: credentials)
  end

  def test_agent_password_cannot_double_as_operator_password
    shared = credentials.merge("NETMON_API_TOKEN" => credentials["NETMON_ADMIN_PASSWORD"])
    assert_nil Netmon::OperatorCredentials.role_for("operator", shared["NETMON_API_TOKEN"], env: shared)
  end

  def test_targets_accept_literal_public_and_lan_addresses
    assert_equal "203.0.113.8", Netmon::ProbeTarget.parse("203.0.113.8")
    assert_equal "10.0.0.20", Netmon::ProbeTarget.parse("10.0.0.20")
    assert_equal "2001:db8::8", Netmon::ProbeTarget.parse("2001:db8::8")
  end

  def test_targets_reject_options_hostnames_ranges_and_special_addresses
    ["-V", "example.com", "203.0.113.8/24", " 203.0.113.8", "127.0.0.1", "::1", "0.0.0.0",
     "169.254.169.254", "fe80::1", "fe80::1%eth0", "224.0.0.1", "ff02::1", "::ffff:127.0.0.1"].each do |value|
      assert_nil Netmon::ProbeTarget.parse(value), value
    end
  end

  def test_command_captures_success_and_rejects_failure
    assert_equal "ok", Netmon::BoundedCommand.capture(RbConfig.ruby, "-e", "print 'ok'", timeout: 3)
    assert_nil Netmon::BoundedCommand.capture(RbConfig.ruby, "-e", "exit 1", timeout: 3)
  end

  def test_command_output_is_bounded
    assert_nil Netmon::BoundedCommand.capture(RbConfig.ruby, "-e", "print 'a' * 100000; sleep 10", timeout: 3, max_bytes: 1024)
  end

  def test_timeout_includes_process_that_closes_output_early
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_nil Netmon::BoundedCommand.capture(RbConfig.ruby, "-e", "STDOUT.close; STDERR.close; sleep 10", timeout: 0.5)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
  end

  def test_cancellation_terminates_running_child
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    cancel = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > 0.3 }
    assert_nil Netmon::BoundedCommand.capture(RbConfig.ruby, "-e", "sleep 10", timeout: 5, cancelled: cancel)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
  end
end
