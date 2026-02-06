# frozen_string_literal: true

class AddWhoisAsnToRemoteHosts < ActiveRecord::Migration[8.0]
  def change
    add_column :remote_hosts, :whois_asn, :string
  end
end
