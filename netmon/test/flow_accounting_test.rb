# frozen_string_literal: true

require "minitest/autorun"
require_relative "../app/lib/netmon/event_contract"
require_relative "../app/lib/netmon/flow_accounting"

class FlowAccountingTest < Minitest::Test
  def setup
    @now = Time.iso8601("2026-11-12T12:00:00Z")
  end

  def advance(previous = nil, at: @now, terminal: false, **counters)
    Netmon::FlowAccounting.advance(previous: previous, counters: counters.transform_keys(&:to_s), observed_at: at, terminal: terminal)
  end

  def state(result, at: @now, closed: false)
    { counters: result.counters, observed_at: at, closed: closed }
  end

  def test_new_and_destroy_credit_the_full_total_and_one_connection
    first = advance(bytes_orig: 100, bytes_reply: 50, packets_orig: 2, packets_reply: 1)
    last = advance(state(first), at: @now + 5, terminal: true, bytes_orig: 1000, bytes_reply: 200, packets_orig: 20, packets_reply: 4)
    assert_equal [1, 0], [first.count_delta, last.count_delta]
    assert_equal 1000, first.deltas["bytes_orig"] + last.deltas["bytes_orig"]
    assert_equal 200, first.deltas["bytes_reply"] + last.deltas["bytes_reply"]
    assert_equal 20, first.deltas["packets_orig"] + last.deltas["packets_orig"]
  end

  def test_destroy_only_is_a_complete_observation_not_a_zero_baseline
    result = advance(terminal: true, bytes_orig: 10000, bytes_reply: 500, packets_orig: 100, packets_reply: 5)
    assert_equal 1, result.count_delta
    assert_equal result.counters, result.deltas
    refute result.stale
  end

  def test_repeated_observation_under_another_event_id_does_not_repeat_deltas
    first = advance(bytes_orig: 100)
    repeated = advance(state(first), bytes_orig: 100)
    assert_equal 0, repeated.count_delta
    assert repeated.deltas.values.all?(&:zero?)
  end

  def test_counter_regression_cannot_lower_a_high_water_mark
    first = advance(bytes_orig: 100, packets_orig: 10)
    assert_raises(Netmon::EventContract::Invalid) { advance(state(first), at: @now + 1, bytes_orig: 50) }
    assert_raises(Netmon::EventContract::Invalid) { advance(state(first), at: @now + 1, packets_orig: 5) }
    later = advance(state(first), at: @now + 2, bytes_orig: 150)
    assert_equal 50, later.deltas["bytes_orig"]
  end

  def test_missing_counters_preserve_prior_values
    first = advance(bytes_orig: 100, bytes_reply: 200)
    result = advance(state(first), at: @now + 1, bytes_orig: 150)
    assert_equal 200, result.counters["bytes_reply"]
    assert_equal 0, result.deltas["bytes_reply"]
    assert_equal 50, result.deltas["bytes_orig"]
  end

  def test_old_observations_and_new_after_terminal_at_the_same_time_are_stale
    last = advance(terminal: true, bytes_orig: 1000)
    [@now - 1, @now].each do |at|
      result = advance(state(last, closed: true), at: at, bytes_orig: 1)
      assert result.stale
      assert_equal 0, result.count_delta
      assert result.deltas.values.all?(&:zero?)
    end
  end

  def test_terminal_can_follow_new_in_the_same_clock_tick
    first = advance(bytes_orig: 100)
    result = advance(state(first), terminal: true, bytes_orig: 1000)
    assert_equal 900, result.deltas["bytes_orig"]
    refute result.stale
  end

  def test_a_closed_identity_cannot_be_reopened_and_new_identity_starts_at_zero
    last = advance(terminal: true, bytes_orig: 1000)
    error = assert_raises(Netmon::EventContract::Invalid) { advance(state(last, closed: true), at: @now + 1, bytes_orig: 10) }
    assert_equal "flow_already_closed", error.message
    next_lifetime = advance(at: @now + 1, bytes_orig: 10)
    assert_equal 10, next_lifetime.deltas["bytes_orig"]
    assert_equal 1, next_lifetime.count_delta
  end
end
