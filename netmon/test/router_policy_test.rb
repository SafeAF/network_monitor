# frozen_string_literal: true

require "minitest/autorun"
require_relative "../app/lib/netmon/event_contract"
require_relative "../app/lib/netmon/router_policy"

class RouterPolicyTest < Minitest::Test
  def test_requires_an_explicit_valid_router_configuration
    [nil, "", " router-1", "router\n", "a" * 65, 42].each do |id|
      error = assert_raises(Netmon::RouterPolicy::Unavailable) do
        Netmon::RouterPolicy.authorize!("router-1", env: { "NETMON_ROUTER_ID" => id })
      end
      assert_equal "router_not_configured", error.message
    end
    assert_raises(Netmon::RouterPolicy::Unavailable) { Netmon::RouterPolicy.authorize!("router-1", env: {}) }
  end

  def test_accepts_the_configured_identity_with_or_without_a_database_binding
    [nil, "router-1"].each do |bound|
      assert_equal "router-1", Netmon::RouterPolicy.authorize!("router-1",
        bound_router_id: bound, env: { "NETMON_ROUTER_ID" => "router-1" })
    end
  end

  def test_rejects_a_different_router_even_before_the_first_binding
    [nil, "router-1"].each do |bound|
      error = assert_raises(Netmon::RouterPolicy::Mismatch) do
        Netmon::RouterPolicy.authorize!("router-2", bound_router_id: bound, env: { "NETMON_ROUTER_ID" => "router-1" })
      end
      assert_equal "router_mismatch", error.message
    end
  end

  def test_configuration_changes_cannot_reassign_existing_ip_keyed_data
    error = assert_raises(Netmon::RouterPolicy::Unavailable) do
      Netmon::RouterPolicy.authorize!("router-2", bound_router_id: "router-1", env: { "NETMON_ROUTER_ID" => "router-2" })
    end
    assert_equal "router_binding_conflict", error.message
  end
end
