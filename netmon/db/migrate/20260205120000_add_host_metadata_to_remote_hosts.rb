# frozen_string_literal: true

class AddHostMetadataToRemoteHosts < ActiveRecord::Migration[8.0]
  def change
    add_column :remote_hosts, :rdns_name, :string
    add_column :remote_hosts, :whois_name, :string
    add_column :remote_hosts, :whois_raw_line, :string
    add_column :remote_hosts, :rdns_checked_at, :datetime
    add_column :remote_hosts, :whois_checked_at, :datetime
  end
end
