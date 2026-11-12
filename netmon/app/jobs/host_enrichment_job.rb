# frozen_string_literal: true

class HostEnrichmentJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = true
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(remote_host_id)
    host = RemoteHost.find_by(id: remote_host_id)
    return unless host && Netmon::EventContract.ip?(host.ip)
    return unless Netmon::HostEnricher.due?(host)

    # External I/O happens before the short metadata-only save transaction.
    Netmon::HostEnricher.apply(host)
    host.save!
  end
end
