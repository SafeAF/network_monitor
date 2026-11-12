# frozen_string_literal: true

class HostScoreRefreshJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = true
  retry_on StandardError, wait: 5.seconds, attempts: 3
  BATCH_SIZE = 100

  def perform(remote_host_id, after_id = 0, through_id = nil)
    host = RemoteHost.find_by(id: remote_host_id)
    return unless host
    through_id ||= Connection.where(dst_ip: host.ip).maximum(:id)
    return unless through_id

    now = Time.current
    rows = Connection.where(dst_ip: host.ip, id: (after_id + 1)..through_id)
      .where("last_seen_at >= ? AND last_seen_at <= ?", now - 10.minutes, now)
      .order(:id).limit(BATCH_SIZE).to_a
    rows.each do |row|
      Connection.transaction do
        connection = Connection.lock.find_by(id: row.id, dst_ip: host.ip)
        next unless connection && connection.last_seen_at.between?(now - 10.minutes, now)
        device = Device.find_by(ip: connection.src_ip)
        next unless device

        Netmon::Anomaly::Detection.call(connection: connection, device: device, remote_host: host,
          now: connection.last_seen_at)
      end
    end
    if rows.length == BATCH_SIZE && rows.last.id < through_id
      self.class.perform_later(remote_host_id, rows.last.id, through_id)
    end
  end
end
