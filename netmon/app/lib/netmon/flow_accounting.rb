# frozen_string_literal: true

module Netmon
  module FlowAccounting
    COUNTERS = %w[bytes_orig bytes_reply packets_orig packets_reply].freeze
    Result = Struct.new(:counters, :deltas, :count_delta, :stale, keyword_init: true)

    def self.advance(previous:, counters:, observed_at:, terminal:)
      old = previous ? previous.fetch(:counters) : COUNTERS.to_h { |key| [key, 0] }
      if previous && (observed_at < previous.fetch(:observed_at) ||
        (previous[:closed] && !terminal && observed_at <= previous.fetch(:observed_at)))
        return Result.new(counters: old, deltas: COUNTERS.to_h { |key| [key, 0] }, count_delta: 0, stale: true)
      end
      raise EventContract::Invalid, "flow_already_closed" if previous && previous[:closed] && !terminal

      current = COUNTERS.to_h { |key| [key, counters[key].nil? ? old.fetch(key) : Integer(counters[key])] }
      if COUNTERS.any? { |key| current.fetch(key) < old.fetch(key) }
        # A counter reset requires a new lifetime identity. Lowering the
        # high-water mark would count the next increase for a second time.
        raise EventContract::Invalid, "flow_counter_regression"
      end
      Result.new(counters: current, deltas: COUNTERS.to_h { |key| [key, current.fetch(key) - old.fetch(key)] },
        count_delta: previous ? 0 : 1, stale: false)
    end
  end
end
