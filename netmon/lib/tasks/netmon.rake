# frozen_string_literal: true

namespace :netmon do
  desc "Run a single snapshot ingestion pass"
  task ingest_once: :environment do
    result = Netmon::ReconcileSnapshot.run

    puts "remote_hosts_upserted=#{result.remote_hosts_upserted} " \
         "connections_upserted=#{result.connections_upserted} " \
         "connections_deleted=#{result.connections_deleted}"
  end

  desc "Run continuous snapshot ingestion"
  task ingest_loop: :environment do
    Netmon::Daemon.run
  end

  desc "Recompute per-device baselines"
  task recompute_baselines: :environment do
    Netmon::Baseline::Recompute.run
  end

  desc "Cleanup old Netmon records"
  task cleanup: :environment do
    config = begin
      path = Rails.root.join("config/netmon.yml")
      YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false) || {}
    rescue Errno::ENOENT
      {}
    end

    cleanup = config.fetch("cleanup", {})
    now = Time.current
    device_minutes_days = (cleanup["device_minutes_days"] || 30).to_i
    remote_minutes_days = (cleanup["remote_host_minutes_days"] || 30).to_i
    anomaly_hits_days = (cleanup["anomaly_hits_days"] || 90).to_i
    incidents_days = (cleanup["incidents_days"] || 90).to_i

    device_cutoff = now - device_minutes_days.days
    remote_cutoff = now - remote_minutes_days.days
    anomaly_cutoff = now - anomaly_hits_days.days
    incident_cutoff = now - incidents_days.days

    device_deleted = DeviceMinute.where("bucket_ts < ?", device_cutoff).delete_all
    remote_deleted = RemoteHostMinute.where("bucket_ts < ?", remote_cutoff).delete_all
    anomaly_deleted = AnomalyHit.where("occurred_at < ?", anomaly_cutoff).delete_all
    incident_deleted = Incident.where("last_seen_at < ? OR (acknowledged_at IS NOT NULL AND acknowledged_at < ?)",
                                      incident_cutoff, incident_cutoff).delete_all

    puts "device_minutes_deleted=#{device_deleted} " \
         "remote_host_minutes_deleted=#{remote_deleted} " \
         "anomaly_hits_deleted=#{anomaly_deleted} " \
         "incidents_deleted=#{incident_deleted}"
  end
end
