# frozen_string_literal: true

module Netmon
  module Dns
    class Prune
      RETENTION_DAYS = 30

      Result = Struct.new(:dns_events_deleted, :dns_event_answers_deleted, :cutoff, keyword_init: true)

      def self.call(now: Time.current, retention_days: RETENTION_DAYS)
        cutoff = now - retention_days.days
        old_event_ids = DnsEvent.where("observed_at < ?", cutoff).select(:id)
        dns_event_answers_deleted = DnsEventAnswer.where(dns_event_id: old_event_ids).delete_all
        dns_events_deleted = DnsEvent.where(id: old_event_ids).delete_all

        Result.new(
          dns_events_deleted: dns_events_deleted,
          dns_event_answers_deleted: dns_event_answers_deleted,
          cutoff: cutoff
        )
      end
    end
  end
end
