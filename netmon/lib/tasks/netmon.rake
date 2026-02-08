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
end
