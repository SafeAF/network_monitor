# frozen_string_literal: true

class AddDnsCorrelationFieldsToConnections < ActiveRecord::Migration[8.0]
  def change
    add_column :connections, :last_domain, :string
    add_column :connections, :last_domain_observed_at, :datetime

    add_index :connections, :last_domain
    add_index :connections, :last_domain_observed_at
  end
end
