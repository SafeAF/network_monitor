# frozen_string_literal: true

require "minitest/autorun"
require_relative "../app/lib/netmon/event_contract"
require_relative "../lib/netmon/request_body_limit"

class EventContractTest < Minitest::Test
  def setup
    @now = Time.iso8601("2026-11-12T12:00:00Z")
    @event = { "type" => "flow", "ts" => @now.iso8601, "data" => {
      "src_ip" => "10.0.0.20", "dst_ip" => "203.0.113.8", "l4proto" => 6,
      "src_port" => 50000, "dst_port" => 443, "bytes_orig" => 100
    } }
  end

  def validate(event = @event)
    Netmon::EventContract.event!(event, now: @now)
  end

  def test_batch_requires_an_array_and_bounded_router_identity
    [nil, [], {}, { "router_id" => "r", "events" => {} },
     { "router_id" => "\nrouter", "events" => [] },
     { "router_id" => "r", "events" => Array.new(501) }].each do |payload|
      assert_raises(Netmon::EventContract::Invalid) { Netmon::EventContract.batch!(payload) }
    end
    assert_equal ["router-1", []], Netmon::EventContract.batch!({ "router_id" => "router-1", "events" => [] })
  end

  def test_legacy_identity_is_stable_across_json_key_order_and_precise_timestamps
    first = validate
    reordered = @event.merge("data" => @event["data"].to_a.reverse.to_h)
    assert_equal first, validate(reordered)
    nanos = @event.merge("ts" => "2026-11-12T12:00:00.000000001Z")
    refute_equal first[:event_uid], validate(nanos)[:event_uid]
    refute_equal first[:payload_digest], validate(@event.merge("data" => @event["data"].merge("bytes_orig" => 101)))[:payload_digest]
  end

  def test_explicit_identity_is_preserved
    assert_equal "event-1", validate(@event.merge("id" => "event-1"))[:event_uid]
    ["", "a" * 129, "bad/id", 42, false, nil].each do |id|
      assert_raises(Netmon::EventContract::Invalid) { validate(@event.merge("id" => id)) }
    end
  end

  def test_rejects_bad_shapes_types_ips_ports_and_counters
    [nil, [], "x", { "type" => "unknown" }, @event.merge("data" => [])].each do |event|
      assert_raises(Netmon::EventContract::Invalid) { validate(event) }
    end
    { "src_ip" => ["example.com", "10.0.0.0/24", "-V"], "dst_port" => [-1, 65536, "443xyz"],
      "l4proto" => [-1, 256, "unknown"], "bytes_orig" => [-1, 2**63, 1.5] }.each do |key, values|
      values.each do |value|
        assert_raises(Netmon::EventContract::Invalid) { validate(@event.merge("data" => @event["data"].merge(key => value))) }
      end
    end
    assert_equal "flow", validate(@event.merge("data" => @event["data"].merge("dst_port" => "443")))[:event_type]
  end

  def test_replay_window_and_clock_skew_are_enforced
    [nil, false, "yesterday", "2026-11-12", "2026-13-12T12:00:00Z", "2026-02-30T12:00:00Z", (@now - 31*86400).iso8601, (@now + 301).iso8601].each do |ts|
      assert_raises(Netmon::EventContract::Invalid) { validate(@event.merge("ts" => ts)) }
    end
    assert validate(@event.merge("ts" => (@now - 29*86400).iso8601))
  end

  def test_dns_validation_and_non_address_answers
    dns = { "type" => "dns_response", "ts" => @now.iso8601,
      "data" => { "client_ip" => "10.0.0.20", "qname" => "api.example.com", "qtype" => "A",
        "answers" => [{ "type" => "A", "data" => "203.0.113.8" }, { "type" => "TXT", "data" => "metadata" }] } }
    assert_equal "dns_response", validate(dns)[:event_type]
    ["not-an-array", Array.new(65) { { "type" => "A", "data" => "203.0.113.8" } },
     [{ "type" => "A", "data" => "invalid" }], [{ "type" => "A", "data" => "2001:db8::1" }]].each do |answers|
      assert_raises(Netmon::EventContract::Invalid) { validate(dns.merge("data" => dns["data"].merge("answers" => answers))) }
    end
  end

  def test_event_fields_and_nesting_are_bounded
    oversized = @event.merge("data" => @event["data"].merge("extra" => "x" * 1025))
    assert_raises(Netmon::EventContract::Invalid) { validate(oversized) }
    nested = "x"
    7.times { nested = { "child" => nested } }
    assert_raises(Netmon::EventContract::Invalid) { validate(@event.merge("data" => { "nested" => nested })) }
    assert_raises(Netmon::EventContract::Invalid) { validate(@event.merge("padding" => "x" * 32768)) }
  end

  def test_body_guard_limits_actual_bytes_not_just_content_length
    called = false
    app = Netmon::RequestBodyLimit.new(->(env) { called = true; [200, {}, [env["rack.input"].read]] })
    response = app.call({ "CONTENT_LENGTH" => "1", "rack.input" => StringIO.new("x" * (Netmon::RequestBodyLimit::MAX_BYTES + 1)) })
    assert_equal 413, response[0]
    refute called
    assert_equal false, JSON.parse(response[2].first)["retryable"]
    assert_equal 200, app.call({ "rack.input" => StringIO.new("") })[0]
    assert_equal ["ok"], app.call({ "rack.input" => StringIO.new("ok") })[2]
  end

  def test_declared_oversized_body_is_rejected_without_reading_it
    input = Object.new
    def input.read(*)
      raise "oversized body must not be read"
    end
    app = Netmon::RequestBodyLimit.new(->(*) { raise "must not reach Rails" })
    assert_equal 413, app.call({ "CONTENT_LENGTH" => (Netmon::RequestBodyLimit::MAX_BYTES + 1).to_s, "rack.input" => input })[0]
  end
end
